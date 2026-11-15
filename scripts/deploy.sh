#!/usr/bin/env bash
# deploy.sh — deploy the SentinelVault system to Reactive Lasna testnet and wire it up.
# Writes deployments.json with every address and transaction hash.
set -euo pipefail
cd "$(dirname "$0")/.."

LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
SYSTEM="0x8888888888888888888888888888888888888888" # system contract AND Lasna callback proxy
export PATH="$HOME/.foundry/bin:$PATH"

PRIVATE_KEY="$(cat .burner-key)"
DEPLOYER="$(cast wallet address --private-key "$PRIVATE_KEY")"
echo "Deployer: $DEPLOYER"
BAL="$(cast balance "$DEPLOYER" --rpc-url "$LASNA_RPC")"
echo "Lasna balance (wei): $BAL"
[ "$BAL" = "0" ] && { echo "ERROR: burner has no lREACT — run scripts/fund.sh first."; exit 1; }

send() { # send <to> <sig> [args...] -> prints tx hash
  cast send "$@" --private-key "$PRIVATE_KEY" --rpc-url "$LASNA_RPC" --json | python3 -c "import sys,json;print(json.load(sys.stdin)['transactionHash'])"
}
create() { # create <src-path:Contract> <value-wei|0> [constructor args...] -> "address hash"
  local target="$1"; local value="$2"; shift 2
  forge create "$target" --rpc-url "$LASNA_RPC" --private-key "$PRIVATE_KEY" --value "$value" --broadcast --json --constructor-args "$@" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['deployedTo'], d['transactionHash'])"
}

echo "== Deploying TestToken VOLT =="
read VOLT VOLT_TX <<< "$(create src/TestToken.sol:TestToken 0 'Volatile Token' 'VOLT')"
echo "VOLT: $VOLT ($VOLT_TX)"

echo "== Deploying TestToken sUSD =="
read SUSD SUSD_TX <<< "$(create src/TestToken.sol:TestToken 0 'USD Test' 'sUSD')"
echo "sUSD: $SUSD ($SUSD_TX)"

echo "== Deploying PriceFeed (initial price \$300.00) =="
read FEED FEED_TX <<< "$(create src/PriceFeed.sol:PriceFeed 0 30000)"
echo "PriceFeed: $FEED ($FEED_TX)"

echo "== Deploying StopLossSentinel (stop \$250.00 / target \$400.00, funded 1 lREACT) =="
read SENTINEL SENTINEL_TX <<< "$(create src/StopLossSentinel.sol:StopLossSentinel 1000000000000000000 "$FEED" 25000 40000)"
echo "Sentinel: $SENTINEL ($SENTINEL_TX)"

echo "== Deploying GuardedVault (funded 0.5 lREACT) =="
read VAULT VAULT_TX <<< "$(create src/GuardedVault.sol:GuardedVault 500000000000000000 "$SYSTEM" "$SENTINEL" "$VOLT" "$SUSD")"
echo "Vault: $VAULT ($VAULT_TX)"

echo "== Wiring: sentinel.setVault =="
SETVAULT_TX="$(send "$SENTINEL" 'setVault(address)' "$VAULT")"
echo "setVault tx: $SETVAULT_TX"

echo "== Seeding: mint VOLT to deployer, sUSD settlement inventory to vault =="
MINT1_TX="$(send "$VOLT" 'mint(address,uint256)' "$DEPLOYER" 100ether)"
MINT2_TX="$(send "$SUSD" 'mint(address,uint256)' "$VAULT" 1000000ether)"
APPROVE_TX="$(send "$VOLT" 'approve(address,uint256)' "$VAULT" 100ether)"
echo "mint VOLT: $MINT1_TX | mint sUSD: $MINT2_TX | approve: $APPROVE_TX"

python3 - "$VOLT" "$VOLT_TX" "$SUSD" "$SUSD_TX" "$FEED" "$FEED_TX" "$SENTINEL" "$SENTINEL_TX" "$VAULT" "$VAULT_TX" "$SETVAULT_TX" "$DEPLOYER" <<'EOF'
import json, sys
keys = ["volt","volt_tx","susd","susd_tx","feed","feed_tx","sentinel","sentinel_tx","vault","vault_tx","setvault_tx","deployer"]
d = dict(zip(keys, sys.argv[1:]))
d.update({"chain": "Reactive Lasna testnet", "chainId": 5318007,
          "rpc": "https://lasna-rpc.rnk.dev/", "explorer": "https://lasna.reactscan.net",
          "system_contract": "0x8888888888888888888888888888888888888888",
          "stop_loss_price_cents": 25000, "take_profit_price_cents": 40000, "initial_price_cents": 30000})
json.dump(d, open("deployments.json", "w"), indent=2)
print(json.dumps(d, indent=2))
EOF
echo "Deployment complete — see deployments.json"
