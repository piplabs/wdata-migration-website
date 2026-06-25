"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useMemo, useState } from "react";
import { parseUnits } from "viem";
import { useAccount, useReadContract } from "wagmi";

import { MigrationDialog } from "@/components/MigrationDialog";
import { UpdateRpcButton } from "@/components/UpdateRpcButton";
import { Button } from "@/components/ui/Button";
import { BRAND } from "@/config/brand";
import { erc20Abi } from "@/config/abis";
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
  const [ecosystem, setEcosystem] = useState<Ecosystem>("data");
  const [isTestnet, setIsTestnet] = useState(false);
  const [amountInput, setAmountInput] = useState("");
  const [dialogOpen, setDialogOpen] = useState(false);

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

  const amountWei = useMemo(() => {
    if (!amountInput) return 0n;
    try {
      return parseUnits(amountInput, network.from.decimals);
    } catch {
      return 0n;
    }
  }, [amountInput, network.from.decimals]);

  const balanceValue = balance.data ?? 0n;
  const onWrongChain = isConnected && chainId !== network.chain.id;
  const exceedsBalance = amountWei > balanceValue;
  const canSwap =
    isConnected &&
    !onWrongChain &&
    migrationReady &&
    amountWei > 0n &&
    !exceedsBalance;

  const swapLabel = (() => {
    if (!migrationReady) return "Migration unavailable";
    if (amountWei === 0n) return "Enter an amount";
    if (exceedsBalance) return "Insufficient balance";
    return `Swap to ${network.to.symbol}`;
  })();

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
          iconUrl={BRAND.token.DATA.svg}
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
        {!isConnected ? (
          <ConnectButton.Custom>
            {({ openConnectModal }) => (
              <Button className="w-full" onClick={openConnectModal}>
                Connect Wallet
              </Button>
            )}
          </ConnectButton.Custom>
        ) : onWrongChain ? (
          <UpdateRpcButton network={network} />
        ) : (
          <Button
            className="w-full"
            disabled={!canSwap}
            onClick={() => setDialogOpen(true)}
          >
            {swapLabel}
          </Button>
        )}
      </div>

      {!migrationReady ? (
        <p className="mt-3 text-center text-xs text-[color:var(--color-muted)]">
          The migration contract for {network.chain.name} is not configured yet.
        </p>
      ) : null}

      {dialogOpen && address ? (
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
