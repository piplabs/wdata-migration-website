# DATA Migration dApp

Web app for migrating wrapped IP → wrapped DATA, one-way 1:1, on **Data Network**
(Story) and **BNB Smart Chain**. Built with Next.js, RainbowKit, wagmi, and viem.

## Flows

| Ecosystem | Chains | Steps |
| --- | --- | --- |
| Data Network | 1514 mainnet · 1315 Aeneid | 1. `WIP.withdraw(amount)` · 2. `WDATA.deposit{value:amount}()` · 3. add WDATA to wallet |
| BNB Smart Chain | 56 mainnet · 97 testnet | 1. `wIP.approve(migration, amount)` · 2. `WdataipMigration.migrate(amount)` · 3. add WDATAIP to wallet |

On Data Network both tokens are WETH9-style wrappers of the native token, so the
migration is unwrap-then-rewrap (no approval, two transactions). On BSC it is a
single `migrate` against the pre-funded [`WdataipMigration`](../wdataip-migration-contract)
contract.

Each step waits for its receipt before advancing; on error the dialog stays on the
failed step with a Retry button.

## Develop

```sh
pnpm install
cp .env.example .env.local   # fill in the values below
pnpm dev                     # http://localhost:3000
pnpm typecheck && pnpm lint  # must be clean
pnpm build
```

## Configuration (`.env.local`)

All config is via `NEXT_PUBLIC_*` env vars (see `.env.example`). Sensible defaults
ship for the Data Network tokens and RPCs, so testnet works out of the box once a
WalletConnect id is set.

| Var | Required | Notes |
| --- | --- | --- |
| `NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID` | yes | from https://cloud.reown.com |
| `NEXT_PUBLIC_DATA_WDATA_ADDRESS` | confirm | WDATA on chain 1514 (Create3 ⇒ likely `0xD18a…bB877`) |
| `NEXT_PUBLIC_AENEID_WIP_ADDRESS` | confirm | WIP on Aeneid (defaults to the predeploy) |
| `NEXT_PUBLIC_BSC_MIGRATION_ADDRESS` | yes for BSC | WdataipMigration on chain 56; BSC swaps are disabled until set |
| `NEXT_PUBLIC_BSC_TESTNET_*` | optional | wIP / WDATAIP / migration for chain 97 |

## Deploy (Vercel)

Set the env vars above in the Vercel project, then deploy. Default build command
(`next build`) and output are used; no extra config required.
