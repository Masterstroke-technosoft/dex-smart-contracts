# Rapiddex Smart Contracts

Core smart contracts for Rapiddex, a Rapiddex V3-based decentralized exchange deployed on MST Mainnet. These contracts manage pool creation, swaps, liquidity positions, and wrapped native token interaction.

## Technical Details (MST Mainnet)

Read these from [`deployments.json`](./deployments.json) rather than copying them;
the values below are a convenience copy of its `network` block.

- **Network Name**: MST Mainnet
- **Chain ID**: `4646`
- **Native Currency**: `MSTC`
- **RPC URL**: `https://mariorpc.mstblockchain.com`
- **WS RPC URL**: `wss://mariorpc.mstblockchain.com`

---

## Contract Directory Structure

All source contracts reside in the `src/` directory. Flattened copies are not kept in the repo: `forge verify-contract` submits standard-JSON input directly, and a checked-in flattened copy only drifts from the source it claims to mirror. Run `forge flatten src/<Contract>.sol` if an explorer ever needs one.

### Core Contracts

*   **`src/WMSTC.sol`** (`Wrapped MSTC`): Canonical wrapped native MSTC token, modeled on WETH9. Periphery contracts operate exclusively on ERC20 tokens, making `WMSTC` a requirement to interact with native MSTC on the platform. Diverges from WETH9 deliberately: `deposit` reverts on zero value and `transferFrom` reverts on a zero destination.
*   **`src/MinimalPositionDescriptor.sol`**: Metadata for liquidity position NFTs, returned as a `data:application/json;base64` URI. A lightweight alternative to full SVG generation libraries to save gas and deployment byte size. `freezeMetadata()` makes the base description permanently immutable.
*   **`src/RapidEXFeeRouter.sol`**: Optional fee-taking wrapper in front of `SwapRouter`. Takes a protocol fee (hard-capped at `MAX_FEE_BPS` = 100 bps) off the input token, then forwards the net amount to the router. Fee decreases apply immediately; increases must pass a 2-day timelock. Built and tested, **not yet deployed** — it is absent from `deployments.json`.

### The quote asset is not ours

The USD side of every pool is **USDC.e** — `Bridged USDC (Onestable Limited)`
at `0x349d9836dd52c25e61Ae745e3da0F8989De63745`, a third-party Circle
FiatTokenV2 behind an upgradeable proxy. There is no source file for it here
and RapidEX has no control over it.

This replaced `src/MUSDC.sol`, RapidEX's own mock stablecoin, which is retired
(see `doNotUse` in [`deployments.json`](./deployments.json)). Retiring it
removed six audit findings outright — they were all specific to that token —
but it did **not** remove the underlying risks; it moved them to an issuer
RapidEX cannot constrain:

| | MUSDC (retired) | USDC.e (now) |
| :--- | :--- | :--- |
| Who can mint | RapidEX admin, capped by `maxSupply` | Onestable Limited, uncapped by us |
| Who can pause | RapidEX admin | Onestable Limited |
| Who can blacklist | RapidEX blacklister | Onestable Limited |
| Pool freeze protection | `protectedFromBlacklist` exempted pools | **None. No exemption mechanism exists** |
| Upgradeable | No | **Yes, by the issuer** |
| `approve` race fix | `compareAndApprove` | Not available, and we cannot add it |

The two rows in bold are real, live exposures with no mitigation on our side:
Onestable Limited can blacklist a RapidEX pool and strand both sides of its
liquidity, and can change the token's logic under us. `script/SetupPools.s.sol`
feature-detects the missing exemption function and skips that step rather than
reverting. These are recorded as `risks` on the USDC.e entry in
`deployments.json`.

---

## Allowance Model

This covers **WMSTC**, the only token in a RapidEX pool that RapidEX controls.
USDC.e is third-party: its `approve` is a plain ERC-20 overwrite, the sandwich
below applies to it, and nothing here can change that — the same exposure
every USDC integration carries.

WMSTC is **ERC-20 compliant**: `approve` overwrites whatever allowance is
already there. It additionally exposes a race-free path:

```solidity
compareAndApprove(address spender, uint256 expected, uint256 value)
increaseAllowance(address spender, uint256 addedValue)
decreaseAllowance(address spender, uint256 subtractedValue)
```

**Use `compareAndApprove` to change an allowance that is already non-zero.**
It reverts unless the allowance is still exactly `expected`, which is what
closes the classic approval sandwich: a spender who front-runs your change to
spend the old allowance moves it off `expected`, so your new approval reverts
instead of stacking on top of the spend.

Requiring `approve` to pass through zero — a pattern this repo used earlier —
does **not** close that hole. The front-runner's drain leaves the allowance at
zero, the following zero→new write is perfectly legal, and the spender still
collects old + new. It only made the attack visible, at the cost of breaking
every integrator that did not reset first.

`permit` (EIP-2612) is an absolute set, exactly like `approve`, as the standard
specifies. Signed approvals carry no race-free variant; holders who need one
use `compareAndApprove`.

> ⚠️ **The live WMSTC predates this.** The deployed contract still enforces the
> old zero-first `approve` and has no `compareAndApprove`. Callers must keep
> using reset-then-approve against mainnet until WMSTC is redeployed — see
> `sourceDrift` in [`deployments.json`](./deployments.json). USDC.e will never
> gain `compareAndApprove`; it is not ours to change.

---

## Admin Model

**RapidEX is single-admin by design.** One externally owned key holds V3
factory ownership (the protocol fee switch), descriptor ownership and FeeRouter
ownership. This is the intended operating model — not a temporary state on the
way to shared custody — and multisig or timelocked governance is deliberately
declined.

Retiring MUSDC shrank this surface considerably: **RapidEX no longer controls
any token.** There is no mint, no pause and no blacklist key on our side; those
powers now sit with Onestable Limited for USDC.e, and WMSTC has no admin at all
(it is a permissionless wrapper with no owner).

What the admin key can do, and the accepted consequences:

| Power | Held by | If the key is compromised | If the key is lost |
| :--- | :--- | :--- | :--- |
| `factory.setOwner`, `setFeeProtocol`, `collectProtocol` | factory owner | Divert accrued protocol fees | Fee switch is frozen as-is |
| `descriptor.setBaseDescription` | descriptor owner | Rewrite every LP NFT's label | Metadata frozen as-is |
| FeeRouter `setFeeConfig`, `queueFeeIncrease` | FeeRouter owner | Raise the swap fee, capped at 100 bps after a 2-day timelock | Fee frozen as-is |

Note what is *not* in that table: no power to mint, freeze, or seize user
funds. The worst a compromised admin key achieves is diverting protocol fees
and defacing NFT metadata.

The guards that make a single key workable are in place and are **not** a
substitute for key hygiene:

- `renounceOwnership()` reverts on the FeeRouter, so the role cannot be dropped.
- Ownership transfer is two-step (`Ownable2Step`) on every contract RapidEX
  wrote, so a mistyped successor cannot take the role.
- The FeeRouter's fee is hard-capped at `MAX_FEE_BPS` (100 bps) and increases
  require a 2-day timelock, so a fee change cannot be slipped in front of an
  in-flight trade.

One sharp edge has no on-chain guard: **`factory.setOwner` is one-step**
(inherited from Uniswap V3, with only a zero-address check added). A mistyped
address there permanently forfeits the protocol fee switch. Verify it twice.

Because there is no second signer, the admin key's custody *is* the security
model. Back it up, keep it offline, and treat any suspicion of exposure as a
reason to rotate every role immediately.

---

## Deployed Contract Addresses

**[`deployments.json`](./deployments.json) is the single source of truth.** It is the
canonical manifest: every address in it was verified against on-chain runtime bytecode
and by calling a distinguishing function, and each entry records how.

No address table is kept here. A hand-maintained second copy is what produced the
mislabelled table this file used to carry, so front-ends, scripts and integrations
should read `deployments.json` directly:

```bash
npm run addresses                 # every live contract, with network header
npm run addresses -- SwapRouter   # one address, bare, for shell substitution
```

`deployments.json` also carries a **`doNotUse`** list of superseded deployments.
Several of those revert on `name()`/`symbol()` (they were built against Cancun, which
this chain does not implement). Check any address you find elsewhere against that list
before using it.

---

## Environment Setup

Addresses come from `deployments.json`, so `.env` only needs the deploy-time secrets
and knobs the Foundry scripts actually read:

```env
RPC_URL=https://mariorpc.mstblockchain.com
PRIVATE_KEY=<your_deployer_private_key>

# script/DeployRapidEX.s.sol
FEE_RECIPIENT=<address that receives RapidEXFeeRouter protocol fees>
PROTOCOL_FEE_BPS=25      # optional, defaults to the script's DEFAULT_FEE_BPS
EXPECTED_NONCE=          # optional, asserts deployer nonce so predicted addresses hold

# script/SetupPools.s.sol
POSITION_MANAGER=<NonfungiblePositionManager address from deployments.json>
V3_FACTORY=<RapiddexV3Factory address from deployments.json>
```

---

## Commands & Usage

This project uses **Foundry** for building, testing, and scripting.

### 1. Build and Compile

Compile all contracts (wrapper & core/periphery dependencies):

```bash
npm run build
# OR directly via Forge:
forge build
```

### 2. Test

```bash
forge test            # whole suite
forge test --summary  # per-suite pass/fail table
```

`test/V3Integration.t.sol` deploys the full 0.7.6 fork from artifacts and asserts the
one invariant a V3 fork can silently break: `test_poolInitCodeHashMatchesDeployedPool`
proves the hardcoded `POOL_INIT_CODE_HASH` in `PoolAddress.sol` still matches the
factory's actual pool bytecode. Any change to `foundry.toml` — optimizer runs,
`evm_version`, metadata settings — changes that bytecode, so run the suite after
touching the build config or every swap and mint will fail against a fresh deployment.

### 3. Debugging with Cast

Use Foundry's `cast` utility to query state directly from MST Mainnet:

*   **Read a pool's price/tick data:**
    ```bash
    cast call <POOL_ADDRESS> "slot0()(uint160,int24,uint16,uint16,uint16,uint8,bool)" --rpc-url https://mariorpc.mstblockchain.com
    ```
*   **Query a user's USDC.e balance** (address read from the manifest, not pasted):
    ```bash
    cast call "$(npm run --silent addresses -- 'USDC.e')" \
      "balanceOf(address)(uint256)" <USER_ADDRESS> --rpc-url https://mariorpc.mstblockchain.com
    ```

---

## Acknowledgements

Rapiddex is a fork of the **Uniswap V3 Protocol** ([Uniswap V3 Core](https://github.com/Uniswap/v3-core) & [Uniswap V3 Periphery](https://github.com/Uniswap/v3-periphery)), adapted and deployed for the MST network. We gratefully acknowledge **Uniswap Labs** (© 2021 Uniswap Labs) for their pioneering work and open-source architecture.


