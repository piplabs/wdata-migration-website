"use client";

import {
  type Config,
  readContract,
  waitForTransactionReceipt,
  watchAsset,
  writeContract,
} from "@wagmi/core";
import { useCallback, useMemo, useState } from "react";
import type { Address } from "viem";
import { useConfig } from "wagmi";

import { erc20Abi, migrationAbi, wrapperAbi } from "@/config/abis";
import type { NetworkConfig } from "@/config/networks";

export type StepStatus = "idle" | "awaitingWallet" | "mining" | "success" | "error";

export interface MigrationStep {
  key: string;
  title: string;
  description: string;
  /** Token-add steps don't produce an on-chain tx hash. */
  isWatchAsset?: boolean;
}

interface MigrationState {
  current: number;
  statuses: StepStatus[];
  hashes: (string | undefined)[];
  error: string | undefined;
}

function buildSteps(network: NetworkConfig): MigrationStep[] {
  if (network.flow === "wrapper") {
    return [
      {
        key: "withdraw",
        title: `Unwrap ${network.from.symbol}`,
        description: `Withdraw native ${network.chain.nativeCurrency.symbol} from ${network.from.symbol}.`,
      },
      {
        key: "deposit",
        title: `Wrap into ${network.to.symbol}`,
        description: `Deposit native ${network.chain.nativeCurrency.symbol} to receive ${network.to.symbol}.`,
      },
      {
        key: "addToken",
        title: `Add ${network.to.symbol} to wallet`,
        description: `Track your ${network.to.symbol} balance in your wallet. (Optional)`,
        isWatchAsset: true,
      },
    ];
  }
  return [
    {
      key: "approve",
      title: `Approve ${network.from.symbol}`,
      description: `Allow the migration contract to spend your ${network.from.symbol}.`,
    },
    {
      key: "migrate",
      title: `Migrate to ${network.to.symbol}`,
      description: `Swap ${network.from.symbol} for ${network.to.symbol} 1:1.`,
    },
    {
      key: "addToken",
      title: `Add ${network.to.symbol} to wallet`,
      description: `Track your ${network.to.symbol} balance in your wallet.`,
      isWatchAsset: true,
    },
  ];
}

function errorMessage(error: unknown): string {
  if (error && typeof error === "object" && "shortMessage" in error) {
    return String((error as { shortMessage: unknown }).shortMessage);
  }
  return error instanceof Error ? error.message : "Transaction failed.";
}

async function runWrapperStep(
  config: Config,
  network: NetworkConfig,
  account: Address,
  amount: bigint,
  stepKey: string,
): Promise<string> {
  if (stepKey === "withdraw") {
    return writeContract(config, {
      account,
      chainId: network.chain.id,
      abi: wrapperAbi,
      address: network.from.address,
      functionName: "withdraw",
      args: [amount],
    });
  }
  return writeContract(config, {
    account,
    chainId: network.chain.id,
    abi: wrapperAbi,
    address: network.to.address,
    functionName: "deposit",
    args: [],
    value: amount,
  });
}

async function runLockMintStep(
  config: Config,
  network: NetworkConfig,
  account: Address,
  amount: bigint,
  stepKey: string,
): Promise<string> {
  if (!network.migration) {
    throw new Error("Migration contract address is not configured for this network.");
  }
  if (stepKey === "approve") {
    return writeContract(config, {
      account,
      chainId: network.chain.id,
      abi: erc20Abi,
      address: network.from.address,
      functionName: "approve",
      args: [network.migration, amount],
    });
  }
  return writeContract(config, {
    account,
    chainId: network.chain.id,
    abi: migrationAbi,
    address: network.migration,
    functionName: "migrate",
    args: [amount],
  });
}

export function useMigration(
  network: NetworkConfig,
  amount: bigint,
  account: Address | undefined,
) {
  const config = useConfig();
  const steps = useMemo(() => buildSteps(network), [network]);

  const [state, setState] = useState<MigrationState>(() => ({
    current: 0,
    statuses: steps.map(() => "idle"),
    hashes: steps.map(() => undefined),
    error: undefined,
  }));

  const setStatus = useCallback((index: number, status: StepStatus) => {
    setState((prev) => {
      const statuses = [...prev.statuses];
      statuses[index] = status;
      return { ...prev, statuses };
    });
  }, []);

  const reset = useCallback(() => {
    setState({
      current: 0,
      statuses: steps.map(() => "idle"),
      hashes: steps.map(() => undefined),
      error: undefined,
    });
  }, [steps]);

  const runStep = useCallback(
    async (index: number) => {
      const step = steps[index];
      if (!step || !account) return;

      setState((prev) => ({ ...prev, error: undefined }));

      try {
        if (step.isWatchAsset) {
          setStatus(index, "awaitingWallet");
          // MetaMask rejects wallet_watchAsset (-32602) when the passed symbol/
          // decimals differ from the token's on-chain values, so prefer on-chain
          // metadata. Fall back to config if the reads fail: the migration has
          // already succeeded by this step, so a failed metadata read must not mark
          // it errored and make a completed swap look failed.
          let assetSymbol = network.to.symbol;
          let assetDecimals = network.to.decimals;
          try {
            const [onchainSymbol, onchainDecimals] = await Promise.all([
              readContract(config, {
                abi: erc20Abi,
                address: network.to.address,
                functionName: "symbol",
                chainId: network.chain.id,
              }),
              readContract(config, {
                abi: erc20Abi,
                address: network.to.address,
                functionName: "decimals",
                chainId: network.chain.id,
              }),
            ]);
            assetSymbol = onchainSymbol;
            assetDecimals = onchainDecimals;
          } catch {
            // keep the configured symbol/decimals
          }
          await watchAsset(config, {
            type: "ERC20",
            options: {
              address: network.to.address,
              symbol: assetSymbol,
              decimals: assetDecimals,
              ...(network.to.image ? { image: network.to.image } : {}),
            },
          });
          setStatus(index, "success");
          setState((prev) => ({ ...prev, current: index + 1 }));
          return;
        }

        setStatus(index, "awaitingWallet");
        const hash =
          network.flow === "wrapper"
            ? await runWrapperStep(config, network, account, amount, step.key)
            : await runLockMintStep(config, network, account, amount, step.key);

        setState((prev) => {
          const hashes = [...prev.hashes];
          hashes[index] = hash;
          return { ...prev, hashes };
        });
        setStatus(index, "mining");

        const receipt = await waitForTransactionReceipt(config, {
          hash: hash as `0x${string}`,
          chainId: network.chain.id,
        });
        if (receipt.status === "reverted") {
          throw new Error("Transaction reverted on-chain.");
        }

        setStatus(index, "success");
        setState((prev) => ({ ...prev, current: index + 1 }));
      } catch (error) {
        setStatus(index, "error");
        setState((prev) => ({ ...prev, error: errorMessage(error) }));
      }
    },
    [account, amount, config, network, setStatus, steps],
  );

  const runCurrent = useCallback(() => runStep(state.current), [runStep, state]);

  const isComplete = state.current >= steps.length;
  const isBusy =
    state.statuses[state.current] === "awaitingWallet" ||
    state.statuses[state.current] === "mining";

  return {
    steps,
    current: state.current,
    statuses: state.statuses,
    hashes: state.hashes,
    error: state.error,
    isComplete,
    isBusy,
    runCurrent,
    reset,
  };
}
