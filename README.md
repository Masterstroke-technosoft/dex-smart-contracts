# Rapiddex Smart Contracts

Core smart contracts for Rapiddex, a Uniswap V3-based decentralized exchange on **MST Mainnet**.
These contracts manage pool creation, swaps, liquidity positions, on-chain state storage, and
wrapped native token interaction.

> **Addresses in this file are generated from deployment output and verified against on-chain
> runtime bytecode.** Do not hand-edit them. [`deployments.json`](./deployments.json) is the
> canonical machine-readable manifest that front-ends and integrations should read.

---

## Network

- **Network name**: MST Mainnet
- **Chain ID**: `4646` (`0x1226`)
- **Native currency**: MSTC
- **RPC URL**: `https://mariorpc.mstblockchain.com`
- **WS RPC URL**: `wss://mariorpc.mstblockchain.com`

---

## Contracts

All source contracts live in `src/`.

* **`src/WMSTC.sol`** (`Wrapped MSTC`, `WMSTC`) — Canonical wrapped native token, modelled on WETH9.
  The periphery operates only on ERC-20 tokens, so wrapping is required to trade the native
  currency. The periphery refers to this address internally as `WETH9`; that is upstream Uniswap
  naming, not a second token.
* **`src/MUSDC.sol`** (`MUSD Coin`, `MUSDC`) — Six-decimal stablecoin used to bootstrap liquidity.
  Owner-controlled minting bounded by an immutable `maxSupply`, plus pausing and a blacklist.
* **`src/MinimalPositionDescriptor.sol`** — ERC-721 metadata for liquidity position NFTs, returned
  as a `data:application/json;base64` URI. A lightweight alternative to full on-chain SVG
  generation. Metadata can be locked permanently with `freezeMetadata()`.
* **`src/LPStateStorage.sol`** — Owner-written snapshot of a pool address and one LP position,
  consumed by indexing and backend services. Not read by any on-chain contract.

The Uniswap V3 core and periphery forks are vendored under `lib/v3-core-main` and
`lib/v3-periphery-main` and compile under Solidity 0.7.6.

---

## Deployed addresses

| Contract | Address |
| :--- | :--- |
| **WMSTC** | `0x56EdE2EbC789fD31f978DdA79D54d6B9e42f9eCD` |
| **MUSDC** | `0x3ac2105Fe12e4c75B3A6e5e5508A3F6716A9e8Ee` |
| **RapiddexV3Factory** | `0xd6987F8CabE051a73c8f5e0D62bb9F8E8D1DE478` |
| **MinimalPositionDescriptor** | `0xFeFE24529574df0247b32027118675a62bc0451E` |
| **NonfungiblePositionManager** | `0xDdc9CD08Ec31e3a2e4DD169f067e367578ae6680` |
| **SwapRouter** | `0x3d74C817c85C3Fe463360EE3974c2715ADFFb6F7` |
| **QuoterV2** | `0x1350EfE8B3cd9cB0cb6D8c18cFF517dCc34e0C38` |
| **LPStateStorage** | `0x1D966C1fFA4733bB609dEc55D749437bc9DDE285` |

Every address above was verified after deployment: runtime bytecode compared byte-for-byte
against the compiled source, immutables checked, and a distinguishing function called on each.

### Superseded — do not integrate against these

Earlier deployments remain live on-chain and will accept liquidity, but are defective or
abandoned. They are indistinguishable from the canonical contracts by on-chain properties alone
(same factory, same wrapped token, same ERC-721 name and symbol), so integrations must resolve
addresses from `deployments.json` rather than by discovery. The full annotated list is in that
file under `doNotUse`; the two most dangerous are position managers whose metadata can never be
repaired, because `NonfungiblePositionManager._tokenDescriptor` is immutable:

| Address | Contract | Problem |
| :--- | :--- | :--- |
| `0x672826C1c56B3C1492b86f6b3A184e1ae97A0f8F` | NonfungiblePositionManager | descriptor address has no code |
| `0x13391cE70a97345Cf2913fE99D5C176744222F54` | NonfungiblePositionManager | descriptor getters revert |
| `0x31e5fdD5009a7b9a09A50D877B7d0D55c7b7031d` | NonfungiblePositionManager | functional, but its ERC721 base was an unpinned copy with no upstream provenance — see [Dependencies](#dependencies) |

---

## Build target

`foundry.toml` pins `evm_version = "shanghai"`. **Do not raise this without confirming the chain's
hardfork first.**

MST Mainnet's EVM predates Cancun and does not implement `MCOPY`. Solidity 0.8.24+ emits `MCOPY`
whenever a function copies a dynamic `string` or `bytes` in memory — *including simply returning
one from an external function*. Building against `cancun` therefore produces contracts that deploy
successfully but revert with `invalid opcode: MCOPY` on any metadata read. This is not
hypothetical: it is how an earlier deployment's `name()` and `symbol()` were bricked.

`PUSH0` (Shanghai) *is* supported by the chain and is already in use, so `shanghai` is correct.

**Before any redeploy, manually re-check two things** — there is no automated guard for either:
1. `evm_version` in `foundry.toml` is still `"shanghai"`, not `"cancun"` or higher.
2. `POOL_INIT_CODE_HASH` in `lib/v3-periphery-main/contracts/libraries/PoolAddress.sol` still
   matches `keccak256(forge inspect RapiddexV3Pool bytecode)`. A stale hash makes the router and
   position manager address pools that do not exist, with no failure until a user tries to trade.

### Dependencies

OpenZeppelin is pinned as two git submodules, matching the project's two Solidity generations —
both are real, tagged upstream releases, not vendored copies:

| Submodule | Version | Used by |
| :--- | :--- | :--- |
| `lib/openzeppelin-contracts-v5` | v5.1.0 (`69c8def5`) | `src/` (0.8.x): `MUSDC`, `MinimalPositionDescriptor` |
| `lib/openzeppelin-contracts-v3` | v3.4.2 (`8e029609`) | `lib/v3-periphery-main` (0.7.6): `NonfungiblePositionManager`'s ERC-721 base |

The v3.4.2 pin replaced an earlier vendored copy that shared the same file layout and interfaces
but had no verifiable upstream provenance — no version tag, no commit reference, and 20–100% of
each file's content differed from any real OpenZeppelin release once compared. It was traced and
found not exploitable, but "traced and found nothing" is weaker than "a pinned, audited release,"
so it was replaced rather than kept. The two submodules are **not** interchangeable with each
other; a context-scoped remapping in `foundry.toml` keeps them apart.

Clone with submodules:

```bash
git clone --recursive <repo>
# or, in an existing clone:
git submodule update --init --recursive
```

---

## Environment setup

Create a `.env` file in the root of this folder. It is gitignored (`.env*`), and must never be
committed.

```env
RPC_URL=https://mariorpc.mstblockchain.com
WS_RPC_URL=wss://mariorpc.mstblockchain.com
CHAIN_ID=4646
PRIVATE_KEY=0x<your_deployer_private_key>

WMSTC_ADDRESS=0x56EdE2EbC789fD31f978DdA79D54d6B9e42f9eCD
MUSDC_ADDRESS=0x3ac2105Fe12e4c75B3A6e5e5508A3F6716A9e8Ee
V3_FACTORY_ADDRESS=0xd6987F8CabE051a73c8f5e0D62bb9F8E8D1DE478
POSITION_DESCRIPTOR_ADDRESS=0xFeFE24529574df0247b32027118675a62bc0451E
POSITION_MANAGER_ADDRESS=0xDdc9CD08Ec31e3a2e4DD169f067e367578ae6680
SWAP_ROUTER_ADDRESS=0x3d74C817c85C3Fe463360EE3974c2715ADFFb6F7
QUOTER_V2_ADDRESS=0x1350EfE8B3cd9cB0cb6D8c18cFF517dCc34e0C38
LP_STATE_STORAGE_ADDRESS=0x1D966C1fFA4733bB609dEc55D749437bc9DDE285
```

`PRIVATE_KEY` must be `0x`-prefixed — Foundry's `vm.envUint` rejects a bare hex string.

---

## Commands

```bash
forge build     # compile
```

### Deploying

```bash
forge script script/DeployMainnet.s.sol:DeployMainnet \
  --rpc-url https://mariorpc.mstblockchain.com \
  --broadcast --legacy --gas-price 5000000000
```

`--legacy` and an explicit `--gas-price` are required. The chain reports an EIP-1559 base fee of
zero, which makes Foundry's default fee estimation produce transactions priced at ~1 wei that are
never mined.

### Post-deploy checklist

Already done:

- Blacklist protection set for `SwapRouter` and the current `NonfungiblePositionManager`. **This
  is per-address and does not carry over** — re-run it after any future position-manager redeploy.

Still outstanding:

1. **Protect each new pool**: `MUSDC.setBlacklistProtection(pool, true)`, as pools are created.
   A blacklisted pool cannot send `MUSDC`, which strands every LP's capital in it.
2. **Raise the oracle**: `pool.increaseObservationCardinalityNext(n)`. Pools open with cardinality
   1 and store no usable price history, so any TWAP read is effectively a manipulable spot price.
3. **Move admin roles to a multisig** — `MUSDC` owner, `MUSDC` blacklister, factory owner,
   descriptor owner and `LPStateStorage` owner. A single EOA currently holds all of them, and can
   mint up to `maxSupply`, pause transfers, blacklist addresses and control the fee switch.
   Ownership transfers are two-step; the nominee must call `acceptOwnership()`.
4. **Freeze position metadata** once final: `MinimalPositionDescriptor.freezeMetadata()`.
5. **Regenerate** `deployments.json` and the table above from deployment output.

### Debugging with cast

```bash
# pool price / tick state
cast call <POOL_ADDRESS> "slot0()(uint160,int24,uint16,uint16,uint16,uint8,bool)" \
  --rpc-url https://mariorpc.mstblockchain.com

# token balance
cast call 0x3ac2105Fe12e4c75B3A6e5e5508A3F6716A9e8Ee "balanceOf(address)(uint256)" <USER_ADDRESS> \
  --rpc-url https://mariorpc.mstblockchain.com
```

---

## Acknowledgements

Rapiddex is a fork of the **Uniswap V3 Protocol** ([Uniswap V3 Core](https://github.com/Uniswap/v3-core) & [Uniswap V3 Periphery](https://github.com/Uniswap/v3-periphery)), adapted and deployed for the MST network. We gratefully acknowledge **Uniswap Labs** (© 2021 Uniswap Labs) for their pioneering work and open-source architecture.
