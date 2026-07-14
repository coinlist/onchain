# CoinList — Ethereum Contracts

Solidity contracts that power CoinList token sales. 

### Token Sales
The core flow is a two-stage pipeline: users' funds are gathered in a **Fund** (`commit`), and tokens are
later handed out by a **Distribution** (`distribute`).

### Token Swaps
A separate **Swap** family provides an alternate, integration-driven acquisition path.

### Deployment and Tracking
Automated deployments of contracts are available via the **Factory** with their locations known to the **Registry**

Contracts are written in Solidity `0.8.34`, built and tested with
[Foundry](https://book.getfoundry.sh/), and depend on [solady](https://github.com/Vectorized/solady)
via [soldeer](https://soldeer.xyz/).

## Core concepts

### Sale id

Every deployed sale contract carries a `bytes32 id` — the unique identifier of the sale it serves.
The same `id` ties together a sale's Fund and Dist deployments.

### Kinds

Each deployable contract reports a `KIND` constant. The Registry keys deployments by `(id, kind)`,
so a single sale `id` can resolve to one contract of each kind.

| KIND | Contract          | Role in the system                                   |
|:-----|:------------------|:-----------------------------------------------------|
| `0`  | Sale Fund         | Collects funding (`commit`) and returns it (`remit`) |
| `1`  | Sale Distribution | Pushes a token out to users (`distribute`)           |
| `2`  | Swap              | Swaps an input token for an output token             |

Contracts also expose a `VERSION` constant, bumped as features are added/refined.

### Registry key

```
registered[id][kind] => deployment address
```

A `(id, kind)` slot may be set once (registration reverts if non-zero) and cleared
via deregistration.


## Contracts

### Deployments

| Environment | Chain | Registry | Sale Factory |
|-------------|-------|----------|--------------|
| Beta | Ethereum Mainnet | — | — |
| Beta | Ethereum Sepolia | [`0x7a346b350e4D1F8A2878182aED11dc9b417274B7`](https://sepolia.etherscan.io/address/0x7a346b350e4D1F8A2878182aED11dc9b417274B7) | [`0xb1C46E187DbA2833aC9b219fD396c233e4f92A9D`](https://sepolia.etherscan.io/address/0xb1C46E187DbA2833aC9b219fD396c233e4f92A9D) |
| Beta | Base Mainnet | — | — |
| Beta | Base Sepolia | [`0xe3261636cd943722F157336AEAABa8B7D71a6495`](https://sepolia.basescan.org/address/0xe3261636cd943722F157336AEAABa8B7D71a6495) | [`0xE5Ae8f0C646dBc1111DbdED801A03Cf7CE0508b1`](https://sepolia.basescan.org/address/0xE5Ae8f0C646dBc1111DbdED801A03Cf7CE0508b1) |
| Prod | Ethereum Mainnet | [`0xF90a1A7ECa0880fBCd061b4819371a5A2989Bf2a`](https://etherscan.io/address/0xF90a1A7ECa0880fBCd061b4819371a5A2989Bf2a) | [`0x71f9727Dfb3fd000d8eCaf66866c3EF8d22012A9`](https://etherscan.io/address/0x71f9727Dfb3fd000d8eCaf66866c3EF8d22012A9) |
| Prod | Ethereum Sepolia | [`0x6F0a9f4D109DDF34281216107B8c565871F85041`](https://sepolia.etherscan.io/address/0x6F0a9f4D109DDF34281216107B8c565871F85041) | [`0xf7610942c87B05892335F08ce5337BC0E3493292`](https://sepolia.etherscan.io/address/0xf7610942c87B05892335F08ce5337BC0E3493292) |
| Prod | Base Mainnet | [`0xD627B38F6188038EDA7e13Cb7126CF7c0f154B84`](https://basescan.org/address/0xD627B38F6188038EDA7e13Cb7126CF7c0f154B84) | [`0xe3261636cd943722F157336AEAABa8B7D71a6495`](https://basescan.org/address/0xe3261636cd943722F157336AEAABa8B7D71a6495) |
| Prod | Base Sepolia | [`0xf6844473a6079f4992a156b67Ff4C70605d95B84`](https://sepolia.basescan.org/address/0xf6844473a6079f4992a156b67Ff4C70605d95B84) | [`0x7A35FFC54381F688f44997042bae03dE67bE8493`](https://sepolia.basescan.org/address/0x7A35FFC54381F688f44997042bae03dE67bE8493) |

### Registry — `src/registry/Registry.sol`

Onchain directory mapping `(id, kind)` to a deployment address.

### Factory — `src/factory/Factory.sol`

Deploys Sale contracts, hands ownership to `deploymentOwner`, and registers them.

### TokenSaleFund — `src/sale/TokenSaleFund.sol`

Collects funding per `(user, option, token)`. Tracks `SaleTotal { commitCount, commitSum, remitCount, remitSum }`;

### TokenSaleDist — `src/sale/TokenSaleDist.sol`

Distributes a single, fixed `distToken`. Inherits `Stopable`, `OwnableRoles`.
Tracks `DistTotal { distCount, distSum }`.

### TokenSwap — `src/swap/TokenSwap.sol`

Abstract base for performing onchain token swaps. Tracks
`SwapTotal { inputSum, feeSum, outputSum, count }`.

## Shared library — `lib/shared`

Generic primitives used across `src/`.

- **`operable/Operable.sol`** — the newer lifecycle mixin (`pause` / `stop` / `status`,
  `active` modifier).
- **`stopable/Stopable.sol`** — the older lifecycle mixin (`stop(level)`, `started`
  modifier).
- **`Utils.sol`** — `isContract(address)`, a free function using `extcodesize`.
- **`TestToken.sol`** — a mintable solady `ERC20` used only by the test suite.

## Build & test

```sh
forge soldeer install   # populate dependencies/ from soldeer.lock

forge build
forge test
```

A `ci` profile (`FOUNDRY_PROFILE=ci`) raises verbosity for CI runs. RPC and Etherscan config for
`sepolia` / `anvil` is read from the environment (`SEPOLIA_RPC_URL`, `ANVIL_RPC_URL`,
`ETHERSCAN_API_KEY`).
