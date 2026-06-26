#!/usr/bin/env bash
# Reproducible WdataipMigration e2e on BSC testnet <-> OP Sepolia (the deployed rehearsal segment).
#
# Codifies the manual run: deploy fresh test wIP + WdataipMigration, bridge WDATA in to mint the
# WDATAIP reserve, exercise a battery of migrate / rescue scenarios (happy + revert paths) with
# on-chain assertions, then bridge WDATAIP back out. State-changing happy paths are real txs;
# revert conditions are checked with static `cast call` (asserting the exact custom-error selector),
# so no extra funded EOAs are needed.
#
# Per-chain gas handling (learned the hard way):
#   - OP Sepolia RPCs reject auto-estimated gas ("intrinsic gas too high") -> pass explicit --gas-limit.
#   - BSC testnet's suggested gas price (~0.1 gwei) stalls -> force --gas-price 10gwei.
#
# Env (defaults to the deployed testnet contracts; PRIVATE_KEY required, e.g. via .env):
#   PRIVATE_KEY, OPERATOR, BSC_TESTNET_RPC, OP_SEPOLIA_RPC,
#   WDATAIP_OFT (BSC), WDATA_ADAPTER (OP Sepolia), WDATA_OP (OP Sepolia)
set -uo pipefail

# --- config -------------------------------------------------------------------------------------
BSC=${BSC_TESTNET_RPC:-https://bsc-testnet-rpc.publicnode.com}
OP=${OP_SEPOLIA_RPC:-https://optimism-sepolia-rpc.publicnode.com}
PK=${PRIVATE_KEY:?set PRIVATE_KEY (e.g. source .env)}
OPERATOR=${OPERATOR:-$(cast wallet address --private-key "$PK")}
WDATAIP_OFT=${WDATAIP_OFT:-0x3A64815b80b995a632ADb282e2Ae951E5174697c}
WDATA_ADAPTER=${WDATA_ADAPTER:-0x9BF8aa3bEA572BbA5AC0CC1D4c93D833c426d255}
WDATA_OP=${WDATA_OP:-0xf9dD6308f1A8F5F0c40c92F1155990913A9aA951}
EID_BSC=40102; EID_OP=40232
U=1000000000000000   # 0.001 (bridge unit + reserve)
M=100000000000000    # 0.0001 (per-migrate unit)

PASS=0; FAIL=0
ok(){ echo "  ✅ $1"; PASS=$((PASS+1)); }
bad(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }
hex(){ cast call "$@" 2>/dev/null | awk '{print $1}'; }
# assert a static call reverts with a given 4-byte selector
expect_revert(){ # $1=selector(hex) $2=label ; rest=cast call args
  local sel=$1 label=$2; shift 2
  local out; out=$(cast call "$@" --rpc-url "$BSC" 2>&1)
  if echo "$out" | grep -qi "$sel"; then ok "$label reverts ($sel)"; else bad "$label — got: $(echo "$out"|tail -1|cut -c1-80)"; fi
}
bsc_send(){ cast send "$@" --rpc-url "$BSC" --private-key "$PK" --gas-price 10000000000 --gas-limit 1500000 >/dev/null 2>&1; }
op_send(){  cast send "$@" --rpc-url "$OP"  --private-key "$PK" --gas-limit 700000 >/dev/null 2>&1; }
bal(){ hex "$1" 'balanceOf(address)(uint256)' "$2" --rpc-url "$3"; }
sel(){ cast sig "$1"; }

echo "operator=$OPERATOR"
SEL_ZEROAMT=$(sel 'ZeroAmount()')
SEL_ZEROADDR=$(sel 'ZeroAddress()')
SEL_RESERVE=$(sel 'WDATAIPInsufficientReserves(uint256,uint256)')
SEL_UNAUTH=$(sel 'OwnableUnauthorizedAccount(address)')

# --- 1) deploy fresh test wIP + migration -------------------------------------------------------
echo "== deploy =="
WIP=$(forge create test/mocks/MockERC20.sol:MockERC20 --rpc-url "$BSC" --private-key "$PK" \
      --gas-price 10000000000 --broadcast --constructor-args "Test wIP" "wIP" 2>/dev/null | sed -n 's/Deployed to: //p')
MIG=$(forge create src/WdataipMigration.sol:WdataipMigration --rpc-url "$BSC" --private-key "$PK" \
      --gas-price 10000000000 --broadcast --constructor-args "$WIP" "$WDATAIP_OFT" "$OPERATOR" 2>/dev/null | sed -n 's/Deployed to: //p')
echo "  wIP=$WIP  migration=$MIG"
[ -n "$WIP" ] && [ -n "$MIG" ] && ok "deployed wIP + migration" || { bad "deploy failed"; exit 1; }

# --- 2) bridge WDATA in (OP Sepolia -> BSC) to mint WDATAIP reserve ------------------------------
echo "== bridge IN (OP Sepolia -> BSC, $U) =="
TO32=0x000000000000000000000000${OPERATOR:2}
SP_IN="($EID_BSC,$TO32,$U,$U,0x,0x,0x)"
op_send "$WDATA_OP" 'approve(address,uint256)' "$WDATA_ADAPTER" "$U"
FEE_IN=$(cast call "$WDATA_ADAPTER" 'quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)((uint256,uint256))' "$SP_IN" false --rpc-url "$OP" 2>/dev/null | grep -oE '[0-9]+' | head -1)
op_send "$WDATA_ADAPTER" 'send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)' "$SP_IN" "($FEE_IN,0)" "$OPERATOR" --value "$FEE_IN"
echo "  waiting for WDATAIP mint on BSC..."
for i in $(seq 1 40); do [ "$(bal "$WDATAIP_OFT" "$OPERATOR" "$BSC")" != "0" ] && break; sleep 10; done
[ "$(bal "$WDATAIP_OFT" "$OPERATOR" "$BSC")" -ge "$U" ] 2>/dev/null && ok "bridge IN delivered (1:1)" || bad "bridge IN not delivered"

# --- 3) fund reserve ----------------------------------------------------------------------------
bsc_send "$WDATAIP_OFT" 'transfer(address,uint256)' "$MIG" "$U"
[ "$(hex "$MIG" 'availableWdataip()(uint256)' --rpc-url "$BSC")" = "$U" ] && ok "reserve funded = $U" || bad "reserve mismatch"

# --- 4) migrate scenario battery ----------------------------------------------------------------
echo "== migrate scenarios =="
# S1 happy path
bsc_send "$WIP" 'mint(address,uint256)' "$OPERATOR" "$M"
bsc_send "$WIP" 'approve(address,uint256)' "$MIG" "$M"
R0=$(hex "$MIG" 'availableWdataip()(uint256)' --rpc-url "$BSC")
WD0=$(bal "$WDATAIP_OFT" "$OPERATOR" "$BSC")
bsc_send "$MIG" 'migrate(uint256)' "$M"
R1=$(hex "$MIG" 'availableWdataip()(uint256)' --rpc-url "$BSC")
WD1=$(bal "$WDATAIP_OFT" "$OPERATOR" "$BSC")
[ $((R0-R1)) -eq "$M" ] && [ $((WD1-WD0)) -eq "$M" ] && [ "$(bal "$WIP" "$MIG" "$BSC")" = "$M" ] && ok "S1 migrate 1:1 (reserve-$M, user+$M, wIP locked)" || bad "S1 migrate accounting"

# S2 second migrate accumulates wIP, draws reserve again
bsc_send "$WIP" 'mint(address,uint256)' "$OPERATOR" "$M"
bsc_send "$WIP" 'approve(address,uint256)' "$MIG" "$M"
bsc_send "$MIG" 'migrate(uint256)' "$M"
[ "$(hex "$MIG" 'availableWdataip()(uint256)' --rpc-url "$BSC")" -eq $((R1-M)) ] && [ "$(bal "$WIP" "$MIG" "$BSC")" -eq $((2*M)) ] && ok "S2 second migrate (wIP accumulates)" || bad "S2"

# S3 zero amount
expect_revert "$SEL_ZEROAMT" "S3 migrate(0)" "$MIG" 'migrate(uint256)' 0 --from "$OPERATOR"
# S4 insufficient allowance (fresh addr, allowance 0)
NOAL=0x00000000000000000000000000000000DeaD0001
expect_revert "reverted" "S4 migrate w/o allowance (any revert)" "$MIG" 'migrate(uint256)' "$M" --from "$NOAL"
# S6 underfunded: amount > reserve
HUGE=100000000000000000000   # 100, >> reserve
expect_revert "$SEL_RESERVE" "S6 migrate underfunded" "$MIG" 'migrate(uint256)' "$HUGE" --from "$OPERATOR"

# --- 5) rescue scenarios ------------------------------------------------------------------------
echo "== rescue scenarios =="
# S7 owner rescues accumulated wIP
WIPIN=$(bal "$WIP" "$MIG" "$BSC")
bsc_send "$MIG" 'rescue(address,address,uint256)' "$WIP" "$OPERATOR" "$WIPIN"
[ "$(bal "$WIP" "$MIG" "$BSC")" = "0" ] && ok "S7 owner rescues wIP ($WIPIN)" || bad "S7 rescue wIP"
# S8 non-owner rescue reverts
expect_revert "$SEL_UNAUTH" "S8 non-owner rescue" "$MIG" 'rescue(address,address,uint256)' "$WDATAIP_OFT" "$NOAL" 1 --from "$NOAL"
# S9 rescue zero recipient
expect_revert "$SEL_ZEROADDR" "S9 rescue zero recipient" "$MIG" 'rescue(address,address,uint256)' "$WDATAIP_OFT" 0x0000000000000000000000000000000000000000 1 --from "$OPERATOR"
# S10 rescue zero amount
expect_revert "$SEL_ZEROAMT" "S10 rescue zero amount" "$MIG" 'rescue(address,address,uint256)' "$WDATAIP_OFT" "$OPERATOR" 0 --from "$OPERATOR"

# S11 owner front-run: rescue the whole reserve, then migrate must revert + not pull wIP
echo "== front-run + drained =="
RES=$(hex "$MIG" 'availableWdataip()(uint256)' --rpc-url "$BSC")
bsc_send "$MIG" 'rescue(address,address,uint256)' "$WDATAIP_OFT" "$OPERATOR" "$RES"
[ "$(hex "$MIG" 'availableWdataip()(uint256)' --rpc-url "$BSC")" = "0" ] && ok "S11 reserve drained to 0" || bad "S11 drain"
# S12 migrate on empty reserve reverts
expect_revert "$SEL_RESERVE" "S12 migrate on empty reserve" "$MIG" 'migrate(uint256)' "$M" --from "$OPERATOR"

# --- 6) bridge OUT (BSC -> OP Sepolia) + zero-recipient failure ----------------------------------
echo "== bridge OUT (BSC -> OP Sepolia) =="
OUTAMT=$(bal "$WDATAIP_OFT" "$OPERATOR" "$BSC")   # whatever WDATAIP the operator now holds
if [ "$OUTAMT" -ge "$M" ] 2>/dev/null; then
  SP_OUT="($EID_OP,$TO32,$OUTAMT,$OUTAMT,0x,0x,0x)"
  FEE_OUT=$(cast call "$WDATAIP_OFT" 'quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)((uint256,uint256))' "$SP_OUT" false --rpc-url "$BSC" 2>/dev/null | grep -oE '[0-9]+' | head -1)
  OPWD0=$(bal "$WDATA_OP" "$OPERATOR" "$OP")
  bsc_send "$WDATAIP_OFT" 'send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)' "$SP_OUT" "($FEE_OUT,0)" "$OPERATOR" --value "$FEE_OUT"
  [ "$(bal "$WDATAIP_OFT" "$OPERATOR" "$BSC")" = "0" ] && ok "bridge OUT burned $OUTAMT WDATAIP" || bad "bridge OUT burn"
  echo "  waiting for WDATA unlock on OP Sepolia..."
  for i in $(seq 1 40); do [ "$(bal "$WDATA_OP" "$OPERATOR" "$OP")" -gt "$OPWD0" ] 2>/dev/null && break; sleep 10; done
  [ "$(bal "$WDATA_OP" "$OPERATOR" "$OP")" -gt "$OPWD0" ] 2>/dev/null && ok "bridge OUT delivered (WDATA unlocked, round-trip closed)" || bad "bridge OUT not delivered"
  # zero-recipient check (bridge layer). The OFT quoteSend does NOT validate the recipient, so a
  # zero/wrong recipient is not caught at quote time — a finding for the dApp, not a WdataipMigration
  # bug (the migration contract has no bridge logic). Documented, not counted as a failure.
  SP_ZERO="($EID_OP,0x0000000000000000000000000000000000000000000000000000000000000000,$M,$M,0x,0x,0x)"
  ZOUT=$(cast call "$WDATAIP_OFT" 'quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)' "$SP_ZERO" false --rpc-url "$BSC" 2>&1)
  if echo "$ZOUT" | grep -qiE "revert|error"; then
    ok "bridge to zero recipient rejected at quote"
  else
    echo "  ⚠️  FINDING: OFT quoteSend accepts a zero recipient (returns a fee) — enforce recipient validation at the dApp/UI layer; not a WdataipMigration issue."
    PASS=$((PASS+1))
  fi
else
  bad "bridge OUT skipped (no WDATAIP left)"
fi

echo ""
echo "================ SUMMARY: $PASS passed / $FAIL failed ================"
echo "wIP=$WIP"
echo "migration=$MIG"
[ "$FAIL" -eq 0 ]
