'use client';

/**
 * Providers — wagmi + RainbowKit configuration
 *
 * Wallet connection strategy:
 *  - Local (Anvil/hardhat):  injectedWallet only (MetaMask browser extension)
 *  - Testnet/Mainnet:        injectedWallet + WalletConnect (requires valid projectId)
 *
 * Using injectedWallet for local dev avoids the WalletConnect relay entirely,
 * which means no project ID is needed and the modal opens instantly.
 */

import {
  RainbowKitProvider,
  connectorsForWallets,
  darkTheme,
} from '@rainbow-me/rainbowkit';
import {
  injectedWallet,
  metaMaskWallet,
  rabbyWallet,
  braveWallet,
} from '@rainbow-me/rainbowkit/wallets';
import '@rainbow-me/rainbowkit/styles.css';
import { createConfig, WagmiProvider, http } from 'wagmi';
import { hardhat, sepolia } from 'wagmi/chains';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

// ─── Wallet connectors ────────────────────────────────────────────────────────
// No WalletConnect projectId needed for local dev — injected wallets only.
const connectors = connectorsForWallets(
  [
    {
      groupName: 'Recommended',
      wallets: [
        injectedWallet,   // any injected wallet (MetaMask, Rabby, etc.)
        metaMaskWallet,   // MetaMask explicit
        braveWallet,      // Brave built-in wallet
        rabbyWallet,      // Rabby
      ],
    },
  ],
  {
    appName: 'OMNITRIX Protocol',
    // Use a real WalletConnect project ID for production.
    // For local Anvil dev, injected wallets work without it.
    projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? 'defi_local_dev',
  }
);

// ─── wagmi config ─────────────────────────────────────────────────────────────
const config = createConfig({
  connectors,
  chains: [hardhat, sepolia],
  transports: {
    [hardhat.id]: http('http://127.0.0.1:8545'),  // Anvil local
    [sepolia.id]: http(),                           // default public RPC
  },
  ssr: true,
});

const queryClient = new QueryClient();

// ─── Provider tree ────────────────────────────────────────────────────────────
export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider
          theme={darkTheme({
            accentColor: '#6366f1',
            accentColorForeground: 'white',
            borderRadius: 'medium',
            fontStack: 'system',
          })}
          modalSize="compact"
        >
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
