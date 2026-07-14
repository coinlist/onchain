// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import {TokenSaleFund} from "sale/TokenSaleFund.sol";
import {IPutManager, IFlyingTulipFund} from "./IFlyingTulipFund.sol";
import {SaleTotal as Total} from "sale/Types.sol";

contract FlyingTulipFund is IFlyingTulipFund, TokenSaleFund {
    // ************************ State ************************************************

    /// @dev proof amount sent to FT in invest call
    uint256 private constant PROOF_AMOUNT = 0;
    /// @dev the type issued with batch related events
    uint256 public ftBatchType;
    /// @dev a WL sent to FT on invest call, provided by FT
    bytes32[] private _proofWl;
    /// @dev the FT PutManager whose invest method we will be calling
    address public putManagerAddress;
    /// @dev flag which allows owner to control investFor commit balance checks
    bool public commitBalanceOverride;

    constructor(uint256 min, bytes32 saleId, address pma) TokenSaleFund(min, saleId) {
        // ivariant: put manager address is not zero
        require(pma != address(0), PutManagerIsZero());

        ftBatchType = uint256(saleId);
        putManagerAddress = pma;
    }

    // ************************ Public API *******************************************

    function isProofWlSet() external view returns (bool) {
        return _proofWl.length > 0;
    }

    // ************************ Admin API *******************************************

    function investFor(address user, bytes32 option, address token, uint256 amount)
        external
        started(REMIT_LEVEL)
        onlyRoles(REMIT_LEVEL)
        returns (bool)
    {
        // invariant: Wl has been set
        require(_proofWl.length > 0, ProofWlNotSet());
        // invariant: amount >= minCommit
        require(amount >= minCommit, InsufficientAmount(amount, minCommit));
        // invariant: user has sufficient commit balance (when not overridden)
        if (!commitBalanceOverride) {
            Total memory data = _totals[user][option][token];
            require(data.commitSum - data.remitSum >= amount, InsufficientCommitment(user, option, token));
        }

        // dev: we are assuming that an approve call has already been made to the putManagerAddress
        IPutManager(putManagerAddress).invest(token, amount, user, PROOF_AMOUNT, _proofWl);

        emit Invested(user, token, amount);

        return true;
    }

    function investFor(
        address[] calldata users,
        bytes32[] calldata options,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external started(REMIT_LEVEL) onlyRoles(REMIT_LEVEL) returns (bool) {
        // invariant: Wl has been set
        require(_proofWl.length > 0, ProofWlNotSet());

        uint256 batched = 0;
        uint256 len = users.length;

        // invariant: the lists are of the same length
        require(len == options.length && len == tokens.length && len == amounts.length, NonEquivalentListLength());

        for (uint256 i = 0; i < len; ++i) {
            address user = users[i];
            bytes32 option = options[i];
            address token = tokens[i];
            uint256 amount = amounts[i];

            Total memory data = _totals[user][option][token];

            // invariants: amount >= minCommit && user has sufficient commit balance (when not overridden)
            if (amount >= minCommit && (commitBalanceOverride || (data.commitSum - data.remitSum >= amount))) {
                try IPutManager(putManagerAddress).invest(token, amount, user, PROOF_AMOUNT, _proofWl) {
                    unchecked {
                        batched += 1;
                    }

                    emit Invested(user, token, amount);
                } catch {
                    emit BatchFail(ftBatchType, user, option, token, amount);
                }
            } else {
                emit BatchFail(ftBatchType, user, option, token, amount);
            }
        }

        emit Batched(ftBatchType, batched, len - batched);

        return true;
    }

    // ***************** Owner API *************************************************

    function setProofWl(bytes32[] calldata pwl) external onlyOwner returns (bool) {
        _proofWl = pwl;
        return true;
    }

    function toggleCommitBalanceOverride() external onlyOwner returns (bool) {
        commitBalanceOverride = !commitBalanceOverride;

        return true;
    }
}
