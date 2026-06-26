# Handoff — WdataipMigration mainnet testing

Owner so far: Chao (barry-peng-story). Taking over mainnet e2e: **Yao**.
Tracking issue: piplabs/wdata-migration-website#3 ($DATA). Full test report (per-case table + tx hashes): see Notion "WdataipMigration — Test Report".

## TL;DR
`WdataipMigration` is a one-way **1:1 wIP → WDATAIP** swap on BSC, dispense-prefunded (no minting). Reserve is funded by bridging `WDATA` from the home chain (Story / on testnet: OP Sepolia) into the BSC OFT. Testnet e2e is **fully green and scripted**; this doc hands you the scripts + the mainnet runbook.

**Status (testnet):** L1 unit/fuzz/invariant **28 ✅** · L2 mainnet-fork (real BSC tokens) **4 ✅** · L3 scripted testnet e2e (BSC testnet ↔ OP Sepolia) **17 ✅ / 0 ❌** (+1 bridge finding). Reproducible; run logs in `~/run-logs/wdataip-e2e/` (last 2 kept).

## Contract (`src/WdataipMigration.sol`)
- `migrate(amount)`: pulls `amount` wIP (requires approval), sends `amount` WDATAIP from the contract's pre-funded balance. Reverts `WDATAIPInsufficientReserves` if under-funded. `nonReentrant`. Reads live `balanceOf` (donation-immune).
- `rescue(token,to,amount)` **onlyOwner**: pulls any token out (LP recovery; also the only "pause" — drain the reserve).
- `availableWdataip()`: current reserve.
- Ownable2Step + ReentrancyGuard, solc 0.8.24. Raw 1:1 → **requires both tokens 18-dec, fee-free, non-rebasing**.

## Repo layout (`wdataip-migration-contract/`)
- `src/WdataipMigration.sol` — the contract
- `script/DeployWdataipMigration.s.sol` — forge deploy (env: PRIVATE_KEY, OWNER_ADDRESS, WIP_ADDRESS, WDATAIP_ADDRESS; mainnet token addrs are the script defaults)
- `script/e2e-testnet.sh` — **the reproducible e2e** (deploy → bridge-in → fund → migrate battery → rescue → drain → bridge-out), pure `cast`, on-chain assertions
- `test/WdataipMigration.t.sol` / `.security.t.sol` / `.invariant.t.sol` — L1
- `test/WdataipMigration.fork.t.sol` — L2 (real BSC tokens, gated on `BSC_RPC`)
- `.env` — **gitignored**; create your own (see below). Chao DMs the testnet operator key separately.

## How to run
```bash
# deps (once): clone forge-std + OZ v5.0.2 into lib/ (foundry.toml remaps to lib/)
forge build
# L1: unit/fuzz/invariant
forge test --no-match-path 'test/*fork*'
# L2: mainnet-fork on the real BSC tokens
BSC_RPC=https://bsc-dataseed.binance.org forge test --match-path test/WdataipMigration.fork.t.sol
# L3: scripted testnet e2e (needs .env with PRIVATE_KEY + operator funded on both chains)
bash script/e2e-testnet.sh
```

## Bridge topology (LayerZero v2 OFT)
Model = **WDATAAdapter (lock/unlock, home chain) ↔ WDATAOFT (mint/burn, BSC)**. The BSC OFT **is** the WDATAIP the migration dispenses.

| | Testnet (rehearsal) | Mainnet |
|---|---|---|
| Home Adapter | OP Sepolia `0x9BF8…d255` (WDATA `0xf9dD…A951`) | Story mainnet `0xA37EDed3…56aFB2` (WDATA `0xD18a5634…`) |
| BSC OFT = WDATAIP | BSC testnet `0x3A64…697c` | BSC mainnet **`0xA37EDed3…56aFB2`** |
| wIP | test mock (deploy your own) | `0x4d6394bC…527107` (18-dec, fee-free, verified) |
| EIDs | OP Sepolia 40232 ↔ BSC testnet 40102 | see `wdata-oft-bridge/layerzero.mainnet.config.ts` (story-mainnet ↔ bsc-mainnet) |

Note: testnet uses OP Sepolia as the home stand-in (Aeneid has no LZ endpoint). Bridge repo (deployed OFT/Adapter + hardhat tasks) = `piplabs/wdata-oft-bridge`. The e2e script drives the bridge via `cast` directly, so it does **not** require that repo.

## Mainnet runbook (your task)
1. **Owner = a multisig** (Gnosis Safe), NOT an EOA — `rescue` can pull ALL wIP + WDATAIP, so owner-key compromise = total loss, and owner can front-run/grief migrations.
2. Deploy `WdataipMigration` on BSC mainnet: `WIP_ADDRESS=0x4d6394bC…527107`, `WDATAIP_ADDRESS=0xA37EDed3…56aFB2` (the BSC mainnet OFT), `OWNER_ADDRESS=<the Safe>`. (`forge script script/DeployWdataipMigration.s.sol`.)
3. **Fund the reserve** with WDATAIP: bridge `WDATA` from Story mainnet → BSC (Story Adapter → BSC OFT mint), or have Binance fill it. Confirm `availableWdataip()` covers expected volume.
4. Run the e2e flow adapted to mainnet (copy `e2e-testnet.sh` → set mainnet RPCs/addresses/EIDs, tiny amounts first): migrate 1:1 → failure paths → bridge BSC↔Story round-trip → reconcile 1:1.
5. **Canary**: a tiny real migrate + bridge, verify, then scale + monitor `availableWdataip()`.

## Gas gotchas (hit on testnet — likely apply to OP-stack/BSC mainnet too)
- **OP-stack RPCs** reject auto-estimated gas ("intrinsic gas too high") → pass an explicit `--gas-limit` on `cast send` (the e2e script does this for OP Sepolia).
- **BSC** suggested gas price (~0.1 gwei) can stall txs → force `--gas-price 10gwei` (script does this); bump + replace same-nonce if a tx sticks.
- Public RPCs drop rapid sequential sends → `cast send` waits for receipts; re-send the dropped one if state doesn't change.

## Env / secrets (DO NOT COMMIT)
`.env` (gitignored) needs:
```
PRIVATE_KEY=0x…        # operator/deployer key — Chao DMs this separately (testnet); use your own for mainnet
OWNER_ADDRESS=0x…      # mainnet: the multisig
WIP_ADDRESS=…          # mainnet default = 0x4d6394bC…527107
WDATAIP_ADDRESS=…      # mainnet default = 0xA37EDed3…56aFB2
BSC_RPC=… BSC_TESTNET_RPC=…
```

## Findings / must-dos for mainnet
- 🔴 owner = multisig (+ consider a timelock on `rescue`).
- 🟠 re-verify wIP & WDATAIP are 18-dec, fee-free, non-upgradeable on the exact mainnet addresses (done for current ones; redo if tokens change).
- 🟡 FCFS reserve, no pause → monitor `availableWdataip()`, pre-fund adequately, consider a per-tx cap.
- ⚠️ OFT `quoteSend` does not validate the recipient → enforce recipient validation in the dApp/UI (bridge layer, not this contract).
- Consider an external audit (Raul raised Binance auditors) for a liquidity-holding contract.

## Testnet artifacts (reference)
- Manual run (verified tx hashes) + scripted run addresses: in the Notion report's "L3 on-chain tx record".
- Operator (testnet): `0x783A42CDB62cD126CcfC46AAdE5a0DDddCD010ec` (owns the testnet OFT; funded on BSC testnet + OP Sepolia).
