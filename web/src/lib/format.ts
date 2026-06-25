import { formatUnits } from "viem";

/** Human-readable token amount, trimmed to `maxFractionDigits` significant decimals. */
export function formatAmount(
  value: bigint,
  decimals: number,
  maxFractionDigits = 6,
): string {
  const full = formatUnits(value, decimals);
  const [whole, fraction = ""] = full.split(".");
  if (!fraction) return whole ?? "0";
  const trimmed = fraction.slice(0, maxFractionDigits).replace(/0+$/, "");
  return trimmed ? `${whole}.${trimmed}` : (whole ?? "0");
}

/** Short address for display, e.g. 0x1514…0000. */
export function shortenAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

/** Build an explorer link for a tx hash given a chain's explorer base url. */
export function txUrl(explorerUrl: string | undefined, hash: string): string {
  if (!explorerUrl) return "#";
  return `${explorerUrl.replace(/\/$/, "")}/tx/${hash}`;
}
