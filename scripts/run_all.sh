#!/usr/bin/env bash
# run_all.sh — fund (if needed) -> deploy -> demo, end to end on Lasna testnet.
set -euo pipefail
cd "$(dirname "$0")/.."
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
export PATH="$HOME/.foundry/bin:$PATH"

ADDR="$(cat burner-address.txt)"
BAL="$(cast balance "$ADDR" --rpc-url "$LASNA_RPC")"
echo "Burner $ADDR Lasna balance: $BAL wei"
if [ "$BAL" = "0" ]; then
  echo "No lREACT yet — running fund.sh (requires Sepolia ETH on the burner)..."
  ./scripts/fund.sh
fi
./scripts/deploy.sh
./scripts/demo.sh
echo "ALL DONE — see deployments.json + demo-results.json"
