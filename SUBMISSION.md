# DoraHacks Submission Package — Reactive Omni Buildathon

**Event:** https://dorahacks.io/hackathon/reactive-omni-buildathon
**Deadline:** 5 December 2026 (registration + BUIDL submission)
**Status:** Everything below is ready to paste. Fields marked `{{…}}` are filled from
`deployments.json` / `demo-results.json` after the on-chain run (`scripts/run_all.sh`).
The only steps that need a human at a browser: (1) claim Sepolia faucet ETH for the burner,
(2) DoraHacks registration + BUIDL submission itself.

---

## BUIDL form fields

**Project name**
```
Stop-Loss Sentinel
```

**Track**
```
Set It and Forget It
```

**Tagline / one-liner**
```
A stop-loss you set once: a reactive contract watches the price feed and exits your position
the moment your threshold breaks — no keeper, no server, no babysitting.
```

**Description (long)**
```
The problem: stop-losses only work if someone is awake to execute them. Exchange stop orders
are custodial and die with the exchange; keeper scripts are fragile — a laptop that sleeps,
a process that crashes, a wallet that runs dry, and your "protection" silently doesn't exist.

Stop-Loss Sentinel moves the watcher on-chain. You deposit a position into the GuardedVault,
set two numbers — a stop-loss and a take-profit — and walk away.

How it works (all on Reactive Lasna testnet, chain 5318007):
1. PriceFeed (origin) emits PriceUpdated(uint256) on every price move.
2. StopLossSentinel (reactive contract) subscribes to that event in its constructor. On every
   notification its react() records the price, checks — via a same-chain read — that the vault
   actually holds an open position, and if the price crossed a threshold it requests a
   callback via the system contract (requestCallbackV_1_0).
3. GuardedVault (destination) receives the callback through the Lasna callback proxy
   (the system contract, 0x8888888888888888888888888888888888888888). It authenticates both
   the proxy as caller and the sentinel as the payload's injected sender, then exits the
   position at the trigger price and pays the beneficiary in sUSD.

Safety properties: the sentinel latches after one trigger (it can never fire twice for one
position), it never pays for a callback when no position is open, the vault rejects callbacks
from any other caller or sender, and both contracts settle their Reactive fees from their own
balances via AbstractPayer with a public coverDebt().

Proof: the demo runs the full loop twice on-chain — a crash through the stop-loss and a rip
through the take-profit — with the complete transaction chain (origin event tx → reactive tx
→ callback tx) linked in the README. The same loop is replayed locally in an 8-test Foundry
suite against a mock system contract.

Why Reactive: this is the canonical reactive pattern — an event on one contract should cause
an action on another, reliably, without infrastructure. Reactive contracts turn "run a bot
forever" into "deploy once."
```

**GitHub repository**
```
https://github.com/Klowor2002/stop-loss-sentinel
```

**Demo video (< 3 min)**
```
{{VIDEO_URL}}
```
Upload target: YouTube (unlisted OK) or Loom. Shot-by-shot plan: `demo/DEMO-SCRIPT.md` in the repo.
Interim local proof video (logic loop): `demo/local-loop.mp4` in the repo — replace with the
on-chain recording before submitting.

**Deployed contracts (Lasna testnet, explorer https://lasna.reactscan.net)**

| Contract | Address | Deploy tx |
|---|---|---|
| TestToken (VOLT) | `{{VOLT_ADDRESS}}` | `{{VOLT_TX}}` |
| TestToken (sUSD) | `{{SUSD_ADDRESS}}` | `{{SUSD_TX}}` |
| PriceFeed | `{{FEED_ADDRESS}}` | `{{FEED_TX}}` |
| StopLossSentinel | `{{SENTINEL_ADDRESS}}` | `{{SENTINEL_TX}}` |
| GuardedVault | `{{VAULT_ADDRESS}}` | `{{VAULT_TX}}` |

**Demo evidence — full reactive loop (from `demo-results.json`)**

Act 1 (stop-loss): deposit `{{ACT1_DEPOSIT_TX}}` · origin crash tx `{{ACT1_ORIGIN_CRASH_TX}}` ·
reactive tx `{{ACT1_REACTIVE_TX}}` · callback tx `{{ACT1_CALLBACK_TX}}`
Act 2 (take-profit): origin moon tx `{{ACT2_ORIGIN_MOON_TX}}` · reactive tx `{{ACT2_REACTIVE_TX}}` ·
callback tx `{{ACT2_CALLBACK_TX}}`

**Team**
```
Solo builder — Klowor2002 (GitHub)
```

**Tags / keywords**
```
reactive contracts, stop-loss, take-profit, automation, defi, lasna, solidity, foundry
```

---

## Remaining steps (browser, in order)

1. **Fund the burner** (testnet-only wallet `0x165aB5E93dFF7E361E355D9D219c0996f1067eEE`):
   claim ≥ 0.05 Sepolia ETH from any Sepolia faucet that needs a browser (e.g. QuickNode
   faucet drip, Google Cloud faucet, or pk910 PoW faucet) and send it to the burner on
   **Ethereum Sepolia** (or claim on Base Sepolia and use that chain's faucet contract
   `0x2afaFD298b23b62760711756088F75B7409f5967` — `scripts/fund.sh` defaults to Ethereum Sepolia).
2. Run `scripts/run_all.sh` (fund swap → deploy → demo). It writes `deployments.json` and
   `demo-results.json`. Then replace every `{{…}}` in README.md and in this file.
3. Record the on-chain demo per `demo/DEMO-SCRIPT.md` (< 3 min), upload, set `{{VIDEO_URL}}`.
4. Commit + push the filled README; verify contracts on Reactscan if desired (Sourcify).
5. On DoraHacks: sign up / log in (GitHub), open the event page, **Register**, then
   **Submit BUIDL** and paste the fields above. Submit well before **5 Dec 2026**.
