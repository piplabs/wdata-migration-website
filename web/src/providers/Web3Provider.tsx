"use client";

import "@rainbow-me/rainbowkit/styles.css";

import {
  RainbowKitProvider,
  connectorsForWallets,
  darkTheme,
} from "@rainbow-me/rainbowkit";
import {
  injectedWallet,
  metaMaskWallet,
  okxWallet,
  phantomWallet,
  rainbowWallet,
  walletConnectWallet,
} from "@rainbow-me/rainbowkit/wallets";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { type ReactNode, useState } from "react";
import { http } from "viem";
import { WagmiProvider, createConfig } from "wagmi";

import { ALL_CHAINS, WALLET_CONNECT_PROJECT_ID } from "@/config/networks";

const connectors = connectorsForWallets(
  [
    {
      groupName: "Recommended",
      wallets: [
        metaMaskWallet,
        okxWallet,
        phantomWallet,
        rainbowWallet,
        injectedWallet,
        walletConnectWallet,
      ],
    },
  ],
  {
    appName: "DATA Migration",
    projectId: WALLET_CONNECT_PROJECT_ID || "MISSING_WALLET_CONNECT_PROJECT_ID",
  },
);

const transports = Object.fromEntries(
  ALL_CHAINS.map((chain) => [
    chain.id,
    http(chain.rpcUrls.default.http[0]),
  ]),
);

const wagmiConfig = createConfig({
  chains: ALL_CHAINS,
  connectors,
  transports,
  ssr: true,
});

const rainbowTheme = darkTheme({
  accentColor: "#F8F8F6",
  accentColorForeground: "#101112",
  borderRadius: "medium",
  overlayBlur: "small",
});

export function Web3Provider({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={rainbowTheme} modalSize="compact">
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
