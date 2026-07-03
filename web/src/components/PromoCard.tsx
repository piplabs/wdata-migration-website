import { LEARN_MORE_URL } from "@/config/networks";

export function PromoCard() {
  return (
    <a
      href={LEARN_MORE_URL}
      target="_blank"
      rel="noreferrer"
      className="fixed bottom-6 right-6 z-40 hidden w-60 overflow-hidden rounded-[var(--radius-card)] border border-[color:var(--color-border)] bg-gradient-to-br from-[color:var(--color-surface-2)] to-[color:var(--color-bg)] p-5 shadow-2xl transition-colors hover:border-[color:var(--color-border-strong)] sm:block"
    >
      <p className="font-[family-name:var(--font-display)] text-lg font-semibold">
        Wrapped DATA
      </p>
      <p className="mt-2 text-sm text-[color:var(--color-muted)]">
        Learn more about DATA ↗
      </p>
    </a>
  );
}
