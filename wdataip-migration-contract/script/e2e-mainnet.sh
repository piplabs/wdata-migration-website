#!/usr/bin/env bash
# Phase 3 (mainnet canary e2e) for the DEPLOYED WdataipMigration. Reproducible, env-driven,
# on-chain assertions, NO output suppression. Mainnet counterpart of script/e2e-testnet.sh.
#
# Owner of the deployed contract is the 3-of-5 Safe, so owner-only `rescue` is NOT exercised here
# (it needs a Safe tx); only the non-owner `rescue` revert is checked. State-changing happy paths
# are real txs; revert conditions use static `cast call` asserting the exact custom-error selector.
#
# Flow: preflight balances -> S1 migrate 1:1 -> failure paths (static) -> bridge WDATAIP BSC->Story
#       -> reconcile 1:1. Env (source .env): PRIVATE_KEY required; rest default to mainnet values.
set -uo pipefail

STORY=${STORY_RPC:-https://mainnet.datarpc.io}
BSC=${BSC_RPC:-https://bsc-dataseed.bnbchain.org}
PK=${PRIVATE_KEY:?set PRIVATE_KEY (source .env)}
OP=${OPERATOR:-$(cast wallet address --private-key "$PK")}
WIP=${WIP_ADDRESS:-0x4d6394bC3031F751EdcE368C189b0E060b527107}
WDATAIP=${WDATAIP_OFT:-0xA37EDed373c5cdF88644db7C6b89f222e756aFB2}
WDATA=${WDATA_STORY:-0xD18a56346227f25D1410F98f78234305660bB877}
MIG=${MIGRATION:-0x093F607c32fCd57C2f008E47c8e16cccaE2cE0B8}
EID_STORY=30364
M=${MIGRATE_AMT:-1000000000000000}   # 0.001 per migrate
GLIM=${GASLIM:-300000}

PASS=0; FAIL=0
ok(){ echo "  OK   $1"; PASS=$((PASS+1)); }
bad(){ echo "  BAD  $1"; FAIL=$((FAIL+1)); }
die(){ echo "  FAIL $1" >&2; echo "==== SUMMARY: $PASS ok / $FAIL bad (aborted) ===="; exit 1; }
balof(){ cast call "$1" 'balanceOf(address)(uint256)' "$2" --rpc-url "$3" 2>/dev/null | awk '{print $1}'; }
hex(){ cast call "$@" 2>/dev/null | awk '{print $1}'; }
# static-call revert assertion against BSC
expect_revert(){ local sel=$1 label=$2; shift 2; local out
  out=$(cast call "$@" --rpc-url "$BSC" 2>&1)
  echo "$out" | grep -qi "$sel" && ok "$label reverts ($sel)" || bad "$label — got: $(echo "$out"|tail -1|cut -c1-90)"; }
# BSC state-changing send: explicit gas, checks receipt status
bsc_send(){ local out
  out=$(cast send "$@" --rpc-url "$BSC" --private-key "$PK" --gas-price 1000000000 --gas-limit "$GLIM" --json 2>&1) \
    || { bad "bsc tx errored: $* :: $(echo "$out"|head -c160)"; return 1; }
  echo "$out" | jq -e '.status=="0x1"' >/dev/null 2>&1 || { bad "bsc tx reverted: $*"; return 1; }
  echo "$out" | jq -r '"    tx="+.transactionHash' 2>/dev/null; }

SEL_ZEROAMT=$(cast sig 'ZeroAmount()')
SEL_RESERVE=$(cast sig 'WDATAIPInsufficientReserves(uint256,uint256)')
SEL_UNAUTH=$(cast sig 'OwnableUnauthorizedAccount(address)')

echo "operator=$OP  migration=$MIG  migrateAmt=$M"
echo "chainId bsc=$(cast chain-id --rpc-url $BSC) story=$(cast chain-id --rpc-url $STORY)"

# --- 0) preflight -----------------------------------------------------------------------------
echo "== 0) preflight balances =="
RES=$(hex "$MIG" 'availableWdataip()(uint256)' --rpc-url "$BSC")
WIPBAL=$(balof "$WIP" "$OP" "$BSC")
BNB=$(cast balance "$OP" --rpc-url "$BSC")
echo "  reserve availableWdataip = $RES"
echo "  operator wIP (BSC)       = $WIPBAL"
echo "  operator BNB (BSC)       = $BNB wei"
[ "$RES" -ge "$M" ] 2>/dev/null && ok "reserve >= migrate amount" || die "reserve $RES < migrate $M (fund first)"
[ "$WIPBAL" -ge "$M" ] 2>/dev/null && ok "wIP balance >= migrate amount" || die "operator has $WIPBAL wIP < $M — acquire wIP on BSC (e.g. Stargate WIP Story->BSC) before Phase 3"

# preflight-only gate: no state-changing tx runs unless explicitly enabled
[ "${CHECK_ONLY:-0}" = "1" ] && { echo "==== preflight OK (CHECK_ONLY=1, no writes) ===="; exit 0; }

# --- 1) S1 happy migrate ----------------------------------------------------------------------
echo "== 1) S1 migrate 1:1 =="
bsc_send "$WIP" 'approve(address,uint256)' "$MIG" "$M" || die "approve failed"
R0=$(hex "$MIG" 'availableWdataip()(uint256)' --rpc-url "$BSC"); WD0=$(balof "$WDATAIP" "$OP" "$BSC"); WIP0=$(balof "$WIP" "$MIG" "$BSC")
bsc_send "$MIG" 'migrate(uint256)' "$M" || die "migrate failed"
R1=$(hex "$MIG" 'availableWdataip()(uint256)' --rpc-url "$BSC"); WD1=$(balof "$WDATAIP" "$OP" "$BSC"); WIP1=$(balof "$WIP" "$MIG" "$BSC")
{ [ $((R0-R1)) -eq "$M" ] && [ $((WD1-WD0)) -eq "$M" ] && [ $((WIP1-WIP0)) -eq "$M" ]; } \
  && ok "migrate 1:1 (reserve -$M, user WDATAIP +$M, wIP locked +$M)" || bad "migrate accounting: dRes=$((R0-R1)) dWD=$((WD1-WD0)) dWIP=$((WIP1-WIP0))"

# --- 2) failure paths (static) ----------------------------------------------------------------
echo "== 2) failure paths (static cast call) =="
expect_revert "$SEL_ZEROAMT" "migrate(0)" "$MIG" 'migrate(uint256)' 0 --from "$OP"
NOAL=0x00000000000000000000000000000000DeaD0001
expect_revert "reverted" "migrate w/o allowance" "$MIG" 'migrate(uint256)' "$M" --from "$NOAL"
HUGE=100000000000000000000   # 100, >> reserve
expect_revert "$SEL_RESERVE" "migrate underfunded" "$MIG" 'migrate(uint256)' "$HUGE" --from "$OP"
expect_revert "$SEL_UNAUTH" "non-owner rescue" "$MIG" 'rescue(address,address,uint256)' "$WDATAIP" "$NOAL" 1 --from "$NOAL"

# --- 3) bridge WDATAIP BSC->Story + reconcile -------------------------------------------------
echo "== 3) bridge migrated WDATAIP back to Story =="
OUT=$(balof "$WDATAIP" "$OP" "$BSC")
[ "$OUT" -ge "$M" ] 2>/dev/null || die "operator WDATAIP $OUT < $M, nothing to bridge"
TO32=0x000000000000000000000000${OP#0x}
SP="($EID_STORY,$TO32,$M,$M,0x,0x,0x)"
FEE=$(cast call "$WDATAIP" 'quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)((uint256,uint256))' "$SP" false --rpc-url "$BSC" 2>&1 | grep -oE '[0-9]+' | head -1)
[ -n "$FEE" ] && ok "bridge-back nativeFee = $FEE wei (BNB)" || die "quoteSend returned no fee"
SW0=$(balof "$WDATA" "$OP" "$STORY")
out=$(cast send "$WDATAIP" 'send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)' "$SP" "($FEE,0)" "$OP" --value "$FEE" --rpc-url "$BSC" --private-key "$PK" --gas-price 1000000000 --gas-limit 800000 --json 2>&1) \
  || die "bridge-back send errored: $(echo "$out"|head -c160)"
echo "$out" | jq -e '.status=="0x1"' >/dev/null 2>&1 || die "bridge-back send reverted"
echo "$out" | jq -r '"    tx="+.transactionHash' 2>/dev/null
[ "$(balof "$WDATAIP" "$OP" "$BSC")" -eq $((OUT-M)) ] 2>/dev/null && ok "WDATAIP burned $M on BSC" || bad "BSC burn accounting"
echo "  waiting for WDATA unlock on Story (target +$M)..."
TGT=$((SW0+M))
for i in $(seq 1 60); do
  CUR=$(balof "$WDATA" "$OP" "$STORY")
  [ "$CUR" -ge "$TGT" ] 2>/dev/null && { ok "Story WDATA unlocked: $CUR (round-trip 1:1 closed)"; break; }
  echo "  [$i] Story WDATA = $CUR (target $TGT) ... waiting 15s"; sleep 15
done
[ "$(balof "$WDATA" "$OP" "$STORY")" -ge "$TGT" ] 2>/dev/null || bad "Story unlock not delivered in time"

echo "================ E2E SUMMARY: $PASS ok / $FAIL bad ================"
[ "$FAIL" -eq 0 ]
