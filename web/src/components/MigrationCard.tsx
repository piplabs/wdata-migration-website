"use client";

import { useConnectModal } from "@rainbow-me/rainbowkit";
import { useEffect, useMemo, useState } from "react";
import { parseUnits } from "viem";
import { useAccount, useReadContract } from "wagmi";

import { MigrationDialog } from "@/components/MigrationDialog";
import { UpdateRpcButton } from "@/components/UpdateRpcButton";
import { Button } from "@/components/ui/Button";
import { BRAND } from "@/config/brand";
import { erc20Abi, migrationAbi } from "@/config/abis";
import { type NetworkConfig, NETWORKS, dataNetwork, getNetwork } from "@/config/networks";
import { formatAmount } from "@/lib/format";

type Ecosystem = "data" | "bsc";

const WDATAIP_INFO =
  "WDATAIP is the wrapped token's name on BNB Chain. It's fully 1:1 with WDATA and WIP.";

function NetworkIndicator({
  ecosystem,
  isTestnet,
}: {
  ecosystem: Ecosystem;
  isTestnet: boolean;
}) {
  const chainName = ecosystem === "bsc" ? "BNB Chain" : "Data Network";
  return (
    <div className="flex items-center justify-between rounded-xl border border-[color:var(--color-border)] bg-[color:var(--color-bg)] p-4">
      <span className="text-xs uppercase tracking-wide text-[color:var(--color-muted)]">
        Network
      </span>
      <div className="flex items-center gap-2">
        <span
          className="h-2 w-2 rounded-full"
          style={{ backgroundColor: isTestnet ? "#fbbf24" : "var(--color-success)" }}
        />
        <span className="text-sm font-medium text-[color:var(--color-fg)]">
          {chainName}
        </span>
        <span className="rounded-md bg-[color:var(--color-surface-2)] px-1.5 py-0.5 text-xs font-medium text-[color:var(--color-muted)]">
          {isTestnet ? "Testnet" : "Mainnet"}
        </span>
      </div>
    </div>
  );
}

function InfoTooltip({ text }: { text: string }) {
  return (
    <span className="group relative inline-flex">
      <button
        type="button"
        aria-label={text}
        className="inline-flex h-4 w-4 cursor-default items-center justify-center rounded-full border border-[color:var(--color-border-strong)] text-[10px] font-medium leading-none text-[color:var(--color-muted)] transition-colors hover:border-[color:var(--color-fg)]/40 hover:text-[color:var(--color-fg)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[color:var(--color-fg)]/40"
      >
        i
      </button>
      <span
        role="tooltip"
        className="pointer-events-none absolute bottom-full left-0 z-10 mb-2 w-56 rounded-lg border border-[color:var(--color-border)] bg-[color:var(--color-surface-2)] px-3 py-2 text-xs font-normal leading-relaxed text-[color:var(--color-fg)] opacity-0 shadow-xl transition-opacity duration-150 group-hover:opacity-100 group-focus-within:opacity-100"
      >
        {text}
        <span className="absolute left-1.5 top-full h-2 w-2 -translate-y-1/2 rotate-45 border-b border-r border-[color:var(--color-border)] bg-[color:var(--color-surface-2)]" />
      </span>
    </span>
  );
}

function TokenPanel({
  label,
  symbol,
  name,
  iconUrl,
  info,
  children,
}: {
  label: string;
  symbol: string;
  name: string;
  iconUrl: string;
  /** Optional explainer shown as a tooltip on an info icon next to the symbol. */
  info?: string;
  children?: React.ReactNode;
}) {
  return (
    <div className="rounded-xl border border-[color:var(--color-border)] bg-[color:var(--color-bg)] p-4">
      <div className="flex items-center justify-between">
        <span className="text-xs uppercase tracking-wide text-[color:var(--color-muted)]">
          {label}
        </span>
        {children}
      </div>
      <div className="mt-2 flex items-center gap-2">
        {/* eslint-disable-next-line @next/next/no-img-element -- remote brand asset */}
        <img
          src={iconUrl}
          alt={symbol}
          className="h-8 w-8 rounded-full bg-[color:var(--color-surface-2)]"
        />
        <div>
          <p className="flex items-center gap-1.5 text-sm font-semibold">
            {symbol}
            {info ? <InfoTooltip text={info} /> : null}
          </p>
          <p className="text-xs text-[color:var(--color-muted)]">{name}</p>
        </div>
      </div>
    </div>
  );
}

export function MigrationCard() {
  const { address, chainId, isConnected } = useAccount();
  const { openConnectModal } = useConnectModal();
  const [amountInput, setAmountInput] = useState("");
  const [dialogOpen, setDialogOpen] = useState(false);
  const [pendingSwap, setPendingSwap] = useState(false);

  // The active network follows the connected wallet's chain; 
  // the indicator can never drift out of sync with the network the
  // user selected in the top-right wallet button. 
  const network = (getNetwork(chainId) ?? NETWORKS[dataNetwork.id]) as NetworkConfig;
  const { ecosystem, isTestnet } = network;
  const isZeroAddress = /^0x0{40}$/.test(network.from.address);
  const configured =
    !isZeroAddress && /^0x[0-9a-fA-F]{40}$/.test(network.from.address);
  const migrationReady =
    configured && (network.flow === "wrapper" || Boolean(network.migration));

  const balance = useReadContract({
    abi: erc20Abi,
    address: network.from.address,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    chainId: network.chain.id,
    query: { enabled: Boolean(address) && configured },
  });

  // lockMint dispenses from a pre-funded reserve; read it so we can block an
  // over-reserve amount up front instead of letting migrate() revert (which some
  // RPCs surface as an opaque "gas limit too high" instead of insufficient reserve).
  const hasReserveGate = network.flow === "lockMint" && Boolean(network.migration);
  const reserve = useReadContract({
    abi: migrationAbi,
    address: network.migration,
    functionName: "availableWdataip",
    chainId: network.chain.id,
    query: { enabled: hasReserveGate },
  });

  const amountWei = useMemo(() => {
    if (!amountInput) return 0n;
    try {
      return parseUnits(amountInput, network.from.decimals);
    } catch {
      return 0n;
    }
  }, [amountInput, network.from.decimals]);

  const balanceValue = balance.data ?? 0n;
  const reserveValue = reserve.data ?? 0n;
  const onWrongChain = isConnected && chainId !== network.chain.id;
  // Gate both on isSuccess so a not-yet-loaded / failed read is not misread as
  // "0" (which would falsely block a valid swap and, right after connect, defeat
  // connect-then-swap by leaving canSwap false while the balance is still loading).
  const exceedsBalance = balance.isSuccess && amountWei > balanceValue;
  const exceedsReserve = hasReserveGate && reserve.isSuccess && amountWei > reserveValue;
  const canSwap =
    isConnected &&
    !onWrongChain &&
    migrationReady &&
    amountWei > 0n &&
    !exceedsBalance &&
    !exceedsReserve;

  const swapLabel = (() => {
    if (!migrationReady) return "Migration unavailable";
    if (amountWei === 0n) return "Enter an amount";
    if (exceedsBalance) return "Insufficient balance";
    if (exceedsReserve) return "Insufficient reserve";
    return isConnected ? "Migrate" : "Connect Wallet & Migrate";
  })();

  // The Swap button connects the wallet first when disconnected, then proceeds
  // to the migration once a connection lands (issue #1015: no silent no-op).
  useEffect(() => {
    if (pendingSwap && isConnected) {
      setPendingSwap(false);
      if (canSwap) setDialogOpen(true);
    }
  }, [pendingSwap, isConnected, canSwap]);

  const onPrimaryAction = () => {
    if (!isConnected) {
      setPendingSwap(true);
      openConnectModal?.();
      return;
    }
    setDialogOpen(true);
  };

  const setPercent = (pct: bigint) => {
    setAmountInput(
      formatAmount((balanceValue * pct) / 100n, network.from.decimals, 18),
    );
  };

  return (
    <div className="w-full max-w-md rounded-[var(--radius-card)] border border-[color:var(--color-border)] bg-[color:var(--color-surface)] p-6 shadow-2xl">
      <h1 className="font-[family-name:var(--font-display)] text-xl font-semibold">
        Migrate to WDATA
      </h1>
      <p className="mt-1 text-sm text-[color:var(--color-muted)]">
        Swap your wrapped IP for wrapped DATA 1:1.
      </p>

      <div className="mt-5">
        <NetworkIndicator ecosystem={ecosystem} isTestnet={isTestnet} />
      </div>

      <div className="mt-4 space-y-2">
        <TokenPanel
          label="From"
          symbol={network.from.symbol}
          name={network.from.name}
          iconUrl={BRAND.token.WIP.png}
        >
          <span className="text-xs text-[color:var(--color-muted)]">
            Balance: {formatAmount(balanceValue, network.from.decimals)}
          </span>
        </TokenPanel>

        <div className="relative rounded-xl border border-[color:var(--color-border)] bg-[color:var(--color-bg)] p-4">
          <div className="flex items-center justify-between">
            <input
              inputMode="decimal"
              placeholder="0.0"
              value={amountInput}
              onChange={(event) => {
                const next = event.target.value;
                if (next === "" || /^\d*\.?\d*$/.test(next)) setAmountInput(next);
              }}
              className="w-full bg-transparent text-2xl font-semibold outline-none placeholder:text-[color:var(--color-muted)]"
            />
            <div className="flex shrink-0 gap-1">
              {([25n, 50n, 100n] as const).map((pct) => (
                <button
                  key={String(pct)}
                  onClick={() => setPercent(pct)}
                  disabled={balanceValue === 0n}
                  className="rounded-lg border border-[color:var(--color-border-strong)] px-2 py-1 text-xs font-medium text-[color:var(--color-muted)] transition-colors hover:text-[color:var(--color-fg)] disabled:opacity-40"
                >
                  {pct === 100n ? "MAX" : `${pct}%`}
                </button>
              ))}
            </div>
          </div>
        </div>

        <div className="flex justify-center">
          <span className="flex h-8 w-8 items-center justify-center rounded-full border border-[color:var(--color-border)] bg-[color:var(--color-surface)] text-sm text-[color:var(--color-muted)]">
            ↓
          </span>
        </div>

        <TokenPanel
          label="To"
          symbol={network.to.symbol}
          name={network.to.name}
          iconUrl={BRAND.token.WDATA.svg}
          {...(network.to.symbol === "WDATAIP" ? { info: WDATAIP_INFO } : {})}
        />
      </div>

      <div className="mt-6">
        {onWrongChain ? (
          <UpdateRpcButton network={network} />
        ) : (
          <Button
            className="w-full"
            disabled={!migrationReady || amountWei === 0n || (isConnected && !canSwap)}
            onClick={onPrimaryAction}
          >
            {swapLabel}
          </Button>
        )}
      </div>

      {!migrationReady ? (
        <p className="mt-3 text-center text-xs text-[color:var(--color-muted)]">
          The migration contract for {network.chain.name} is not configured yet.
        </p>
      ) : exceedsReserve ? (
        <p className="mt-3 text-center text-xs text-[color:var(--color-danger)]">
          Only {formatAmount(reserveValue, network.to.decimals)} {network.to.symbol}{" "}
          left in the reserve right now.
        </p>
      ) : null}

      {dialogOpen ? (
        <MigrationDialog
          network={network}
          amount={amountWei}
          account={address}
          onClose={() => setDialogOpen(false)}
          onComplete={() => balance.refetch()}
        />
      ) : null}
    </div>
  );
}
