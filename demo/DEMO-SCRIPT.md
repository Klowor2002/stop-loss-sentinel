# Demo video — shot-by-shot script (target: 2 min 30 s, hard cap 3 min)

**Format:** screen recording, two panels — terminal (left) and Lasna Reactscan (right).
Narration can be voice-over or captions; captions are safer. Every shot below maps to a real
command in `scripts/demo.sh` or a real explorer page — nothing is staged.

| # | Time | Visual | Caption / narration |
|---|---|---|---|
| 1 | 0:00–0:15 | README top + architecture diagram (repo page) | "Stop-Loss Sentinel. A stop-loss you set once — a reactive contract watches the market and exits your position for you. No keeper, no server." |
| 2 | 0:15–0:35 | Terminal: `forge test` output, 8 passed | "The logic is unit-tested locally, including a full replay of the stop-loss and take-profit loops against a mock system contract." |
| 3 | 0:35–0:55 | Reactscan: the five contracts from `deployments.json`; open the Sentinel's page, show *Reactive* status = active | "Deployed on Lasna testnet: a price feed, the reactive sentinel, and the guarded vault it protects." |
| 4 | 0:55–1:15 | Terminal: `demo.sh` Act 1 start — deposit tx; vault page shows position open, 10 VOLT | "We deposit 10 VOLT. Stop-loss $250, take-profit $400, price starts at $300." |
| 5 | 1:15–1:35 | Terminal: `setPrice(290)`; sentinel page refreshes — an `Observed` reactive tx, position still open | "Price dips to $290 — inside the band. The sentinel sees it… and does nothing. Exactly as designed." |
| 6 | 1:35–2:05 | Terminal: `setPrice(240)`; wait; vault page refreshes — position closed, `Exited(StopLoss, 240)`; beneficiary sUSD balance 2,400 | "Price crashes to $240. Nobody clicks anything. The sentinel fires, the callback lands, the vault exits at $240 and pays out 2,400 sUSD." |
| 7 | 2:05–2:25 | Reactscan: open the three transactions side by side — origin `setPrice`, reactive `react()`, callback `executeStopLoss` | "The full evidence chain on-chain: origin event → reactive execution → callback. Three transactions, zero humans." |
| 8 | 2:25–2:45 | Terminal: Act 2 — re-deposit, re-arm, `setPrice(450)`; vault shows `Exited(TakeProfit, 450)`, +4,500 sUSD | "Same sentinel, other direction: re-armed, price rips to $450, take-profit exits automatically." |
| 9 | 2:45–2:55 | README architecture diagram again | "Set it, fund it, forget it. Stop-Loss Sentinel — built on Reactive Network." |

## Recording checklist

- [ ] Run `scripts/run_all.sh` once end-to-end first (fund → deploy → demo) so every hash exists.
- [ ] Browser tabs pre-opened: repo README, Reactscan pages for Sentinel + Vault (from `deployments.json`).
- [ ] Terminal font large; run `./scripts/demo.sh` live for shots 4–8 (it prints every hash).
- [ ] Keep total runtime under 3:00 — the two on-chain waits (~15 s each) can be sped up 2× in edit.
- [ ] Upload to YouTube (unlisted is fine) or Loom; put the link in the DoraHacks BUIDL page
      and replace `{{VIDEO_URL}}` in README.md / SUBMISSION.md.

## Fallback (no on-chain footage yet)

`demo/local-loop.cast` — an asciinema recording of the local full-loop test suite
(`forge test -vvv`) — proves the logic end-to-end against the mock system contract.
Convert to video with: `agg demo/local-loop.cast demo/local-loop.gif`
