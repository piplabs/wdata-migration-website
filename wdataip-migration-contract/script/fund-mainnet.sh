#!/usr/bin/env bash
# Phase 2 (mainnet): fund the deployed WdataipMigration reserve by bridging WDATA Story -> BSC.
# Reproducible, env-driven, on-chain assertions after every step, NO output suppression.
#
# Flow: wrap DATA -> WDATA (to reach RESERVE) -> approve adapter -> quoteSend ->
#       send (Story adapter locks WDATA, BSC OFT mints WDATAIP) -> wait for BSC mint ->
#       transfer WDATAIP into the migration contract -> assert availableWdataip() == RESERVE.
#
# Env (source .env first): PRIVATE_KEY required. Others default to the verified mainnet values.
set -uo pipefail

STORY=${STORY_RPC:-https://mainnet.datarpc.io}
BSC=${BSC_RPC:-https://bsc-dataseed.bnbchain.org}
PK=${PRIVATE_KEY:?set PRIVATE_KEY (source .env)}
OP=${OPERATOR:-$(cast wallet address --private-key "$PK")}
WDATA=${WDATA_STORY:-0xD18a56346227f25D1410F98f78234305660bB877}      # Story canonical WDATA
ADAPTER=${WDATA_ADAPTER:-0xA37EDed373c5cdF88644db7C6b89f222e756aFB2}  # Story OFTAdapter (lock-box)
WDATAIP=${WDATAIP_OFT:-0xA37EDed373c5cdF88644db7C6b89f222e756aFB2}    # BSC OFT (= WDATAIP)
MIG=${MIGRATION:-0x093F607c32fCd57C2f008E47c8e16cccaE2cE0B8}          # deployed WdataipMigration
EID_BSC=30102
AMT=${RESERVE:-10000000000000000}   # 0.01 (18 dec)
# Story RPC times out on eth_estimateGas (-32002) -> pass explicit gas-limit + gas-price, skip estimation.
GP=$(cast gas-price --rpc-url "$STORY" 2>/dev/null); { [ -n "$GP" ] && [ "$GP" != "0" ]; } || GP=5000000000
GASLIM=${GASLIM:-1200000}

ok(){ echo "  OK   $1"; }
die(){ echo "  FAIL $1" >&2; exit 1; }
balof(){ cast call "$1" 'balanceOf(address)(uint256)' "$2" --rpc-url "$3" 2>/dev/null | awk '{print $1}'; }

# story_send <args...> : legacy tx on Story, prints receipt, dies on error or status!=1
story_send(){
  local out
  out=$(cast send "$@" --rpc-url "$STORY" --private-key "$PK" --legacy --gas-limit "$GASLIM" --gas-price "$GP" --json 2>&1) \
    || die "story tx errored: $* :: $out"
  echo "$out" | jq -e '.status=="0x1"' >/dev/null 2>&1 \
    || die "story tx reverted (status!=1): $* :: $(echo "$out" | head -c 300)"
  echo "$out" | jq -r '"  tx="+.transactionHash+" gasUsed="+.gasUsed' 2>/dev/null
}

echo "operator=$OP  reserve=$AMT  migration=$MIG"
echo "chainId story=$(cast chain-id --rpc-url $STORY)  bsc=$(cast chain-id --rpc-url $BSC)"

# --- 1) wrap DATA -> WDATA up to RESERVE -------------------------------------------------------
echo "== 1) ensure WDATA balance >= reserve =="
WBAL=$(balof "$WDATA" "$OP" "$STORY")
echo "  WDATA bal now = $WBAL"
if [ "$WBAL" -lt "$AMT" ] 2>/dev/null; then
  NEED=$((AMT - WBAL))
  echo "  depositing $NEED wei native DATA -> WDATA"
  story_send "$WDATA" 'deposit()' --value "$NEED"
  WBAL=$(balof "$WDATA" "$OP" "$STORY")
fi
[ "$WBAL" -ge "$AMT" ] 2>/dev/null && ok "WDATA bal = $WBAL (>= $AMT)" || die "WDATA bal $WBAL < $AMT"

# --- 2) approve adapter -----------------------------------------------------------------------
echo "== 2) approve adapter for reserve =="
story_send "$WDATA" 'approve(address,uint256)' "$ADAPTER" "$AMT"
ALLOW=$(cast call "$WDATA" 'allowance(address,address)(uint256)' "$OP" "$ADAPTER" --rpc-url "$STORY" | awk '{print $1}')
[ "$ALLOW" -ge "$AMT" ] 2>/dev/null && ok "allowance = $ALLOW" || die "allowance $ALLOW < $AMT"

# --- 3) quote Story->BSC LZ fee ---------------------------------------------------------------
echo "== 3) quoteSend =="
TO32=0x000000000000000000000000${OP#0x}
SP="($EID_BSC,$TO32,$AMT,$AMT,0x,0x,0x)"
FEE=$(cast call "$ADAPTER" 'quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)((uint256,uint256))' "$SP" false --rpc-url "$STORY" 2>&1 | grep -oE '[0-9]+' | head -1)
[ -n "$FEE" ] || die "quoteSend returned no fee"
ok "nativeFee = $FEE wei"

# --- 4) send (bridge in) ----------------------------------------------------------------------
echo "== 4) send 0.01 WDATA Story -> BSC =="
W0=$(balof "$WDATAIP" "$OP" "$BSC")
story_send "$ADAPTER" 'send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)' "$SP" "($FEE,0)" "$OP" --value "$FEE"
NEWWBAL=$(balof "$WDATA" "$OP" "$STORY")
ok "WDATA locked; Story WDATA bal now = $NEWWBAL"

# --- 5) wait for WDATAIP mint on BSC ----------------------------------------------------------
echo "== 5) wait for BSC mint (WDATAIP balance to rise by $AMT) =="
TARGET=$((W0 + AMT))
for i in $(seq 1 60); do
  CUR=$(balof "$WDATAIP" "$OP" "$BSC")
  [ "$CUR" -ge "$TARGET" ] 2>/dev/null && { ok "BSC mint delivered: WDATAIP bal = $CUR"; break; }
  echo "  [$i] BSC WDATAIP bal = $CUR (target $TARGET) ... waiting 15s"
  sleep 15
done
CUR=$(balof "$WDATAIP" "$OP" "$BSC")
[ "$CUR" -ge "$TARGET" ] 2>/dev/null || die "BSC mint not delivered after wait (bal=$CUR target=$TARGET)"

# --- 6) fund the migration reserve ------------------------------------------------------------
echo "== 6) transfer $AMT WDATAIP -> migration =="
out=$(cast send "$WDATAIP" 'transfer(address,uint256)' "$MIG" "$AMT" --rpc-url "$BSC" --private-key "$PK" --gas-price 1000000000 --gas-limit 120000 --json 2>&1) \
  || die "bsc transfer errored: $out"
echo "$out" | jq -e '.status=="0x1"' >/dev/null 2>&1 || die "bsc transfer reverted: $(echo "$out"|head -c 300)"
echo "$out" | jq -r '"  tx="+.transactionHash' 2>/dev/null

# --- 7) assert reserve ------------------------------------------------------------------------
RES=$(cast call "$MIG" 'availableWdataip()(uint256)' --rpc-url "$BSC" | awk '{print $1}')
[ "$RES" -ge "$AMT" ] 2>/dev/null && ok "availableWdataip() = $RES (reserve funded)" || die "reserve $RES < $AMT"
echo "================ PHASE 2 DONE: reserve=$RES ================"
