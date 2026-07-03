"use client";

import { useConnectModal } from "@rainbow-me/rainbowkit";
import { useEffect } from "react";
import type { Address } from "viem";

import { Button } from "@/components/ui/Button";
import { Spinner } from "@/components/ui/Spinner";
import type { NetworkConfig } from "@/config/networks";
import { useMigration } from "@/hooks/useMigration";
import { formatAmount, txUrl } from "@/lib/format";

interface MigrationDialogProps {
  network: NetworkConfig;
  amount: bigint;
  /** Undefined when the wallet disconnects mid-flow; the dialog stays open and re-prompts. */
  account: Address | undefined;
  onClose: () => void;
  onComplete: () => void;
}

function StepIcon({ status, index }: { status: string; index: number }) {
  if (status === "success") {
    return (
      <span className="flex h-7 w-7 items-center justify-center rounded-full bg-[color:var(--color-success)]/15 text-[color:var(--color-success)]">
        ✓
      </span>
    );
  }
  if (status === "error") {
    return (
      <span className="flex h-7 w-7 items-center justify-center rounded-full bg-[color:var(--color-danger)]/15 text-[color:var(--color-danger)]">
        !
      </span>
    );
  }
  if (status === "awaitingWallet" || status === "mining") {
    return (
      <span className="flex h-7 w-7 items-center justify-center rounded-full bg-[color:var(--color-surface-2)] text-[color:var(--color-fg)]">
        <Spinner />
      </span>
    );
  }
  return (
    <span className="flex h-7 w-7 items-center justify-center rounded-full border border-[color:var(--color-border-strong)] text-xs text-[color:var(--color-muted)]">
      {index + 1}
    </span>
  );
}

export function MigrationDialog({
  network,
  amount,
  account,
  onClose,
  onComplete,
}: MigrationDialogProps) {
  const { steps, current, statuses, hashes, error, isComplete, isBusy, runCurrent } =
    useMigration(network, amount, account);
  const { openConnectModal } = useConnectModal();

  useEffect(() => {
    if (isComplete) onComplete();
  }, [isComplete, onComplete]);

  const explorer = network.chain.blockExplorers?.default.url;
  const currentStatus = statuses[current];
  const showRetry = currentStatus === "error";
  const onOptionalAddStep =
    Boolean(account) && !isComplete && Boolean(steps[current]?.isWatchAsset);

  const actionLabel = (() => {
    if (isComplete) return "Done";
    if (currentStatus === "awaitingWallet") return "Confirm in wallet…";
    if (currentStatus === "mining") return "Confirming transaction…";
    if (showRetry) return "Retry";
    const step = steps[current];
    return step?.isWatchAsset ? `Add ${network.to.symbol}` : (step?.title ?? "Continue");
  })();

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
    >
      <div className="w-full max-w-md rounded-[var(--radius-card)] border border-[color:var(--color-border)] bg-[color:var(--color-surface)] p-6 shadow-2xl">
        <div className="mb-5 flex items-start justify-between">
          <div>
            <h2 className="font-[family-name:var(--font-display)] text-lg font-semibold">
              Migrate {network.from.symbol} → {network.to.symbol}
            </h2>
            <p className="mt-1 text-sm text-[color:var(--color-muted)]">
              {formatAmount(amount, network.from.decimals)} {network.from.symbol} on{" "}
              {network.chain.name}
            </p>
          </div>
          <button
            onClick={onClose}
            className="text-[color:var(--color-muted)] transition-colors hover:text-[color:var(--color-fg)]"
            aria-label="Close"
          >
            ✕
          </button>
        </div>

        <ol className="space-y-3">
          {steps.map((step, index) => {
            const status = statuses[index] ?? "idle";
            const hash = hashes[index];
            const active = index === current && !isComplete;
            return (
              <li
                key={step.key}
                className={`flex gap-3 rounded-xl border p-3 ${
                  active
                    ? "border-[color:var(--color-border-strong)] bg-[color:var(--color-surface-2)]"
                    : "border-transparent"
                }`}
              >
                <StepIcon status={status} index={index} />
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-medium">{step.title}</p>
                  <p className="text-xs text-[color:var(--color-muted)]">
                    {step.description}
                  </p>
                  {hash && explorer ? (
                    <a
                      href={txUrl(explorer, hash)}
                      target="_blank"
                      rel="noreferrer"
                      className="mt-1 inline-block text-xs text-[color:var(--color-fg)] underline underline-offset-2"
                    >
                      View transaction ↗
                    </a>
                  ) : null}
                </div>
              </li>
            );
          })}
        </ol>

        {!account && !isComplete ? (
          <p className="mt-4 rounded-lg bg-[color:var(--color-danger)]/10 px-3 py-2 text-sm text-[color:var(--color-danger)]">
            Wallet disconnected. Reconnect to continue the migration.
          </p>
        ) : error ? (
          <p className="mt-4 rounded-lg bg-[color:var(--color-danger)]/10 px-3 py-2 text-sm text-[color:var(--color-danger)]">
            {error}
          </p>
        ) : null}

        <div className="mt-6">
          {isComplete ? (
            <Button className="w-full" onClick={onClose}>
              {actionLabel}
            </Button>
          ) : !account ? (
            <Button className="w-full" onClick={() => openConnectModal?.()}>
              Reconnect wallet
            </Button>
          ) : onOptionalAddStep ? (
            <div className="flex gap-3">
              <Button className="flex-1" onClick={runCurrent} disabled={isBusy}>
                {isBusy ? <Spinner /> : null}
                {actionLabel}
              </Button>
              <Button
                variant="secondary"
                className="flex-1"
                onClick={() => {
                  onComplete();
                  onClose();
                }}
                disabled={isBusy}
              >
                Close
              </Button>
            </div>
          ) : (
            <Button className="w-full" onClick={runCurrent} disabled={isBusy}>
              {isBusy ? <Spinner /> : null}
              {actionLabel}
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}
