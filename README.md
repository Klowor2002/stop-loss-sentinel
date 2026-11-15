# Stop-Loss Sentinel — "Set It and Forget It" Portfolio Protection on Reactive Network

**Track:** Reactive Omni Buildathon — *Set It and Forget It*
**Network:** Reactive Lasna testnet (chain ID 5318007) · **Stack:** Solidity 0.8.29, Foundry, reactive-lib-omni

A stop-loss you don't have to watch. You deposit a position, set two numbers — a stop-loss and a
take-profit — and walk away. A **reactive contract** subscribed to the price feed watches the
market for you, and the moment the price crosses either threshold it triggers a callback that
exits the position. No keeper bot, no cron job, no server, no "please check the dashboard."
The network itself is the watchdog.

---

## The problem

Every retail trader knows the ritual: set a mental stop-loss, then fail to execute it because
they were asleep, at work, or staring at the chart hoping for a bounce. The usual fixes are
centralized (an exchange's stop order — custodial, and it dies with the exchange) or fragile
(a keeper script on a laptop that must stay online, funded, and un-crashed 24/7).

Reactive contracts remove the watcher entirely. The trigger logic lives on-chain, is executed
by the Reactive Network the moment the event happens, and pays for itself out of a small
pre-funded balance. Set it, fund it, forget it.

## How it works

```
 PriceFeed                StopLossSentinel                 GuardedVault
 (origin, Lasna)          (reactive, Lasna)                (destination, Lasna)
 ───────────────          ────────────────────             ────────────────────
 setPrice(240_00)         react(LogRecord)                 executeStopLoss(…)
      │  emits                  │  price ≤ stop?                 │  sells position
      │  PriceUpdated           │  position open?                │  → sUSD to owner
      └────────────────────────►│                                ▲
                                │  requestCallbackV_1_0        │
                                └────────────────────────────────┘
                                     via system contract
                                  0x8888…8888 (Lasna proxy)
```

1. **Origin — `PriceFeed`** emits `PriceUpdated(uint256)` on every price move. In production
   this role belongs to an exchange or oracle contract; here the feed is owner-driven so the
   demo can move the market on demand. The sentinel doesn't care who writes the price — it
   reacts to the event, which is the entire point of the pattern.
2. **Reactive — `StopLossSentinel`** subscribes in its constructor to the feed's
   `PriceUpdated` topic on Lasna. Every notification runs `react()` (system-contract only):
   it records the price, checks — via a same-chain read — that the vault actually holds an
   open position, and if the price crossed a threshold it latches and requests a callback
   (`requestCallbackV_1_0`) to the vault. The position check matters: callbacks are billed,
   so the sentinel never pays to exit a position that doesn't exist.
3. **Destination — `GuardedVault`** holds the position (10 VOLT in the demo). Its
   `executeStopLoss` / `executeTakeProfit` functions can only be called by the callback proxy,
   and the proxy overwrites the payload's first argument with the sentinel's address, which
   the vault verifies (`onlyCallbackSender`). On a valid callback the vault exits the whole
   position at the trigger price and pays the beneficiary in sUSD.

**Safety properties**

- `react()` never reverts on foreign logs — mismatched notifications return silently.
- The sentinel **latches** after one trigger: it cannot fire twice for the same position.
  Re-arming is an explicit owner action after a new deposit.
- The vault rejects callbacks from any caller that isn't the proxy, and any sender that
  isn't the sentinel (both cases covered by unit tests).
- Both contracts settle their Reactive fees from their own balances via the standard
  `AbstractPayer.pay()` flow, and expose `coverDebt()`.

## Deployed contracts (Lasna testnet)

> Filled in by `scripts/deploy.sh` — see `deployments.json` in this repo for the
> machine-readable record, and the "Demo evidence" section below for the full loop.

| Contract | Address | Deploy tx |
|---|---|---|
| TestToken (VOLT) | `{{VOLT_ADDRESS}}` | `{{VOLT_TX}}` |
| TestToken (sUSD) | `{{SUSD_ADDRESS}}` | `{{SUSD_TX}}` |
| PriceFeed | `{{FEED_ADDRESS}}` | `{{FEED_TX}}` |
| StopLossSentinel | `{{SENTINEL_ADDRESS}}` | `{{SENTINEL_TX}}` |
| GuardedVault | `{{VAULT_ADDRESS}}` | `{{VAULT_TX}}` |

Parameters: initial price **$300.00** · stop-loss **$250.00** · take-profit **$400.00** ·
position **10 VOLT**. Explorer: https://lasna.reactscan.net

## Demo evidence — the full loop, on-chain

**Act 1 — stop-loss.** Deposit 10 VOLT → price moves $300 → $290 (observed, no trigger) →
price crashes to $240 → the sentinel fires → the vault exits at $240 and pays out 2,400 sUSD.

| Step | Transaction |
|---|---|
| Deposit | `{{ACT1_DEPOSIT_TX}}` |
| Origin event ($290, in-band) | `{{ACT1_ORIGIN_INBAND_TX}}` |
| Origin event ($240, crash) | `{{ACT1_ORIGIN_CRASH_TX}}` |
| Reactive tx (`react()`) | `{{ACT1_REACTIVE_TX}}` |
| Callback tx (`executeStopLoss`) | `{{ACT1_CALLBACK_TX}}` |

**Act 2 — take-profit.** Re-deposit, re-arm → price rips to $450 → the vault exits at the
target and pays out 4,500 sUSD.

| Step | Transaction |
|---|---|
| Re-deposit / re-arm | `{{ACT2_DEPOSIT_TX}}` / `{{ACT2_REARM_TX}}` |
| Origin event ($450) | `{{ACT2_ORIGIN_MOON_TX}}` |
| Reactive tx (`react()`) | `{{ACT2_REACTIVE_TX}}` |
| Callback tx (`executeTakeProfit`) | `{{ACT2_CALLBACK_TX}}` |

🎬 **Demo video (< 3 min):** {{VIDEO_URL}} — shot-by-shot plan in `demo/DEMO-SCRIPT.md`.

## Run it yourself

```bash
# 1. Build & test (the test suite replays the whole loop against a mock system contract)
forge build
forge test

# 2. Fund a testnet-only burner with lREACT:
#    send Sepolia ETH (Ethereum Sepolia) to the Reactive faucet contract
#    0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 — 1 ETH → 100 lREACT, credited to the
#    same address on Lasna. Or just run:
./scripts/fund.sh            # assumes the burner already holds Sepolia ETH

# 3. Deploy, wire, seed (writes deployments.json)
./scripts/deploy.sh

# 4. Run both demo acts and collect the evidence chain (writes demo-results.json)
./scripts/demo.sh
```

## Design notes & honest limitations

- **Origin = destination = Lasna.** Keeping the whole loop on one chain makes the demo
  self-contained and lets `react()` read the vault's state directly. Nothing in the design
  depends on it: point the subscription at a Sepolia feed and the callback at a Sepolia
  vault and the same contracts work cross-chain.
- **Settlement is simulated.** The vault pays out from a pre-funded sUSD inventory instead
  of routing a sell order to a DEX — Lasna has no liquid VOLT market to sell into. The
  reactive trigger, authentication, and accounting are exactly what a production
  integration would use; only the venue leg is stubbed.
- **The feed is owner-driven** so the demo can move the market on demand. Subscribing to a
  real oracle/exchange event source is a constructor argument, not a code change.

## Layout

```
src/    PriceFeed · StopLossSentinel · GuardedVault · TestToken
test/   SentinelVault.t.sol — 8 tests incl. full stop-loss & take-profit loop replays
scripts/ fund.sh · deploy.sh · demo.sh · run_all.sh
demo/   DEMO-SCRIPT.md — shot-by-shot video plan
```

Built for the Reactive Omni Buildathon (DoraHacks), *Set It and Forget It* track.
Testnet only — no real funds were used or harmed.
