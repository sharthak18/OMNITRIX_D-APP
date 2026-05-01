# OMNITRIX Protocol

**OMNITRIX** is a fully on-chain, decentralized finance (DeFi) protocol built on Ethereum. It provides a comprehensive, vertically integrated ecosystem featuring an Automated Market Maker (AMM), an over-collateralized Lending & Borrowing market, and a Yield Farming staking platform.

![OMNITRIX Protocol](https://img.shields.io/badge/Status-Live%20on%20Sepolia-success)
![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue)
![Framework](https://img.shields.io/badge/Next.js-16%20App%20Router-black)

---

> [!IMPORTANT]
> 📖 **Want to know exactly how everything works?**  
> Check out the [**Comprehensive Project Walkthrough**](./PROJECT_WALKTHROUGH.md) for an exhaustive explanation of the architecture, what every smart contract does, why they exist, and how the Next.js frontend connects to the blockchain.

---

## ⚡ Core Features

1. **Decentralized Exchange (AMM)**
   - Permissionless token swapping using a constant-product formula ($x \times y = k$).
   - Custom `DefiFactory`, `DefiRouter`, and `DefiPair` contracts optimized for gas efficiency.
   - Built-in Time-Weighted Average Price (TWAP) accumulators to resist short-term price manipulation.

2. **Lending & Borrowing Market**
   - Over-collateralized lending pool supporting WETH, USDC, and OMNI.
   - Health Factor system preventing systemic insolvency.
   - Flash Loan capabilities (`flashLoan`) for arbitrage and liquidations.
   - **Chainlink Oracle Integration:** Utilizes industry-standard off-chain price feeds to eliminate flash-loan spot price manipulation vulnerabilities.

3. **Yield Farming & Staking**
   - Synthetix-style reward distribution system.
   - Users can provide liquidity to the AMM and stake their LP tokens to earn continuous `OMNI` emissions per second.
   - Reward rates adjust dynamically based on total value locked (TVL).

## 🏗 Architecture & Codebase

The protocol is explicitly separated into two main directories:

### 1. The Smart Contracts (`/contracts`)
Developed and tested using **Foundry**. This is the backend logic that lives on Ethereum.
- **Tokens**: `DefiToken.sol` manages the OMNI token supply and minting rights.
- **AMM**: `DefiFactory.sol`, `DefiPair.sol`, and `DefiRouter.sol` handle the constant-product liquidity pools and secure token swaps.
- **Lending**: `LendingPool.sol` manages the overcollateralized borrowing logic, backed by Chainlink's `PriceOracle.sol` to prevent flash loan attacks.
- **Staking**: `StakingRewards.sol` handles the Synthetix-style reward dripping to LP providers.

### 2. The Frontend (`/frontend`)
The user interface, built with **Next.js 16 (App Router)** and **React**.
- **Web3 Engine**: Uses **Wagmi v3**, **Viem v2**, and **RainbowKit** to interact with MetaMask and sign transactions.
- **State Sync**: Uses **TanStack Query** for aggressive real-time blockchain state synchronization. If a block is mined, the UI updates instantly.
- **Design**: Fully custom vanilla CSS featuring glassmorphism, responsive mobile layouts, and joyful CSS keyframe animations (like the floating crypto background).

## 🚀 Getting Started

### Prerequisites
- [Foundry](https://getfoundry.sh/) (Forge, Anvil, Cast)
- [Node.js](https://nodejs.org/) (v18+)
- [MetaMask](https://metamask.io/) or equivalent injected wallet.

### 1. Smart Contracts
```bash
cd contracts
forge install
forge test
```
To deploy to a live testnet (e.g., Sepolia):
```bash
# Add your SEPOLIA_RPC_URL and ETHERSCAN_API_KEY to contracts/.env
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --account yourKeystore --broadcast --verify
```

### 2. Frontend App
```bash
cd frontend
npm install
npm run dev
```
Navigate to `http://localhost:3000` to interact with the protocol.

## 🔒 Security
- All external calls follow the Checks-Effects-Interactions pattern.
- Critical state-mutating functions are protected by `ReentrancyGuard`.
- The lending pool oracle leverages Chainlink to prevent AMM-based flash loan attacks.
- Solmate and OpenZeppelin libraries are used for standard ERC20 and math operations.

## 📄 License
This project is licensed under the MIT License.
