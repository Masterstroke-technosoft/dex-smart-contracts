# Rapiddex Smart Contracts

Core smart contracts for Rapiddex, a Rapiddex V3-based decentralized exchange deployed on the MST Testnet. These contracts manage pool creation, swaps, liquidity positions, on-chain state storage, and wrapped native token interaction.

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

---

## Deployed Contract Addresses

Below are the deployed contract addresses on the MST Testnet (synced with the `.env` file):

| Contract | Address |
| :--- | :--- |
| **WMST** | `0xCa626248811DaD64F8284Ea63a11C2A4078795BC` |
| **tMUSD (tMUSDC)** | `0x7f64380eAb3e93ceA8aEA7D51294F83e5f067458` |
| **V3 Factory** | `0xD02BB60b01cB1DDca2Af9183499958E5494598f5` |
| **Position Descriptor** | `0xe87FAAcbF4df86B2459937c1e8C71AB4810eFA9a` |
| **Position Manager** | `0x45F540Ccd263b1511a8c3C02bcB5E64876577Ad6` |
| **Swap Router** | `0x0D24EC10272D6081E4b95e0D3F4B03ba8a43c605` |
| **Quoter V2** | `0xA570f13D675E05a2916885f7236ED88BeF151488` |
| **LP State Storage** | `0xE530b2B61C0C6243502dF49A93A0622aCDa6AFC7` |

---

## Environment Setup

Create a `.env` file in the root of this folder containing the target configuration:

```env
RPC_URL=https://testnetrpc.mstblockchain.com
WS_RPC_URL=wss://testnetrpc.mstblockchain.com
CHAIN_ID=91562037
PRIVATE_KEY=<your_deployer_private_key>

WMST_ADDRESS=0xCa626248811DaD64F8284Ea63a11C2A4078795BC
TMUSD_ADDRESS=0x7f64380eAb3e93ceA8aEA7D51294F83e5f067458
V3_FACTORY_ADDRESS=0xD02BB60b01cB1DDca2Af9183499958E5494598f5
POSITION_DESCRIPTOR_ADDRESS=0xe87FAAcbF4df86B2459937c1e8C71AB4810eFA9a
POSITION_MANAGER_ADDRESS=0x45F540Ccd263b1511a8c3C02bcB5E64876577Ad6
SWAP_ROUTER_ADDRESS=0x0D24EC10272D6081E4b95e0D3F4B03ba8a43c605
QUOTER_V2_ADDRESS=0xA570f13D675E05a2916885f7236ED88BeF151488
LP_STATE_STORAGE_ADDRESS=0xE530b2B61C0C6243502dF49A93A0622aCDa6AFC7
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

### 2. Debugging with Cast

Use Foundry's `cast` utility to query state directly from the MST Testnet:

*   **Read a pool's price/tick data:**
    ```bash
    cast call <POOL_ADDRESS> "slot0()(uint160,int24,uint16,uint16,uint16,uint8,bool)" --rpc-url https://testnetrpc.mstblockchain.com
    ```
*   **Query a user's token balance:**
    ```bash
    cast call 0x7f64380eAb3e93ceA8aEA7D51294F83e5f067458 "balanceOf(address)(uint256)" <USER_ADDRESS> --rpc-url https://testnetrpc.mstblockchain.com
    ```

---

## Acknowledgements

Rapiddex is a fork of the **Uniswap V3 Protocol** ([Uniswap V3 Core](https://github.com/Uniswap/v3-core) & [Uniswap V3 Periphery](https://github.com/Uniswap/v3-periphery)), adapted and deployed for the MST network. We gratefully acknowledge **Uniswap Labs** (© 2021 Uniswap Labs) for their pioneering work and open-source architecture.


