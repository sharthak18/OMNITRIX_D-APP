# OMNITRIX Protocol - Frontend Application

The official user interface for the OMNITRIX DeFi Protocol, built for maximum performance, responsiveness, and real-time blockchain synchronization.

## Tech Stack

- **Framework:** Next.js 16 (App Router)
- **Styling:** Vanilla CSS (Modular & performant)
- **Web3 Integration:** Wagmi v3, Viem v2, RainbowKit v2
- **State Management:** TanStack Query v5

## Features

- **Live Dashboard:** Real-time metrics including TVL, APY, and interactive token price charts.
- **Automated Market Maker:** Seamlessly swap ERC-20 tokens with built-in slippage protection and dynamic quote routing.
- **Over-collateralized Lending:** Supply collateral to earn yield, or borrow assets dynamically monitored by health factors.
- **Yield Farming:** Stake LP tokens to earn `OMNI` rewards emitted block-by-block.
- **Optimistic UI:** Aggressive query invalidation ensures that the UI updates the exact millisecond a blockchain transaction confirms.

## Local Development

```bash
# Install dependencies
npm install

# Start the development server
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) to view the application.

## Configuration

The frontend dynamically loads deployed contract addresses from `lib/contracts.ts`, which acts as the source of truth for both local Anvil environments and public testnets (Sepolia).

When switching networks in MetaMask, RainbowKit and Wagmi will automatically detect the active chain and route contract calls to the correct addresses.
