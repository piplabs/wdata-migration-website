#!/usr/bin/env bash
# Read-only verification of the current mainnet state after the canary e2e. No keys, no writes.
# Prints each cast command + expected value + live result + OK/CHECK so it can be audited by hand.
set -uo pipefail

BSC=${BSC_RPC:-https://bsc-dataseed.bnbchain.org}
STORY=${STORY_RPC:-https://mainnet.datarpc.io}
MIG=0x093F607c32fCd57C2f008E47c8e16cccaE2cE0B8
OFT=0xA37EDed373c5cdF88644db7C6b89f222e756aFB2     # BSC WDATAIP OFT == Story WDATA adapter (create3)
WIP_BSC=0x4d6394bC3031F751EdcE368C189b0E060b527107
WDATA=0xD18a56346227f25D1410F98f78234305660bB877
SAFE=0x887AdcCdcA74486f450ea4603ED0c1Ea15a76288
OP=0x783A42CDB62cD126CcfC46AAdE5a0DDddCD010ec

# chk <label> <addr> <sig> <expect> <rpc> [arg]
chk(){ local label=$1 addr=$2 sig=$3 expect=$4 rpc=$5 arg=${6:-} cmd got st
  if [ -n "$arg" ]; then cmd="cast call $addr '$sig' $arg --rpc-url $rpc"; else cmd="cast call $addr '$sig' --rpc-url $rpc"; fi
  got=$(eval "$cmd" 2>&1 | awk '{print $1}' | tr -d '"')
  st=CHECK; [ "$(echo "$got"|tr 'A-Z' 'a-z')" = "$(echo "$expect"|tr 'A-Z' 'a-z')" ] && st=OK
  printf "%s\n  %s\n  expect= %s\n  got=    %s   [%s]\n\n" "$label" "$cmd" "$expect" "$got" "$st"
}

echo "########## BSC mainnet (chainId 56) ##########"; echo
chk "1. migration.owner() == BSC Safe"            "$MIG" 'owner()(address)'            "$SAFE"                "$BSC"
chk "2. migration.wip() == BSC wIP"               "$MIG" 'wip()(address)'              "$WIP_BSC"             "$BSC"
chk "3. migration.wdataip() == WDATAIP OFT"       "$MIG" 'wdataip()(address)'          "$OFT"                 "$BSC"
chk "4. migration.pendingOwner() == 0"            "$MIG" 'pendingOwner()(address)'     "0x0000000000000000000000000000000000000000" "$BSC"
chk "5. migration.availableWdataip() (reserve)"   "$MIG" 'availableWdataip()(uint256)' "9000000000000000"     "$BSC"
chk "6. wIP locked in migration (from migrate)"   "$WIP_BSC" 'balanceOf(address)(uint256)' "1000000000000000" "$BSC" "$MIG"
chk "7. WDATAIP totalSupply (after 0.001 burn)"   "$OFT" 'totalSupply()(uint256)'      "9000000000000000"     "$BSC"
chk "8. operator wIP left (0.005 in - 0.001)"     "$WIP_BSC" 'balanceOf(address)(uint256)' "4000000000000000" "$BSC" "$OP"
chk "9. operator WDATAIP (migrated then bridged)" "$OFT" 'balanceOf(address)(uint256)' "0"                    "$BSC" "$OP"
chk "10. Safe threshold"                          "$SAFE" 'getThreshold()(uint256)'    "3"                    "$BSC"

echo "########## Story / Data Network (chainId 1514) ##########"; echo
chk "11. WDATA locked in adapter (1:1 backing)"   "$WDATA" 'balanceOf(address)(uint256)' "9000000000000000"  "$STORY" "$OFT"
chk "12. operator WDATA (0.001 unlocked back)"    "$WDATA" 'balanceOf(address)(uint256)' "1000000000000000"  "$STORY" "$OP"

echo "########## 1:1 backing invariant ##########"
TS=$(cast call "$OFT" 'totalSupply()(uint256)' --rpc-url "$BSC" | awk '{print $1}')
LK=$(cast call "$WDATA" 'balanceOf(address)(uint256)' "$OFT" --rpc-url "$STORY" | awk '{print $1}')
echo "  WDATAIP totalSupply (BSC) = $TS"
echo "  WDATA locked in adapter (Story) = $LK"
[ "$TS" = "$LK" ] && echo "  [OK] totalSupply == locked  (1:1 backed)" || echo "  [CHECK] mismatch"
