# MSTSwap V3 Integration Guide

> Replace all placeholder values with your own deployed contract addresses and wallet values before running commands.

---

# Loading Environment Variables

## Git Bash / MINGW64

```bash
set -a
source .env
set +a
```

## Windows PowerShell

```powershell
Get-Content .env | ForEach-Object {
    if ($_ -match "^\s*([^#=\s]+)\s*=\s*(.*)$") {
        [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2].Trim("'").Trim('"'), "Process")
    }
}
```

---

# Example `.env`

```env
RPC_URL=https://your-rpc-url.example

PRIVATE_KEY=your_private_key

TOKEN0_ADDRESS=0xToken0Address
TOKEN1_ADDRESS=0xToken1Address

POOL_ADDRESS=0xPoolAddress
FACTORY_ADDRESS=0xFactoryAddress

POSITION_MANAGER_ADDRESS=0xPositionManagerAddress
SWAP_ROUTER_ADDRESS=0xSwapRouterAddress
QUOTER_V2_ADDRESS=0xQuoterV2Address

DEPLOYER=0xYourWalletAddress

STORAGE_ADDRESS=0xStorageAddress
EXECUTOR_ADDRESS=0xExecutorAddress
```

---

# Uniswap V3 Lifecycle Commands

---

## 1. Verify Pool Creation

```bash
cast call "$FACTORY_ADDRESS" \
  "getPool(address,address,uint24)(address)" \
  "$TOKEN0_ADDRESS" "$TOKEN1_ADDRESS" 3000 \
  --rpc-url "$RPC_URL"
```

Expected Output:

```text
0xPoolAddress
```

---

## 2. Verify LP Position NFT

### Check NFT Owner

```bash
cast call "$POSITION_MANAGER_ADDRESS" \
  "ownerOf(uint256)(address)" 1 \
  --rpc-url "$RPC_URL"
```

### Check Metadata URI

```bash
cast call "$POSITION_MANAGER_ADDRESS" \
  "tokenURI(uint256)(string)" 1 \
  --rpc-url "$RPC_URL"
```

---

## 3. Read Pool Slot0 State

```bash
cast call "$POOL_ADDRESS" \
  "slot0()(uint160,int24,uint16,uint16,uint16,uint8,bool)" \
  --rpc-url "$RPC_URL"
```

---

## 4. Verify Tick Spacing

```bash
cast call "$FACTORY_ADDRESS" \
  "feeAmountTickSpacing(uint24)(int24)" \
  3000 \
  --rpc-url "$RPC_URL"
```

---

## 5. Read Pool Liquidity

```bash
cast call "$POOL_ADDRESS" \
  "liquidity()(uint128)" \
  --rpc-url "$RPC_URL"
```

---

## 6. Check Token Balances

### Token0 Balance

```bash
cast call "$TOKEN0_ADDRESS" \
  "balanceOf(address)(uint256)" \
  "$DEPLOYER" \
  --rpc-url "$RPC_URL"
```

### Token1 Balance

```bash
cast call "$TOKEN1_ADDRESS" \
  "balanceOf(address)(uint256)" \
  "$DEPLOYER" \
  --rpc-url "$RPC_URL"
```

---

## 7. Get Swap Quote

```bash
cast call "$QUOTER_V2_ADDRESS" \
  "quoteExactInputSingle((address,address,uint256,uint24,uint160))(uint256,uint160,uint32,uint256)" \
  "($TOKEN0_ADDRESS,$TOKEN1_ADDRESS,1000000000000000,3000,0)" \
  --rpc-url "$RPC_URL"
```

---

## 8. Wrap & Approve Tokens

### Wrap Native Token

```bash
cast send "$TOKEN0_ADDRESS" \
  "deposit()" \
  --value 0.01ether \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC_URL"
```

### Approve Router

```bash
cast send "$TOKEN0_ADDRESS" \
  "approve(address,uint256)" \
  "$SWAP_ROUTER_ADDRESS" \
  10000000000000000 \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC_URL"
```

---

## 9. Execute Single Swap

```bash
cast send "$SWAP_ROUTER_ADDRESS" \
  "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))" \
  "($TOKEN0_ADDRESS,$TOKEN1_ADDRESS,3000,$DEPLOYER,$(($(date +%s)+1200)),10000000000000000,0,0)" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY"
```

---

## 10. Execute Multi-Hop Swap

```bash
cast send "$SWAP_ROUTER_ADDRESS" \
  "exactInput((bytes,address,uint256,uint256,uint256))" \
  "(0xYourEncodedPath,$DEPLOYER,$(($(date +%s)+1200)),1000000000000000,0)" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY"
```

---

## 11. Add Liquidity

```bash
cast send "$POSITION_MANAGER_ADDRESS" \
  "increaseLiquidity((uint256,uint256,uint256,uint256,uint256,uint256))" \
  "(1,10000000,1000000000000000,0,0,$(($(date +%s)+1200)))" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY"
```

---

## 12. Remove Liquidity

```bash
cast send "$POSITION_MANAGER_ADDRESS" \
  "decreaseLiquidity((uint256,uint128,uint256,uint256,uint256))" \
  "(1,1000000,0,0,$(($(date +%s)+1200)))" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY"
```

---

## 13. Collect Fees

```bash
cast send "$POSITION_MANAGER_ADDRESS" \
  "collect((uint256,address,uint128,uint128))" \
  "(1,$DEPLOYER,340282366920938463463374607431768211455,340282366920938463463374607431768211455)" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY"
```

---

# Automated Testing Executor

Instead of manually running every lifecycle step, an executor contract can automate pool creation, liquidity provisioning, and storage updates.

---

## Transfer Storage Ownership

```bash
cast send "$STORAGE_ADDRESS" \
  "transferOwnership(address)" \
  "$EXECUTOR_ADDRESS" \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC_URL"
```

---

## Execute Full Pool + Liquidity Flow

```bash
cast send "$EXECUTOR_ADDRESS" \
  "initiatePoolAndLiquidity((uint24,uint160,uint256,uint256,int24,int24))" \
  "3000" \
  "79228162514264337593543950336" \
  "10000000000000000" \
  "100000000" \
  "-887220" \
  "887220" \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC_URL" \
  --value 0.01ether
```

---

# Run Integration Tests

```bash
cd contracts

forge test -vvv
```

---

# Example Successful Output

```text
Compiler run successful!

[PASS] testSwapFlow()
[PASS] testFullMintFlowOnFork()
[PASS] testDeploymentAddressesConnected()
[PASS] testFullFlow()
[PASS] testFullOrchestratorFlow()

Suite result: ok. All tests passed.
```

---
