// The Data Foundation brand kit, served from the piplabs CDN.
// Mirror of https://www.datafdn.org/brand-guide
const CDN = "https://assets.piplabs.xyz/datafdn.org/brand-kit/06252026";

export const BRAND = {
  /** Full white wordmark (no background) — for the dark header. */
  logoWhite: `${CDN}/Logo/TDF_Logo_White.svg`,
  /** Square symbol mark, white — for favicons / compact spots. */
  symbolWhite: `${CDN}/Symbol/TDF_Symbol_White.svg`,
  token: {
    /** Native DATA token mark. */
    DATA: {
      svg: `${CDN}/Token/DATA/TDF_Token_DATA.svg`,
      png: `${CDN}/Token/DATA/TDF_Token_DATA.png`,
    },
    /** Wrapped DATA token mark; used for WDATA / WDATAIP. */
    WDATA: {
      svg: `${CDN}/Token/WDATA/TDF_Token_WDATA.svg`,
      png: `${CDN}/Token/WDATA/TDF_Token_WDATA.png`,
    },
    /** Wrapped IP source token (WIP / wIP) — logo from datanetscan.io, vendored locally. */
    WIP: {
      png: "/tokens/wip.png",
    },
  },
} as const;
