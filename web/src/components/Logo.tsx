export function Logo() {
  return (
    <span className="flex items-center gap-2.5 select-none">
      <span
        className="flex h-8 w-8 items-center justify-center rounded-lg border border-[color:var(--color-border-strong)] bg-[color:var(--color-surface-2)] font-[family-name:var(--font-display)] text-sm font-bold"
        aria-hidden="true"
      >
        D
      </span>
      <span className="font-[family-name:var(--font-display)] text-lg font-semibold tracking-tight">
        DATA Migration
      </span>
    </span>
  );
}
