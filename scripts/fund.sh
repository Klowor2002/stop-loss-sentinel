#!/usr/bin/env bash
# fund.sh — swap Sepolia ETH for Lasna testnet REACT via the official Reactive faucet contract.
#
# Prerequisite: the burner wallet (./.burner-key) must already hold Sepolia ETH on
# Ethereum Sepolia (from any public Sepolia faucet). This script sends AMOUNT_ETH of it to the
# faucet contract; the same address is credited AMOUNT_ETH * 100 lREACT on Lasna.
#
# Usage: AMOUNT_ETH=0.05 ./scripts/fund.sh
set -euo pipefail
cd "$(dirname "$0")/.."

AMOUNT_ETH="${AMOUNT_ETH:-0.05}"
SEPOLIA_RPC="${SEPOLIA_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
FAUCET="0x9b9BB25f1A81078C544C829c5EB7822d747Cf434" # Reactive faucet, Ethereum Sepolia
export PATH="$HOME/.foundry/bin:$PATH"

PRIVATE_KEY="$(cat .burner-key)"
ADDR="$(cast wallet address --private-key "$PRIVATE_KEY")"
echo "Burner: $ADDR"

BAL="$(cast balance "$ADDR" --rpc-url "$SEPOLIA_RPC")"
echo "Sepolia ETH balance (wei): $BAL"
echo "Sending $AMOUNT_ETH Sepolia ETH to the Reactive faucet contract $FAUCET ..."
cast send "$FAUCET" --value "${AMOUNT_ETH}ether" --private-key "$PRIVATE_KEY" --rpc-url "$SEPOLIA_RPC"

echo "Waiting for the lREACT credit on Lasna..."
for i in $(seq 1 30); do
  LB="$(cast balance "$ADDR" --rpc-url "$LASNA_RPC")"
  echo "  Lasna balance (wei): $LB"
  [ "$LB" != "0" ] && break
  sleep 10
done
echo "Done. Lasna balance: $(cast balance "$ADDR" --rpc-url "$LASNA_RPC") wei"
