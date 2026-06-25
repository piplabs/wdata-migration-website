"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";

import { Logo } from "@/components/Logo";
import { LEARN_MORE_URL } from "@/config/networks";

export function Header() {
  return (
    <header className="w-full border-b border-[color:var(--color-border)]">
      <div className="mx-auto flex h-16 max-w-5xl items-center justify-between px-4 sm:px-6">
        <Logo />
        <div className="flex items-center gap-3 sm:gap-5">
          <a
            href={LEARN_MORE_URL}
            target="_blank"
            rel="noreferrer"
            className="hidden text-sm text-[color:var(--color-muted)] transition-colors hover:text-[color:var(--color-fg)] sm:inline"
          >
            Learn More about DATA
          </a>
          <ConnectButton
            accountStatus="address"
            chainStatus="icon"
            showBalance={false}
          />
        </div>
      </div>
    </header>
  );
}
