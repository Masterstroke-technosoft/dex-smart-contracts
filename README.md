# Rapidex Smart Contracts

Core smart contracts for Rapidex, a Uniswap V3-based decentralized exchange deployed on the MST Testnet. These contracts manage pool creation, swaps, liquidity positions, on-chain state storage, and wrapped native token interaction.

## Technical Details (MST Testnet)

- **Network Name**: MST Testnet
- **Chain ID**: `91562037`
- **RPC URL**: `https://testnetrpc.mstblockchain.com`
- **WS RPC URL**: `wss://testnetrpc.mstblockchain.com`

---

## Contract Directory Structure

All source contracts reside in the `src/` directory, while pre-flattened versions (for block explorer verification) are located in `src/flattened/`.

### Core Contracts

*   **`src/WMST.sol`** (`Wrapped MST`): Canonical wrapped native MST token, modeled on WETH9. Periphery contracts operate exclusively on ERC20 tokens, making `WMST` a requirement to interact with native MST on the platform.
*   **`src/TestToken.sol`** (`tMUSD`): A mock ERC20 stablecoin (tMUSDC) with 6 decimals, used to bootstrap liquidity pools and facilitate swap testing. Equipped with minting capabilities owned by the contract deployer.
*   **`src/MinimalPositionDescriptor.sol`**: Provides basic metadata (`tokenURI` containing the token ID) for liquidity position NFTs. A lightweight alternative to full SVG generation libraries to save gas and deployment byte size.
*   **`src/LPStateStorage.sol`**: Stores metadata, pool addresses, and LP position parameters (liquidity, token amounts) directly on-chain. Used to coordinate state tracking across indexing and backend services.

### Importer/Wrapper Contracts (Uniswap V3 Core & Periphery)

The project leverages Uniswap V3 core and periphery implementations via library wrappers to preserve the audited codebases while targeting compatibility with Solidity `0.7.6`:

*   **`src/RapidexV3FactoryImporter.sol`**: Extends `UniswapV3Factory` (core pool registry).
*   **`src/NonfungiblePositionManagerImporter.sol`**: Extends `NonfungiblePositionManager` (liquidity management and ERC721 positions).
*   **`src/SwapRouterImporter.sol`**: Extends `SwapRouter` (exact input/output routing).
*   **`src/QuoterV2Importer.sol`**: Extends `QuoterV2` (on-chain price quotes).

---

## Deployed Contract Addresses

Below are the deployed contract addresses on the MST Testnet (synced with the `.env` file):

| Contract | Address |
| :--- | :--- |
| **WMST** | `0x9DDd1F5Ac413aBb02d642471fb0D415A75fa17Be` |
| **USDC (tMUSDC)** | `0x51c85e958A4F0A291891B0567A0E2533032c6D70` |
| **V3 Factory** | `0xacC93a1d4fB8a9953f2BEC2c8f1d75027c6289F3` |
| **Position Manager** | `0x73E156fd96ACF6497d9f986e665Fa48F45f942F0` |
| **Swap Router** | `0x26E11805440137E25399FC2a47CBDC8dF1e24B30` |
| **Quoter V2** | `0x21E72a835204ec0c5a9ec9F02540D4398d6963a6` |
| **LP State Storage** | `0xA4B4766f5A58331b54Fd3351D67891B123857857` |

---

## Environment Setup

Create a `.env` file in the root of this folder containing the target configuration:

```env
RPC_URL=https://testnetrpc.mstblockchain.com
WS_RPC_URL=wss://testnetrpc.mstblockchain.com
CHAIN_ID=91562037
PRIVATE_KEY=<your_deployer_private_key>

WMST_ADDRESS=0x9DDd1F5Ac413aBb02d642471fb0D415A75fa17Be
USDC_ADDRESS=0x51c85e958A4F0A291891B0567A0E2533032c6D70
V3_FACTORY_ADDRESS=0xacC93a1d4fB8a9953f2BEC2c8f1d75027c6289F3
POSITION_MANAGER_ADDRESS=0x73E156fd96ACF6497d9f986e665Fa48F45f942F0
SWAP_ROUTER_ADDRESS=0x26E11805440137E25399FC2a47CBDC8dF1e24B30
QUOTER_V2_ADDRESS=0x21E72a835204ec0c5a9ec9F02540D4398d6963a6
LP_STATE_STORAGE_ADDRESS=0xA4B4766f5A58331b54Fd3351D67891B123857857
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

### 2. Running Maintenance Scripts

The scripts in `script/` are used to interact with live contracts on MST Testnet.

#### Set Pool Protocol Fees
Sets the protocol fee split for a pool. (Only the `RapidexV3Factory` owner can invoke this).

```bash
# Set parameters in your command environment:
export POOL_ADDRESS=0x...
export FEE_PROTOCOL_0=4
export FEE_PROTOCOL_1=4
export FACTORY_OWNER_PRIVATE_KEY=0x...

# Execute the script:
forge script script/SetPoolProtocolFee.s.sol:SetPoolProtocolFee \
  --rpc-url https://testnetrpc.mstblockchain.com \
  --broadcast
```

#### Collect Protocol Fees
Collects accrued protocol fees from a specific pool and routes them to a recipient address.

```bash
# Set parameters in your command environment:
export POOL_ADDRESS=0x...
export FEE_RECIPIENT=0x...
export AMOUNT_0_REQUESTED=1000000000000000000
export AMOUNT_1_REQUESTED=1000000000000000000
export FACTORY_OWNER_PRIVATE_KEY=0x...

# Execute the script:
forge script script/CollectPoolProtocolFees.s.sol:CollectPoolProtocolFees \
  --rpc-url https://testnetrpc.mstblockchain.com \
  --broadcast
```

### 3. Debugging with Cast

Use Foundry's `cast` utility to query state directly from the MST Testnet:

*   **Read a pool's price/tick data:**
    ```bash
    cast call <POOL_ADDRESS> "slot0()(uint160,int24,uint16,uint16,uint16,uint8,bool)" --rpc-url https://testnetrpc.mstblockchain.com
    ```
*   **Query a user's token balance:**
    ```bash
    cast call 0x51c85e958A4F0A291891B0567A0E2533032c6D70 "balanceOf(address)(uint256)" <USER_ADDRESS> --rpc-url https://testnetrpc.mstblockchain.com
    ```
