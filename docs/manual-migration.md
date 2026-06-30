<!-- DRAFT — do not publish to users until the migration reserve is funded for production volume. -->

# Migrate wIP → WDATAIP on BSC

You swap **wIP** for **WDATAIP** at **1:1** on **BNB Smart Chain (BSC)**. Migration is **one-way** — there is no reverse.

## What you need

- A wallet (e.g. MetaMask) set to **BNB Smart Chain (BSC) mainnet**
- Some **wIP** to migrate
- A little **BNB** to pay for gas

## Official addresses — use only these

| Token / contract | Address |
| --- | --- |
| Migration contract | [`0x093F607c32fCd57C2f008E47c8e16cccaE2cE0B8`](https://bscscan.com/address/0x093F607c32fCd57C2f008E47c8e16cccaE2cE0B8) |
| wIP (you deposit) | [`0x4d6394bC3031F751EdcE368C189b0E060b527107`](https://bscscan.com/address/0x4d6394bC3031F751EdcE368C189b0E060b527107) |
| WDATAIP (you receive) | [`0xA37EDed373c5cdF88644db7C6b89f222e756aFB2`](https://bscscan.com/address/0xA37EDed373c5cdF88644db7C6b89f222e756aFB2) |

> Security: only use the addresses above. Never trust addresses from DMs, ads, or search results.

## Amounts are in wei (18 decimals)

Both tokens use 18 decimals, so on BscScan you enter amounts in **wei**.
Example: **1 wIP = `1000000000000000000`** (a 1 followed by 18 zeros).
BscScan's number fields have a small **`× 10^18`** helper next to them — use it so you don't miscount zeros.

## Step 1 — Approve the migration contract to spend your wIP

1. Open the wIP contract → **Contract → Write Contract**:
   [bscscan.com/address/0x4d6394bC…527107#writeContract](https://bscscan.com/address/0x4d6394bC3031F751EdcE368C189b0E060b527107#writeContract)
2. Click **Connect Wallet** and connect your wallet.
3. Find **`approve`** (function **1** in the list) and fill in:
   - `spender` = `0x093F607c32fCd57C2f008E47c8e16cccaE2cE0B8` (the migration contract)
   - `amount` = how much wIP you want to migrate, **in wei**
4. Click **Write** and confirm in your wallet.

## Step 2 — Migrate

1. Open the migration contract → **Contract → Write Contract**:
   [bscscan.com/address/0x093F607c…E0B8#writeContract](https://bscscan.com/address/0x093F607c32fCd57C2f008E47c8e16cccaE2cE0B8#writeContract)
2. Click **Connect Wallet** and connect your wallet.
3. Find **`migrate`** (function **2** in the list) and set `amount` = the **same** wei amount you approved in Step 1.
4. Click **Write** and confirm. You receive the same amount of **WDATAIP**, 1:1.

## Troubleshooting

- **`migrate` fails immediately / "transfer amount exceeds allowance"** — your Step 1 approval was missing or too small. Redo Step 1 with the correct amount.
- **`WDATAIPInsufficientReserves`** — the reserve is currently too low for that amount. Try a smaller amount or contact the team.
- **Wrong amount** — remember amounts are in wei (18 decimals). `1` is not 1 token; `1000000000000000000` is.

## Notes

- 1:1, no protocol fee — you only pay BSC gas.
