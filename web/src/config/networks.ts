import { type Address, type Chain, defineChain } from "viem";

import { BRAND } from "@/config/brand";

/**
 * How a network performs the migration:
 * - `wrapper`: Data Network. Unwrap WIP to native (`withdraw`), re-wrap into WDATA
 *   (`deposit`). Two txs, no approval.
 * - `lockMint`: BNB Smart Chain. Approve wIP, then `migrate` on the WdataipMigration
 *   contract which dispenses pre-funded WDATAIP 1:1.
 */
export type Flow = "wrapper" | "lockMint";

export interface TokenInfo {
  address: Address;
  symbol: string;
  name: string;
  decimals: number;
  /** Logo used when adding the token to the wallet (wallet_watchAsset). */
  image?: string;
}

export interface NetworkConfig {
  chain: Chain;
  flow: Flow;
  ecosystem: "data" | "bsc";
  isTestnet: boolean;
  from: TokenInfo;
  to: TokenInfo;
  /** Required for `lockMint`; the WdataipMigration contract address. */
  migration?: Address;
}

// Next.js inlines NEXT_PUBLIC_* into the client bundle only when referenced by literal
// name at build time; a dynamic process.env[key] resolves to undefined in the browser.
// So every var is listed literally here and env() just reads this statically-inlined map.
const PUBLIC_ENV: Record<string, string | undefined> = {
  NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID: process.env.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID,
  NEXT_PUBLIC_DATA_RPC_URL: process.env.NEXT_PUBLIC_DATA_RPC_URL,
  NEXT_PUBLIC_DATA_WIP_ADDRESS: process.env.NEXT_PUBLIC_DATA_WIP_ADDRESS,
  NEXT_PUBLIC_DATA_WDATA_ADDRESS: process.env.NEXT_PUBLIC_DATA_WDATA_ADDRESS,
  NEXT_PUBLIC_AENEID_RPC_URL: process.env.NEXT_PUBLIC_AENEID_RPC_URL,
  NEXT_PUBLIC_AENEID_WIP_ADDRESS: process.env.NEXT_PUBLIC_AENEID_WIP_ADDRESS,
  NEXT_PUBLIC_AENEID_WDATA_ADDRESS: process.env.NEXT_PUBLIC_AENEID_WDATA_ADDRESS,
  NEXT_PUBLIC_BSC_RPC_URL: process.env.NEXT_PUBLIC_BSC_RPC_URL,
  NEXT_PUBLIC_BSC_WIP_ADDRESS: process.env.NEXT_PUBLIC_BSC_WIP_ADDRESS,
  NEXT_PUBLIC_BSC_WDATAIP_ADDRESS: process.env.NEXT_PUBLIC_BSC_WDATAIP_ADDRESS,
  NEXT_PUBLIC_BSC_MIGRATION_ADDRESS: process.env.NEXT_PUBLIC_BSC_MIGRATION_ADDRESS,
  NEXT_PUBLIC_BSC_TESTNET_RPC_URL: process.env.NEXT_PUBLIC_BSC_TESTNET_RPC_URL,
  NEXT_PUBLIC_BSC_TESTNET_WIP_ADDRESS: process.env.NEXT_PUBLIC_BSC_TESTNET_WIP_ADDRESS,
  NEXT_PUBLIC_BSC_TESTNET_WDATAIP_ADDRESS: process.env.NEXT_PUBLIC_BSC_TESTNET_WDATAIP_ADDRESS,
  NEXT_PUBLIC_BSC_TESTNET_MIGRATION_ADDRESS: process.env.NEXT_PUBLIC_BSC_TESTNET_MIGRATION_ADDRESS,
};

const env = (key: string, fallback = ""): string =>
  (PUBLIC_ENV[key] ?? "").trim() || fallback;

const asAddress = (value: string): Address | undefined =>
  /^0x[0-9a-fA-F]{40}$/.test(value) ? (value as Address) : undefined;

const DATA_CURRENCY = { name: "DATA", symbol: "DATA", decimals: 18 } as const;
const BNB_CURRENCY = { name: "BNB", symbol: "BNB", decimals: 18 } as const;

const WIP_PREDEPLOY = "0x1514000000000000000000000000000000000000" as Address;
const WDATA_CREATE3 = "0xD18a56346227f25D1410F98f78234305660bB877" as Address;
const ZERO = "0x0000000000000000000000000000000000000000" as Address;

const bscMigration = asAddress(env("NEXT_PUBLIC_BSC_MIGRATION_ADDRESS"));
const bscTestnetMigration = asAddress(env("NEXT_PUBLIC_BSC_TESTNET_MIGRATION_ADDRESS"));

export const dataNetwork = {
  ...defineChain({
    id: 1514,
    name: "Data Network",
    nativeCurrency: DATA_CURRENCY,
    rpcUrls: {
      default: { http: [env("NEXT_PUBLIC_DATA_RPC_URL", "https://mainnet.datarpc.io")] },
    },
    blockExplorers: {
      default: { name: "DATA Network Explorer", url: "https://datanetscan.io" },
    },
  }),
  iconUrl: BRAND.token.DATA.png,
  iconBackground: "#ffffff",
};

export const aeneid = {
  ...defineChain({
    id: 1315,
    name: "Aeneid Data Network",
    nativeCurrency: DATA_CURRENCY,
    rpcUrls: {
      default: { http: [env("NEXT_PUBLIC_AENEID_RPC_URL", "https://aeneid.datarpc.io")] },
    },
    blockExplorers: {
      default: { name: "Aeneid Explorer", url: "https://aeneid.datanetscan.io" },
    },
    testnet: true,
  }),
  iconUrl: BRAND.token.DATA.png,
  iconBackground: "#ffffff",
};

export const bsc: Chain = defineChain({
  id: 56,
  name: "BNB Smart Chain",
  nativeCurrency: BNB_CURRENCY,
  rpcUrls: {
    default: { http: [env("NEXT_PUBLIC_BSC_RPC_URL", "https://bsc-dataseed.bnbchain.org")] },
  },
  blockExplorers: { default: { name: "BscScan", url: "https://bscscan.com" } },
});

export const bscTestnet: Chain = defineChain({
  id: 97,
  name: "BNB Smart Chain Testnet",
  nativeCurrency: { name: "tBNB", symbol: "tBNB", decimals: 18 },
  rpcUrls: {
    default: {
      http: [
        env(
          "NEXT_PUBLIC_BSC_TESTNET_RPC_URL",
          "https://data-seed-prebsc-1-s1.bnbchain.org:8545",
        ),
      ],
    },
  },
  blockExplorers: { default: { name: "BscScan Testnet", url: "https://testnet.bscscan.com" } },
  testnet: true,
});

export const NETWORKS: Record<number, NetworkConfig> = {
  [dataNetwork.id]: {
    chain: dataNetwork,
    flow: "wrapper",
    ecosystem: "data",
    isTestnet: false,
    from: {
      address: asAddress(env("NEXT_PUBLIC_DATA_WIP_ADDRESS")) ?? WIP_PREDEPLOY,
      symbol: "WIP",
      name: "Wrapped IP",
      decimals: 18,
    },
    to: {
      address: asAddress(env("NEXT_PUBLIC_DATA_WDATA_ADDRESS")) ?? WDATA_CREATE3,
      symbol: "WDATA",
      name: "Wrapped DATA",
      decimals: 18,
      image: BRAND.token.WDATA.png,
    },
  },
  [aeneid.id]: {
    chain: aeneid,
    flow: "wrapper",
    ecosystem: "data",
    isTestnet: true,
    from: {
      address: asAddress(env("NEXT_PUBLIC_AENEID_WIP_ADDRESS")) ?? WIP_PREDEPLOY,
      symbol: "WIP",
      name: "Wrapped IP",
      decimals: 18,
    },
    to: {
      address: asAddress(env("NEXT_PUBLIC_AENEID_WDATA_ADDRESS")) ?? WDATA_CREATE3,
      symbol: "WDATA",
      name: "Wrapped DATA",
      decimals: 18,
      image: BRAND.token.WDATA.png,
    },
  },
  [bsc.id]: {
    chain: bsc,
    flow: "lockMint",
    ecosystem: "bsc",
    isTestnet: false,
    from: {
      address:
        asAddress(env("NEXT_PUBLIC_BSC_WIP_ADDRESS")) ??
        ("0x4d6394bC3031F751EdcE368C189b0E060b527107" as Address),
      symbol: "wIP",
      name: "Wrapped IP",
      decimals: 18,
    },
    to: {
      address:
        asAddress(env("NEXT_PUBLIC_BSC_WDATAIP_ADDRESS")) ??
        ("0xA37EDed373c5cdF88644db7C6b89f222e756aFB2" as Address),
      symbol: "WDATAIP",
      name: "Wrapped DATAIP",
      decimals: 18,
      image: BRAND.token.WDATA.png,
    },
    ...(bscMigration ? { migration: bscMigration } : {}),
  },
  [bscTestnet.id]: {
    chain: bscTestnet,
    flow: "lockMint",
    ecosystem: "bsc",
    isTestnet: true,
    from: {
      address: asAddress(env("NEXT_PUBLIC_BSC_TESTNET_WIP_ADDRESS")) ?? ZERO,
      symbol: "wIP",
      name: "Wrapped IP",
      decimals: 18,
    },
    to: {
      address: asAddress(env("NEXT_PUBLIC_BSC_TESTNET_WDATAIP_ADDRESS")) ?? ZERO,
      symbol: "WDATAIP",
      name: "Wrapped DATAIP",
      decimals: 18,
      image: BRAND.token.WDATA.png,
    },
    ...(bscTestnetMigration ? { migration: bscTestnetMigration } : {}),
  },
};

export const ALL_CHAINS: readonly [Chain, ...Chain[]] = [
  dataNetwork,
  aeneid,
  bsc,
  bscTestnet,
];

export const getNetwork = (chainId: number | undefined): NetworkConfig | undefined =>
  chainId === undefined ? undefined : NETWORKS[chainId];

export const WALLET_CONNECT_PROJECT_ID = env(
  "NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID",
);

export const LEARN_MORE_URL = "https://datafdn.org";
