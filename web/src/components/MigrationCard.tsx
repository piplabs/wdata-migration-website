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
import { type NetworkConfig, NETWORKS, chainIdFor } from "@/config/networks";
import { formatAmount } from "@/lib/format";

type Ecosystem = "data" | "bsc";

function SegmentedControl<T extends string>({
  options,
  value,
  onChange,
}: {
  options: { value: T; label: string }[];
  value: T;
  onChange: (value: T) => void;
}) {
  return (
    <div className="flex rounded-xl border border-[color:var(--color-border)] bg-[color:var(--color-bg)] p-1">
      {options.map((option) => (
        <button
          key={option.value}
          onClick={() => onChange(option.value)}
          className={`flex-1 rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
            value === option.value
              ? "bg-[color:var(--color-surface-2)] text-[color:var(--color-fg)]"
              : "text-[color:var(--color-muted)] hover:text-[color:var(--color-fg)]"
          }`}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

function TokenPanel({
  label,
  symbol,
  name,
  iconUrl,
  children,
}: {
  label: string;
  symbol: string;
  name: string;
  iconUrl: string;
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
          <p className="text-sm font-semibold">{symbol}</p>
          <p className="text-xs text-[color:var(--color-muted)]">{name}</p>
        </div>
      </div>
    </div>
  );
}

export function MigrationCard() {
  const { address, chainId, isConnected } = useAccount();
  const { openConnectModal } = useConnectModal();
  const [ecosystem, setEcosystem] = useState<Ecosystem>("data");
  const [isTestnet, setIsTestnet] = useState(false);
  const [amountInput, setAmountInput] = useState("");
  const [dialogOpen, setDialogOpen] = useState(false);
  const [pendingSwap, setPendingSwap] = useState(false);

  const targetChainId = chainIdFor(ecosystem, isTestnet);
  const network = NETWORKS[targetChainId] as NetworkConfig;
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
    return `Swap to ${network.to.symbol}`;
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

  return (
    <div className="w-full max-w-md rounded-[var(--radius-card)] border border-[color:var(--color-border)] bg-[color:var(--color-surface)] p-6 shadow-2xl">
      <h1 className="font-[family-name:var(--font-display)] text-xl font-semibold">
        Migrate to WDATA
      </h1>
      <p className="mt-1 text-sm text-[color:var(--color-muted)]">
        Swap your wrapped IP for wrapped DATA 1:1.
      </p>

      <div className="mt-5 grid grid-cols-2 gap-3">
        <SegmentedControl<Ecosystem>
          options={[
            { value: "data", label: "Data Network" },
            { value: "bsc", label: "BNB Chain" },
          ]}
          value={ecosystem}
          onChange={setEcosystem}
        />
        <SegmentedControl
          options={[
            { value: "main", label: "Mainnet" },
            { value: "test", label: "Testnet" },
          ]}
          value={isTestnet ? "test" : "main"}
          onChange={(value) => setIsTestnet(value === "test")}
        />
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
            <button
              onClick={() =>
                setAmountInput(formatAmount(balanceValue, network.from.decimals, 18))
              }
              disabled={balanceValue === 0n}
              className="rounded-lg border border-[color:var(--color-border-strong)] px-2.5 py-1 text-xs font-medium text-[color:var(--color-muted)] transition-colors hover:text-[color:var(--color-fg)] disabled:opacity-40"
            >
              MAX
            </button>
          </div>
        </div>

        <TokenPanel
          label="To"
          symbol={network.to.symbol}
          name={network.to.name}
          iconUrl={BRAND.token.WDATA.svg}
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
