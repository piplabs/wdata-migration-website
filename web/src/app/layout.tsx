import type { Metadata } from "next";
import { Inter, Poppins } from "next/font/google";
import type { ReactNode } from "react";

import { BRAND } from "@/config/brand";
import { Web3Provider } from "@/providers/Web3Provider";

import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-inter",
  display: "swap",
});

const poppins = Poppins({
  subsets: ["latin"],
  weight: ["500", "600", "700"],
  variable: "--font-poppins",
  display: "swap",
});

export const metadata: Metadata = {
  title: "DATA Migration — WIP to WDATA",
  description:
    "Migrate your wrapped IP (WIP / wIP) to wrapped DATA (WDATA / WDATAIP) on Data Network and BNB Smart Chain.",
  icons: { icon: BRAND.symbolWhite },
  openGraph: {
    title: "DATA Migration — WIP to WDATA",
    description:
      "Migrate your wrapped IP to wrapped DATA on Data Network and BNB Smart Chain.",
    images: [BRAND.token.WDATA.png],
  },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className={`${inter.variable} ${poppins.variable}`}>
      <body>
        <Web3Provider>{children}</Web3Provider>
      </body>
    </html>
  );
}
