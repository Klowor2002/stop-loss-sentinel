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
PENDING — to be recorded once the Lasna callback lands; finalized shot list in demo/SHOT-LIST.md
```
Upload target: YouTube (unlisted OK) or Loom. Shot-by-shot plan: `demo/DEMO-SCRIPT.md` in the repo.
Interim local proof video (logic loop): `demo/local-loop.mp4` in the repo — replace with the
on-chain recording before submitting.

**Deployed contracts (Lasna testnet, explorer https://lasna.reactscan.net)**

| Contract | Address | Deploy tx |
|---|---|---|
| TestToken (VOLT) | `0x81Bde1cf4a6BB14dF743eAaa2FD085E538039946` | `0x2e684e867dd260a40670147604a97b83797e07df40d11daf0bb1e9c34393e57a` |
| TestToken (sUSD) | `0xa01Bbc41112B66b8ce2a894e8f25d240e4465d91` | `0x49abfff27091961a7fb06e668305c96950aad85b94525cc411dcebdbcacef01a` |
| PriceFeed | `0xf7a896373AE8b26AEA2fAe0Db19c24329F28b846` | `0x8247c5147c9c0a530274a74298b275539be4e54876f2f307f8d1cb5563ea1832` |
| StopLossSentinel | `0xB657F69DD996FED0e4ccABCD2f994415d80d035e` | `0xe05a2a29712e9eca076e978673d701c98b89dc0abba84349565654d25c62cf07` |
| GuardedVault | `0xE0ab06984d3c4e506128658BC07ae899F06EcBBd` | `0x9bf7e1703bd73fd2442e3963c6e03a09838ba45ddc8c68803f7c1ec75012077c` |

**Demo evidence — full reactive loop (from `demo-results.json`)**

Act 1 (stop-loss): deposit `0xb1e5979bccaabc229cfca953675b271448c5851ec5cb517df75f03728d6af614` · origin crash tx `0x3b0b7e814779747f1afceed08287e4c61d0d1315b1b134b8d3c04456d23bffa1` ·
reactive tx `0xa49c86e87a06c9e9bef1ca4caf13216a8cf87280a3eefca3fee1a2f0979828d2` · callback tx `pending — awaiting Lasna callback delivery (network-side; see demo-results.json)`
Act 2 (take-profit): origin moon tx `pending — Act 2 not yet run` · reactive tx `pending — Act 2 not yet run` ·
callback tx `pending — awaiting Lasna callback delivery (network-side; see demo-results.json)`

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
3. Record the on-chain demo per `demo/DEMO-SCRIPT.md` (< 3 min), upload, set `PENDING — to be recorded once the Lasna callback lands; finalized shot list in demo/SHOT-LIST.md`.
4. Commit + push the filled README; verify contracts on Reactscan if desired (Sourcify).
5. On DoraHacks: sign up / log in (GitHub), open the event page, **Register**, then
   **Submit BUIDL** and paste the fields above. Submit well before **5 Dec 2026**.
