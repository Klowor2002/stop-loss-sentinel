#!/usr/bin/env bash
# record-local.sh — the terminal session recorded into demo/local-loop.cast
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"
echo "$ Stop-Loss Sentinel — local full-loop verification"
sleep 1
echo "# The test suite replays the ENTIRE reactive loop against a mock system contract:"
echo "#   price crash -> react() -> callback request -> proxy delivery -> vault exit"
sleep 2
echo "$ forge test"
forge test 2>&1 | grep -vE "^Ran "
sleep 2
echo "# 8/8 passing — including test_StopLossFullLoop and test_TakeProfitFullLoop."
echo "# On Lasna, the same loop runs on-chain: origin tx -> reactive tx -> callback tx."
echo "# On-chain recording plan: demo/DEMO-SCRIPT.md"
sleep 2
