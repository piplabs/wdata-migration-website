#!/usr/bin/env bash
# Acquire wIP on BSC for the Phase 3 e2e by bridging WIP Story -> BSC over the canonical LayerZero
# OFT route (Story WIP OFTAdapter lock-box <-> BSC wIP OFT). Same shape as fund-mainnet.sh.
# Reproducible, env-driven, on-chain assertions, NO output suppression.
#
# Flow: wrap native DATA -> WIP (WETH9-style) up to WIP_IN -> approve adapter -> quoteSend ->
#       send (Story locks WIP, BSC mints wIP to operator) -> wait for BSC mint -> assert.
set -uo pipefail

STORY=${STORY_RPC:-https://mainnet.datarpc.io}
BSC=${BSC_RPC:-https://bsc-dataseed.bnbchain.org}
PK=${PRIVATE_KEY:?set PRIVATE_KEY (source .env)}
OP=${OPERATOR:-$(cast wallet address --private-key "$PK")}
WIP_STORY=${WIP_STORY:-0x1514000000000000000000000000000000000000}        # Story canonical WIP (WETH9-style)
WIP_ADAPTER=${WIP_ADAPTER:-0xa0a3D349e532d6F2D4ccFE2284Bb10288739698C}    # Story WIP OFTAdapter (lock-box)
WIP_BSC=${WIP_BSC:-0x4d6394bC3031F751EdcE368C189b0E060b527107}            # BSC wIP OFT
EID_BSC=30102
AMT=${WIP_IN:-5000000000000000}   # 0.005
# Story RPC times out on eth_estimateGas (-32002) -> explicit gas-limit + gas-price, skip estimation.
GP=$(cast gas-price --rpc-url "$STORY" 2>/dev/null); { [ -n "$GP" ] && [ "$GP" != "0" ]; } || GP=5000000000
GASLIM=${GASLIM:-1200000}

ok(){ echo "  OK   $1"; }
die(){ echo "  FAIL $1" >&2; exit 1; }
balof(){ cast call "$1" 'balanceOf(address)(uint256)' "$2" --rpc-url "$3" 2>/dev/null | awk '{print $1}'; }
story_send(){ local out
  out=$(cast send "$@" --rpc-url "$STORY" --private-key "$PK" --legacy --gas-limit "$GASLIM" --gas-price "$GP" --json 2>&1) \
    || die "story tx errored: $* :: $out"
  echo "$out" | jq -e '.status=="0x1"' >/dev/null 2>&1 || die "story tx reverted: $* :: $(echo "$out"|head -c 300)"
  echo "$out" | jq -r '"  tx="+.transactionHash+" gasUsed="+.gasUsed' 2>/dev/null; }

echo "operator=$OP  WIP_IN=$AMT"
echo "chainId story=$(cast chain-id --rpc-url $STORY)  bsc=$(cast chain-id --rpc-url $BSC)"

echo "== 1) ensure Story WIP balance >= WIP_IN (wrap native DATA) =="
WBAL=$(balof "$WIP_STORY" "$OP" "$STORY"); echo "  WIP bal now = $WBAL"
if [ "$WBAL" -lt "$AMT" ] 2>/dev/null; then
  NEED=$((AMT - WBAL)); echo "  depositing $NEED wei native -> WIP"
  story_send "$WIP_STORY" 'deposit()' --value "$NEED"; WBAL=$(balof "$WIP_STORY" "$OP" "$STORY")
fi
[ "$WBAL" -ge "$AMT" ] 2>/dev/null && ok "WIP bal = $WBAL" || die "WIP bal $WBAL < $AMT"

echo "== 2) approve adapter =="
story_send "$WIP_STORY" 'approve(address,uint256)' "$WIP_ADAPTER" "$AMT"
ALLOW=$(cast call "$WIP_STORY" 'allowance(address,address)(uint256)' "$OP" "$WIP_ADAPTER" --rpc-url "$STORY" | awk '{print $1}')
[ "$ALLOW" -ge "$AMT" ] 2>/dev/null && ok "allowance = $ALLOW" || die "allowance $ALLOW < $AMT"

echo "== 3) quoteSend Story->BSC =="
TO32=0x000000000000000000000000${OP#0x}
SP="($EID_BSC,$TO32,$AMT,$AMT,0x,0x,0x)"
FEE=$(cast call "$WIP_ADAPTER" 'quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)((uint256,uint256))' "$SP" false --rpc-url "$STORY" 2>&1 | grep -oE '[0-9]+' | head -1)
[ -n "$FEE" ] && ok "nativeFee = $FEE wei" || die "quoteSend returned no fee"

echo "== 4) send WIP Story -> BSC =="
W0=$(balof "$WIP_BSC" "$OP" "$BSC")
story_send "$WIP_ADAPTER" 'send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)' "$SP" "($FEE,0)" "$OP" --value "$FEE"
ok "WIP locked on Story; Story WIP bal now = $(balof "$WIP_STORY" "$OP" "$STORY")"

echo "== 5) wait for wIP mint on BSC (rise by $AMT) =="
TARGET=$((W0 + AMT))
for i in $(seq 1 60); do
  CUR=$(balof "$WIP_BSC" "$OP" "$BSC")
  [ "$CUR" -ge "$TARGET" ] 2>/dev/null && { ok "BSC wIP delivered: bal = $CUR"; break; }
  echo "  [$i] BSC wIP bal = $CUR (target $TARGET) ... waiting 15s"; sleep 15
done
CUR=$(balof "$WIP_BSC" "$OP" "$BSC")
[ "$CUR" -ge "$TARGET" ] 2>/dev/null && echo "================ wIP IN DONE: BSC wIP=$CUR ================" || die "wIP not delivered (bal=$CUR target=$TARGET)"
