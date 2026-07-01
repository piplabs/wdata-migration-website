"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";

import { Logo } from "@/components/Logo";

export function Header() {
  return (
    <header className="w-full border-b border-[color:var(--color-border)]">
      <div className="mx-auto flex h-16 max-w-5xl items-center justify-between px-4 sm:px-6">
        <Logo />
        <ConnectButton
          accountStatus="address"
          chainStatus="icon"
          showBalance={false}
        />
      </div>
    </header>
  );
}
