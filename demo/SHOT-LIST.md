# Demo video — finalized shot list (plan B: terminal recording)

Status: READY TO FILM the moment the Act-1 callback lands on Lasna and Act 2 completes.
The Reactscan two-panel plan in `DEMO-SCRIPT.md` is not filmable headlessly (the explorer is a
JS app), so the video is a terminal recording (asciinema → agg → mp4) of live `cast` evidence
commands, with title cards between acts. Tooling verified on this machine: asciinema, agg, ffmpeg.

Target length: < 3 min. Narration: captions only (no voiceover needed).

## Shots

1. **Title card (5 s)** — "Stop-Loss Sentinel — a reactive stop-loss that fires itself.
   Reactive Network Omni Buildathon · Lasna testnet (chainId 5318007)."
2. **The contracts (20 s)** — terminal: `cat deployments.json`; `cast call` the sentinel's
   stop/target/initial price cents (25000 / 40000 / 30000) and the vault address it guards.
3. **Act 1 — the position (20 s)** — show the Act-1 deposit tx hash + `cast call` vault
   `position()(uint256)` = 10 VOLT, `positionActive()` = true (pre-crash state from the
   recorded run; hashes in `demo-results.json`).
4. **Act 1 — the crash (30 s)** — show origin txs: in-band $290 (no trigger — sentinel
   `observations()` = 1, `latched()` = false), then crash $240 origin tx → reactive tx
   `0xa49c…` receipt: `Observed(24000)` + `Triggered(1, 24000)` logs; sentinel `latched()` = true.
   Caption: "No keeper, no bot, no server — the contract reacted on its own."
5. **Act 1 — the exit (30 s)** — the callback tx (delivery via Lasna callback proxy
   0x8888…8888): vault `exitCount()` = 1, `lastExitReason()` = 1 (StopLoss),
   `lastExitPrice()` = 24000, `lastExitStableOut()` = 2400 sUSD; beneficiary sUSD balance
   before/after (+2,400). Show the `Exited` event in the callback tx receipt.
6. **Act 2 — take-profit (45 s)** — re-deposit + rearm txs, origin $300 (in band), origin
   $450 → reactive tx with `Triggered(2, 45000)` → callback tx: `exitCount()` = 2,
   `lastExitReason()` = 2 (TakeProfit), `lastExitStableOut()` = 4500 sUSD; beneficiary
   total 6,900 sUSD.
7. **Closing card (10 s)** — "Set it and forget it: the exit is a protocol guarantee,
   not a promise from a server." + repo URL + Lasna explorer links for every tx above.

## Recording commands

```bash
asciinema rec demo.cast -c "bash demo/film.sh"   # film.sh runs the cast evidence commands with pauses
agg demo.cast demo.gif
ffmpeg -i demo.gif -movflags faststart -pix_fmt yuv420p demo.mp4
```

Upload to YouTube (unlisted) or Loom, then set the URL in README.md / SUBMISSION.md
(the two `VIDEO` spots) and in the DoraHacks BUIDL.
