#!/usr/bin/env bash
# act2_continue.sh — run Act 2 (take-profit) after Act 1's callback has landed,
# recovering the reactive + callback tx hashes from on-chain evidence:
#   reactive tx  <- sentinel's Triggered event log (transactionHash)
#   callback tx  <- system contract getCallbacks(reactive_tx) destination hash
# Writes act2-results.json. Act 1 hashes are collected separately into demo-results.json.
set -euo pipefail
cd "$(dirname "$0")/.."

LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
SYSTEM="0x8888888888888888888888888888888888888888"
export PATH="$HOME/.foundry/bin:$PATH"

PRIVATE_KEY="$(cat .burner-key)"
DEPLOYER="$(cast wallet address --private-key "$PRIVATE_KEY")"
SUSD="$(python3 -c "import json;print(json.load(open('deployments.json'))['susd'])")"
FEED="$(python3 -c "import json;print(json.load(open('deployments.json'))['feed'])")"
SENTINEL="$(python3 -c "import json;print(json.load(open('deployments.json'))['sentinel'])")"
VAULT="$(python3 -c "import json;print(json.load(open('deployments.json'))['vault'])")"

send() { cast send "$@" --private-key "$PRIVATE_KEY" --rpc-url "$LASNA_RPC" --json | python3 -c "import sys,json;print(json.load(sys.stdin)['transactionHash'])"; }
call() { cast call "$@" --rpc-url "$LASNA_RPC"; }

wait_exit() { # wait_exit <expected exitCount> <max-seconds>
  local want="$1" max="$2" waited=0 n
  while [ "$waited" -lt "$max" ]; do
    n="$(call "$VAULT" 'exitCount()(uint256)')"
    [ "$n" = "$want" ] && return 0
    sleep 20; waited=$((waited + 20))
  done
  echo "TIMEOUT waiting for exitCount=$want after ${max}s"; return 1
}

loop_txs() { # loop_txs <kind: 1=stop-loss 2=take-profit> -> "reactive_tx callback_tx"
  python3 - "$LASNA_RPC" "$SENTINEL" "$SYSTEM" "$1" "$VAULT" <<'EOF'
import json, subprocess, sys
import requests
rpc_url, sentinel, system, kind, vault = sys.argv[1:6]
CAST = "/home/hatch/.foundry/bin/cast"
def rpc(method, params):
    r = requests.post(rpc_url, json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params}, timeout=30)
    return r.json()["result"]
def keccak(sig):
    return subprocess.run([CAST, "keccak", sig], capture_output=True, text=True).stdout.strip()
topic = keccak("Triggered(uint256,uint256)")
latest = int(rpc("eth_blockNumber", []), 16)
reactive_tx = ""
for start in range(latest, latest - 29000 * 4, -29000):
    logs = rpc("eth_getLogs", [{"fromBlock": hex(max(0, start - 28999)), "toBlock": hex(start),
                                "address": sentinel, "topics": [topic]}])
    for l in logs:
        data = l["data"][2:]
        k = int(data[0:64], 16)
        if k == int(kind):
            reactive_tx = l["transactionHash"]  # keep the latest matching one
    if reactive_tx:
        break
callback_tx = ""
if reactive_tx:
    out = subprocess.run([CAST, "call", system,
                          "getCallbacks(uint256)((uint256,address,uint256,uint256,uint256,bytes)[])",
                          reactive_tx, "--rpc-url", rpc_url], capture_output=True, text=True).stdout
    # cast prints tuples like (8407695, 0xSentinel, 0, 5318007, 12345678901234567890, 0x)
    # the 5th field is the destination tx hash as uint256 -> hex
    import re
    m = re.search(r"\((\d+),\s*(0x[0-9a-fA-F]{40}),\s*(\d+),\s*(\d+),\s*(\d+),\s*0x", out)
    if m:
        callback_tx = "0x%064x" % int(m.group(5))
if not callback_tx:
    # Fallback: the delivery tx is the one that emitted the vault's Exited event
    # for this exit kind (reason is the first data word).
    etopic = keccak("Exited(uint8,uint256,uint256,uint256)")
    for start in range(latest, latest - 29000 * 4, -29000):
        logs = rpc("eth_getLogs", [{"fromBlock": hex(max(0, start - 28999)), "toBlock": hex(start),
                                    "address": vault, "topics": [etopic]}])
        for l in logs:
            if int(l["data"][2:66], 16) == int(kind):
                callback_tx = l["transactionHash"]
        if callback_tx:
            break
print(reactive_tx, callback_tx)
EOF
}

echo "######## ACT 2 — TAKE-PROFIT (continuation) ########"
echo "Precondition check: exitCount must be 1, sentinel latched"
echo "exitCount: $(call "$VAULT" 'exitCount()(uint256)') | latched: $(call "$SENTINEL" 'latched()(bool)')"

DEPOSIT2_TX="$(send "$VAULT" 'deposit(uint256)' 10ether)"
REARM_TX="$(send "$SENTINEL" 'rearm()')"
echo "re-deposit tx: $DEPOSIT2_TX | rearm tx: $REARM_TX"
ORIGIN2_TX="$(send "$FEED" 'setPrice(uint256)' 30000)"
echo "origin reset tx (\$300): $ORIGIN2_TX"
sleep 15
echo "Price \$300 -> \$450 (rips through the \$400 take-profit)"
ORIGIN3_TX="$(send "$FEED" 'setPrice(uint256)' 45000)"
echo "origin tx: $ORIGIN3_TX"
wait_exit 2 5400 || echo "WARN: exit wait timed out — collecting on-chain state anyway"
read REACTIVE2_TX CALLBACK2_TX <<< "$(loop_txs 2)"
echo "reactive tx: ${REACTIVE2_TX:-<not found>} | callback tx: ${CALLBACK2_TX:-<not recorded yet>}"
echo "vault: lastExitReason=$(call "$VAULT" 'lastExitReason()(uint8)') (2=TakeProfit) lastExitPrice=$(call "$VAULT" 'lastExitPrice()(uint256)') lastExitStableOut=$(call "$VAULT" 'lastExitStableOut()(uint256)') exitCount=$(call "$VAULT" 'exitCount()(uint256)')"
echo "beneficiary sUSD balance: $(call "$SUSD" 'balanceOf(address)(uint256)' "$DEPLOYER")"

python3 - "$DEPOSIT2_TX" "$REARM_TX" "$ORIGIN2_TX" "$ORIGIN3_TX" "$REACTIVE2_TX" "$CALLBACK2_TX" <<'EOF'
import json, sys
names = ["act2_deposit_tx", "act2_rearm_tx", "act2_origin_reset_tx", "act2_origin_moon_tx", "act2_reactive_tx", "act2_callback_tx"]
json.dump(dict(zip(names, sys.argv[1:])), open("act2-results.json", "w"), indent=2)
print("Wrote act2-results.json")
EOF
echo "ACT 2 COMPLETE"
