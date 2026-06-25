"use client";

import { useSwitchChain } from "wagmi";

import { Button } from "@/components/ui/Button";
import { Spinner } from "@/components/ui/Spinner";
import type { NetworkConfig } from "@/config/networks";

export function UpdateRpcButton({ network }: { network: NetworkConfig }) {
  const { switchChain, isPending } = useSwitchChain();

  const label =
    network.ecosystem === "data"
      ? `Update ${network.chain.name} RPC`
      : `Switch to ${network.chain.name}`;

  return (
    <Button
      className="w-full"
      onClick={() => switchChain({ chainId: network.chain.id })}
      disabled={isPending}
    >
      {isPending ? <Spinner /> : null}
      {isPending ? "Confirm in wallet…" : label}
    </Button>
  );
}
