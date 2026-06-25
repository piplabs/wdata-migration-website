import type { ButtonHTMLAttributes, ReactNode } from "react";

type Variant = "primary" | "secondary" | "ghost";

const base =
  "inline-flex items-center justify-center gap-2 rounded-xl font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[color:var(--color-fg)]/40";

const sizes = "h-12 px-5 text-sm";

const variants: Record<Variant, string> = {
  primary: "bg-[color:var(--color-fg)] text-[color:var(--color-bg)] hover:bg-white",
  secondary:
    "bg-[color:var(--color-surface-2)] text-[color:var(--color-fg)] border border-[color:var(--color-border-strong)] hover:border-[color:var(--color-fg)]/40",
  ghost:
    "bg-transparent text-[color:var(--color-muted)] hover:text-[color:var(--color-fg)]",
};

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  children: ReactNode;
}

export function Button({
  variant = "primary",
  className = "",
  children,
  ...props
}: ButtonProps) {
  return (
    <button className={`${base} ${sizes} ${variants[variant]} ${className}`} {...props}>
      {children}
    </button>
  );
}
