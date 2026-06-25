# QQQ technical-strategy study

Goal: find a **long/flat** technical strategy on daily QQQ that **beats buy-and-hold
on CAGR while taking no more downside (max drawdown) than B&H**, and verify the edge
holds across time scales from ~1 month to ~10 years.

Pure base Julia + stdlib — no packages to install.

**→ For the chosen strategy, its performance across time scales, and how to run it
as an investor, see [STRATEGY.md](STRATEGY.md).** This file documents the *study*
behind it.

## ⭐ Get today's trade signal

```bash
julia analysis/signal.jl          # ← run THIS for the latest call
```

This is the one command you run day-to-day. It loads the **latest** QQQ data from
`../data/` (automatically merging any newer overlapping pulls you've dropped in — see
"Updating the data" below), then prints the current **buy-hold / sell-wait** call for the
adopted **either-on blend**, with the trend- and momentum-filter breakdown:

```
► EITHER-ON  ▲ BUY / HOLD  —  100% QQQ      (or  ▼ SELL / WAIT — hold cash)
► AVG (½-size alt.)  exposure now = 100% QQQ
```

Optional ticker argument (default QQQ): `julia analysis/signal.jl QQQ`.

### Updating the data
**`signal.jl` does this automatically** — every run it pulls the latest QQQ bars from a free
public source (Yahoo Finance, via stdlib `Downloads`; no API key, no data-service site), merges
them into `data/`, and refreshes the web bundle. So normally you just:

```bash
julia analysis/signal.jl              # auto-pull latest → merge → signal (+ refresh web/data.js)
julia analysis/signal.jl --no-fetch   # offline: use existing data only
```

To fetch/inspect explicitly, or for another ticker, use `fetch_data.jl`:

```bash
julia analysis/fetch_data.jl          # QQQ, last 10 trading days → merge into data/
julia analysis/fetch_data.jl SPY 20   # any ticker, last 20 days
julia analysis/fetch_data.jl --no-save # just print, don't write
```

The auto-pull writes one fixed **live-overlay** file in `data/` (git-ignored, overwritten each
run) that `load_ticker` merges on top by date — overlap of any size, this pull wins. You can
still drop a `QQQ (…).csv` export in by hand. Only the first 6 columns (Date, OHLC, Volume) are
read and all indicators are recomputed from price. (Fetching mid-session captures a partial bar
for today — run after the close for official daily values.)

## Repo layout & other scripts

**`analysis/` (root) — the two production blend cases:**

```bash
julia analysis/signal.jl                # today's signal — auto-pulls latest data first (above)
julia analysis/fetch_data.jl            # explicit fetch: pull the last 10 trading days (free source, no key)
julia analysis/build_blend_pages.jl     # execution webpages   → results/blend_either_on.html, blend_avg.html
julia analysis/blend_finalists_compare.jl  # side-by-side either-on vs avg battery (decision table)
julia analysis/blend_walkforward.jl     # out-of-sample validation of the blends
julia analysis/plot_blend_finalists.jl  # equity + drawdown chart → results/blend_finalists.svg
```

**`analysis/sma_study/` — the original SMA-flagship study** (CAGR-beat-with-no-worse-drawdown sweep):
`run_analysis.jl` (sweep/rank/flagship), `walkforward.jl`, `cross_asset_analysis.jl`,
`report.jl`, `plot_results.jl` / `plot_hybrid.jl` / `plot_recent.jl` / `plot_universe.jl`,
`build_report.jl`, `build_onepager.jl`. Run e.g. `julia analysis/sma_study/run_analysis.jl`.

**`analysis/tests/` — exploratory / development scripts** behind the blend (kept for the record):
the CCI band & TMA-switch sweeps and walk-forwards (`cci_*.jl`), the lost-decade study
(`period_1999_2009.jl`), and the earlier two-strategy finalist comparison (`finalists_*.jl`,
`plot_finalists.jl`).

Charts are **SVG** (zero-dependency); plot scripts also emit PNG if `rsvg-convert` is on `PATH`.
Do **not** rasterize wide SVGs with macOS `qlmanage` (it square-crops and chops recent years).
`build_report.jl` inlines the `sma_study` charts, so run those first.
(`julia` lives at `~/.juliaup/bin/julia` on this machine — not on PATH.)

## Method

- **Data**: `../data/QQQ (…).csv`, ~6,860 daily bars, 1999-03-10 → 2026-06-23 (multiple
  overlapping pulls merged by date). The window deliberately spans the dot-com crash, 2008,
  2020 and 2022, so drawdown is stress-tested. **Only the first 6 columns (OHLCV) are used** —
  all indicators are computed in `src/indicators.jl`, never read from the source file.
- **Causality**: every signal is lagged one day (`pos[i] = signal[i-1]`) before it earns a
  return — no look-ahead. Indicators are NaN until their look-back fills, so each strategy
  is automatically flat during warm-up.
- **Accounting**: long/flat only (100 % QQQ or 100 % cash). Cash earns **4 %/yr**; **5 bps**
  proportional cost on turnover. Both assumptions are stress-tested (see sensitivity table).
- **Bar**: CAGR > B&H **and** max drawdown no worse than B&H.
- **Robustness**: rolling windows of 21d…2520d (≈1mo…10yr), reporting how often the strategy
  beats B&H on return and on drawdown at each scale. This guards against the full-sample
  number being a fluke of one lucky regime exit.

## The flagship trend filter (the blend's trend component)

This study's flagship is a 50/200 SMA trend filter in two variants — **Standard (fast
re-entry)** and **Conservative (classic 50/200)**. It is now the **trend component** of
the adopted production strategy, the *either-on blend* (this trend filter combined with a
CCI(40)/TMA momentum filter that covers the fast crashes the SMA misses) — see
**[STRATEGY.md](STRATEGY.md)** for the blend, which is what `signal.jl` reports. The 50/200
golden cross emerged from the sweep below as the best return-per-drawdown rule that
significantly beat B&H; the walk-forward study then showed adding *fast re-entry* (re-enter
when price reclaims the 50-day SMA, ~10-day minimum hold) raises return at the same drawdown
— so it became the Standard variant.

| 1999–2026 | Standard (fast re-entry) | Conservative (50/200) | buy & hold |
|---|---:|---:|---:|
| CAGR | **14.4 %** | 11.9 % | 10.3 % |
| Total (×$1) | **39.0×** | 21.2× | 14.5× |
| Max drawdown | −36 % | −36 % | −83 % |
| Sharpe / Sortino / Calmar | **0.58 / 0.82 / 0.40** | 0.49 / 0.70 / 0.33 | 0.35 / 0.51 / 0.12 |
| OOS 2004+ CAGR / maxDD | 14.1 % / −29 % | 12.4 % / −29 % | 14.7 % / −54 % |
| Trades/yr | ~5 | ~1.3 | 0 |

![equity & drawdown](results/sma_study/hybrid_vs_fixed.svg)

## The honest read

1. **The reliable win is risk, not raw return.** Across rolling windows the flagship is
   shallower-than-or-equal to B&H on drawdown **66–86 %** of the time at *every* scale — a
   robust, assumption-free reduction. Drawdown is roughly halved and Calmar roughly tripled.

2. **It does *not* reliably out-return B&H window-by-window.** Its rolling *return* win-rate
   is mostly **below 50 %** (19–53 % depending on scale). The full-sample CAGR edge comes
   almost entirely from side-stepping the deep, grinding bear markets (esp. the −83 % dot-com
   crash right after the 1999 start), plus earning 4 % in cash while out — not from beating
   B&H in a typical year.

3. **The CAGR edge is assumption-sensitive; the drawdown edge is not.** At 0 % cash the CAGR
   advantage shrinks to ~+0.2 pp (10.5 % vs 10.3 %); at 4–5 % cash it's +1.5–2.0 pp. The
   −36 % vs −83 % drawdown gap holds regardless of cash rate or cost (robust to 10 bps).

## Trade-off frontier (all clear the bar — pick by what you weight)

| if you want…                  | strategy        | CAGR   | maxDD  | Calmar |
|-------------------------------|-----------------|-------:|-------:|-------:|
| max CAGR (accept deeper DD)   | regime-stay 200 | 12.2 % | −51 %  | 0.24   |
| **best balance (flagship)**   | **SMA 50/200**  | 11.9 % | −36 %  | 0.33   |
| smoothest ride (~B&H return)  | CCI(40)>0 / ADX | 10.3–10.5 % | −28 % | 0.37–0.38 |

There is no per-window free lunch: to beat B&H on *return* in a typical window you must stay
~fully invested (≈B&H, little drawdown relief); to cut drawdown hard you must sit out and give
up return. No *single* filter here beats B&H on return in a typical year without leverage. The
**blend below is the study's resolution** — by combining two filters with complementary blind
spots it clears the original bar (beats B&H on full-sample return *and* halves drawdown),
though even it only ties B&H once the dot-com crash is excluded, so the edge stays
bear-concentrated rather than a typical-window free lunch.

### An alternative overlay: the CCI(50) −120/−40 momentum band

A separate, momentum-based risk-reducer (sell when CCI(50) < −120, re-enter when CCI(50) > −40) —
the **precursor to the blend's momentum filter** ([STRATEGY.md §2b](STRATEGY.md)). Over 2006–2026 — split into two
independent decades — it cuts max drawdown to ~−22 % (vs B&H's −36 %/−54 %) and roughly doubles
Calmar in both halves, at ~0.4–1.7 pp/yr less CAGR. Its walk-forward (`tests/cci_walkforward.jl`)
mirrors the SMA finding: the fixed band beats adaptive re-optimization out-of-sample (Calmar
0.59 vs 0.46), evidence it isn't overfit. **Caveat:** unlike the SMA filter it handled the
2000–2002 dot-com grind poorly (full-1999 sample drawdown −66 %, Calmar 0.17). That weakness
was later fixed by gating its exit on a 200-day triangular-MA slope (→ `cci_band_tma_switch`),
which became the blend's momentum filter (below).

## The result — the either-on blend (the adopted strategy)

The study's two risk-reducers fail in *opposite* regimes: the **SMA trend filter** is blind to
fast crashes (it sat through COVID at −29 %) but handles slow grinding bears; the **CCI/TMA
momentum filter** reacts fast to crashes but, alone, gets chopped up in a multi-year bear.
Blending them — **hold QQQ unless *both* say "out"** (`blend_either_on`) — covers both:

| 1999–2026 | either-on blend | avg ½ blend | buy & hold |
|---|---:|---:|---:|
| CAGR | **15.3 %** | 13.7 % | 10.2 % |
| Growth of \$1 | **48×** | 34× | 14× |
| Max drawdown | −37 % | **−33 %** | −83 % |
| Calmar | 0.41 | **0.42** | 0.12 |
| Trades/yr | **~3** | ~12 | 0 |

This is the only candidate in the study to **beat B&H on full-sample return *and* roughly
halve its drawdown** — the bar the study set out to clear. It stays consistent with the "no
free lunch" read above: the return edge is bear-concentrated (out-of-sample 2004+, with the
dot-com crash excluded, `either-on` *ties* B&H at 14.9 % vs 14.5 %, just at half the drawdown).
`either-on` is the adopted default (max return, ~3 trades/yr, all-in/all-out); `avg` is the
smoother ½-size alternative that also cushions fast crashes. Full strategy, performance and
execution: **[STRATEGY.md](STRATEGY.md)**; it's what `signal.jl` reports.

## Files

**Docs & module**
- `STRATEGY.md` — **the deliverable**: chosen strategy, performance over time scales, execution guide
- `QQQBacktest.jl` — module entry point (`include` + `using .QQQBacktest`)

**`src/` — the toolkit**
- `data.jl` — CSV loader; reads only the 6 trusted columns; `load_ticker` merges all of a ticker's files by date (any overlap, newest pull wins)
- `indicators.jl` — all indicators computed from OHLCV: SMA/EMA/TMA/RSI/CCI/MACD/Awesome/ADX, rolling stats, returns, drawdown
- `engine.jl` — causal long/flat backtester · `metrics.jl` — CAGR, Sharpe, Sortino, maxDD, Calmar
- `strategies.jl` — strategy library: trend filters, the CCI band/TMA-switch (`cci_band_tma_switch`), and the blends (`blend_either_on`, `blend_avg`, `blend_components`)
- `crossasset.jl` — align other ETFs to QQQ + cross-asset signals · `evaluate.jl` — rolling multi-timescale + `walk_forward`
- `fetch.jl` — pull recent OHLCV from Yahoo (`fetch_ohlcv`/`update_data`), write the live overlay, and regenerate the web bundle (`write_web_bundle`)

**`analysis/` (root) — production: the two blend cases**
- `signal.jl` — **the day-to-day tool**: auto-pulls the latest data, then prints the buy-hold/sell-wait call for the adopted either-on blend + filter breakdown (and refreshes `web/data.js`)
- `fetch_data.jl` — explicit fetch of recent daily OHLCV from a free public source (Yahoo, via stdlib `Downloads`); no API key or data-service site
- `build_blend_pages.jl` — self-contained execution webpages (`results/blend_either_on.html`, `results/blend_avg.html`)
- `blend_finalists_compare.jl` / `blend_walkforward.jl` — side-by-side battery and OOS validation (STRATEGY.md §3–4)
- `plot_blend_finalists.jl` — equity + drawdown chart (`results/blend_finalists.svg`)

**`sma_study/` — the original SMA-flagship study**
- `run_analysis.jl` (sweep/rank/flagship), `walkforward.jl`, `cross_asset_analysis.jl`, `report.jl`,
  `plot_results.jl` / `plot_hybrid.jl` / `plot_recent.jl` / `plot_universe.jl`, `build_report.jl`, `build_onepager.jl`

**`tests/` — exploratory / development scripts** (the path to the blend; kept for the record)
- CCI band & TMA-switch sweeps + walk-forwards (`cci_band_*.jl`, `cci_tma_*.jl`, `cci_walkforward.jl`, `cci_regime_switch_test.jl`),
  the lost-decade study (`period_1999_2009.jl`), and the earlier finalists comparison (`finalists_compare.jl`, `finalists_blend_test.jl`, `plot_finalists.jl`)

**`results/`** — outputs, mirroring the script layout: root holds the blend artifacts
(`blend_either_on.html`, `blend_avg.html`, `blend_finalists.svg/png`, `blend_walkforward.csv`);
`results/sma_study/` holds the SMA-study CSVs/charts/HTML; `results/tests/` holds the
exploratory outputs. (`signal.jl` writes nothing — it just prints.)
