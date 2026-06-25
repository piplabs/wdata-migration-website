import { LEARN_MORE_URL } from "@/config/networks";

export function Footer() {
  return (
    <footer className="w-full border-t border-[color:var(--color-border)]">
      <div className="mx-auto flex max-w-5xl flex-col items-center justify-between gap-2 px-4 py-6 text-sm text-[color:var(--color-muted)] sm:flex-row sm:px-6">
        <span>One-way migration · WIP → WDATA</span>
        <a
          href={LEARN_MORE_URL}
          target="_blank"
          rel="noreferrer"
          className="transition-colors hover:text-[color:var(--color-fg)]"
        >
          Learn More about DATA
        </a>
      </div>
    </footer>
  );
}
