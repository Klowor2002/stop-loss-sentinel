#!/usr/bin/env bash
# demo.sh — run the full on-chain demo on Lasna and collect the evidence chain:
#   origin tx (PriceFeed.setPrice) -> reactive tx (StopLossSentinel.react) -> callback tx (GuardedVault exit)
#
# Act 1: stop-loss. Act 2: take-profit. Results are appended to demo-results.json.
set -euo pipefail
cd "$(dirname "$0")/.."

LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
SYSTEM="0x8888888888888888888888888888888888888888"
EXPLORER_API="https://lasna.reactscan.net/api/v2"
export PATH="$HOME/.foundry/bin:$PATH"

PRIVATE_KEY="$(cat .burner-key)"
DEPLOYER="$(cast wallet address --private-key "$PRIVATE_KEY")"
VOLT="$(python3 -c "import json;print(json.load(open('deployments.json'))['volt'])")"
SUSD="$(python3 -c "import json;print(json.load(open('deployments.json'))['susd'])")"
FEED="$(python3 -c "import json;print(json.load(open('deployments.json'))['feed'])")"
SENTINEL="$(python3 -c "import json;print(json.load(open('deployments.json'))['sentinel'])")"
VAULT="$(python3 -c "import json;print(json.load(open('deployments.json'))['vault'])")"

send() { cast send "$@" --private-key "$PRIVATE_KEY" --rpc-url "$LASNA_RPC" --json | python3 -c "import sys,json;print(json.load(sys.stdin)['transactionHash'])"; }
call() { cast call "$@" --rpc-url "$LASNA_RPC"; }

wait_exit() { # wait_exit <expected exitCount>
  local want="$1"
  for i in $(seq 1 40); do
    local n; n="$(call "$VAULT" 'exitCount()(uint256)')"
    [ "$n" = "$want" ] && return 0
    sleep 5
  done
  echo "TIMEOUT waiting for exitCount=$want"; return 1
}

find_loop_txs() { # find_loop_txs <method-name> -> prints "reactive_tx callback_tx" (best effort via Reactscan)
  python3 - "$EXPLORER_API" "$SENTINEL" "$VAULT" "$SYSTEM" "$1" <<'EOF'
import json, sys, urllib.request
api, sentinel, vault, system, method = sys.argv[1:6]
def get(url):
    req = urllib.request.Request(url, headers={"accept": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)
reactive_tx = ""
try:
    d = get(f"{api}/addresses/{sentinel}/transactions?page_size=50")
    for it in d.get("items", []):
        if (it.get("from") or {}).get("hash", "").lower() == system.lower():
            reactive_tx = it["hash"]; break
except Exception:
    pass
callback_tx = ""
try:
    d = get(f"{api}/addresses/{vault}/transactions?page_size=50")
    for it in d.get("items", []):
        if it.get("method") == method:
            callback_tx = it["hash"]; break
except Exception:
    pass
print(reactive_tx, callback_tx)
EOF
}

echo "######## ACT 1 — STOP-LOSS ########"
echo "Opening position: deposit 10 VOLT into the GuardedVault"
DEPOSIT_TX="$(send "$VAULT" 'deposit(uint256)' 10ether)"
echo "deposit tx: $DEPOSIT_TX"

echo "Price \$300 -> \$290 (inside the band — sentinel observes, no trigger)"
ORIGIN0_TX="$(send "$FEED" 'setPrice(uint256)' 29000)"
sleep 15
echo "observations: $(call "$SENTINEL" 'observations()(uint256)') | positionActive: $(call "$VAULT" 'positionActive()(bool)')"

echo "Price \$290 -> \$240 (crashes through the \$250 stop-loss — no human involved from here)"
ORIGIN1_TX="$(send "$FEED" 'setPrice(uint256)' 24000)"
echo "origin tx: $ORIGIN1_TX"
wait_exit 1
read REACTIVE1_TX CALLBACK1_TX <<< "$(find_loop_txs executeStopLoss)"
echo "reactive tx: ${REACTIVE1_TX:-<see Reactscan>} | callback tx: ${CALLBACK1_TX:-<see Reactscan>}"
echo "vault: positionActive=$(call "$VAULT" 'positionActive()(bool)') lastExitReason=$(call "$VAULT" 'lastExitReason()(uint8)') (1=StopLoss) lastExitPrice=$(call "$VAULT" 'lastExitPrice()(uint256)')"
echo "beneficiary sUSD balance: $(call "$SUSD" 'balanceOf(address)(uint256)' "$DEPLOYER")"

echo "######## ACT 2 — TAKE-PROFIT ########"
DEPOSIT2_TX="$(send "$VAULT" 'deposit(uint256)' 10ether)"
REARM_TX="$(send "$SENTINEL" 'rearm()')"
echo "re-deposit tx: $DEPOSIT2_TX | rearm tx: $REARM_TX"
ORIGIN2_TX="$(send "$FEED" 'setPrice(uint256)' 30000)"
sleep 15
echo "Price \$300 -> \$450 (rips through the \$400 take-profit)"
ORIGIN3_TX="$(send "$FEED" 'setPrice(uint256)' 45000)"
echo "origin tx: $ORIGIN3_TX"
wait_exit 2
read REACTIVE2_TX CALLBACK2_TX <<< "$(find_loop_txs executeTakeProfit)"
echo "reactive tx: ${REACTIVE2_TX:-<see Reactscan>} | callback tx: ${CALLBACK2_TX:-<see Reactscan>}"
echo "vault: lastExitReason=$(call "$VAULT" 'lastExitReason()(uint8)') (2=TakeProfit) lastExitPrice=$(call "$VAULT" 'lastExitPrice()(uint256)') exitCount=$(call "$VAULT" 'exitCount()(uint256)')"
echo "beneficiary sUSD balance: $(call "$SUSD" 'balanceOf(address)(uint256)' "$DEPLOYER")"

python3 - "$DEPOSIT_TX" "$ORIGIN0_TX" "$ORIGIN1_TX" "$REACTIVE1_TX" "$CALLBACK1_TX" "$DEPOSIT2_TX" "$REARM_TX" "$ORIGIN2_TX" "$ORIGIN3_TX" "$REACTIVE2_TX" "$CALLBACK2_TX" <<'EOF'
import json, sys
names = ["act1_deposit_tx","act1_origin_inband_tx","act1_origin_crash_tx","act1_reactive_tx","act1_callback_tx",
         "act2_deposit_tx","act2_rearm_tx","act2_origin_reset_tx","act2_origin_moon_tx","act2_reactive_tx","act2_callback_tx"]
json.dump(dict(zip(names, sys.argv[1:])), open("demo-results.json", "w"), indent=2)
print("Wrote demo-results.json")
EOF
echo "DEMO COMPLETE"
