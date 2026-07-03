import { BRAND } from "@/config/brand";

export function Logo() {
  return (
    <span className="flex items-center gap-3 select-none">
      {/* eslint-disable-next-line @next/next/no-img-element -- remote brand SVG, not optimizable */}
      <img src={BRAND.logoWhite} alt="Data Foundation" className="h-11 w-auto" />
      <span className="hidden font-[family-name:var(--font-display)] text-sm font-medium text-[color:var(--color-muted)] sm:inline">
        Migration
      </span>
    </span>
  );
}
