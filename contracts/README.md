# OMNITRIX Protocol - Smart Contracts

This directory contains the core Solidity smart contracts powering the OMNITRIX DeFi Protocol, developed and tested using [Foundry](https://getfoundry.sh/).

## Architecture

The protocol consists of four primary modules:

1. **Tokens (`src/tokens/`)**
   - `DefiToken.sol`: The native governance and reward token (`OMNI`). Includes minting capabilities restricted to the protocol owner (or staking contracts) for reward distribution.
2. **AMM & Swaps (`src/swap/`)**
   - `DefiFactory.sol`: Deploys new `DefiPair` contracts and tracks all liquidity pools.
   - `DefiPair.sol`: The core AMM pool implementation (Constant Product), handling LP token minting/burning, swaps, and TWAP price accumulators.
   - `DefiRouter.sol`: The periphery contract that safely routes user interactions (adding/removing liquidity, swapping exact amounts) with deadline and slippage checks.
3. **Lending (`src/lending/`)**
   - `LendingPool.sol`: Core lending market. Users supply collateral and borrow against it. Implements a Taylor-series approximation for per-second interest compounding.
   - `PriceOracle.sol`: Chainlink-compatible oracle registry preventing flash loan manipulation.
4. **Staking (`src/staking/`)**
   - `StakingRewards.sol`: Distributes `OMNI` rewards continuously to LP token stakers.

## Development & Testing

```bash
# Compile contracts
forge build

# Run unit and fuzz tests
forge test -vvv

# Check gas snapshots
forge snapshot
```

## Deployment

Deployments are handled by `script/Deploy.s.sol`. It intelligently detects the target chain:
- **Local (Chain ID 31337):** Deploys mock tokens (WETH/USDC) and mock Chainlink aggregators.
- **Testnet (Chain ID 11155111):** Integrates with live Sepolia Chainlink price feeds.

```bash
# Securely deploy to Sepolia using an encrypted keystore
source .env
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --account defaultkey --broadcast --verify
```
