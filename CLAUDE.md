# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal quantitative investment analysis project written in Julia (`.jl` scripts run directly, not a package). There is no build system or automated test suite. Julia **is** installed, but at `~/.juliaup/bin/julia` and **not on `PATH`** — prefix it (`export PATH="$HOME/.juliaup/bin:$PATH"`) or call the full path. The global package env is empty, so prefer **pure base Julia + stdlib** (`Statistics`, `Printf`, `Dates`) and avoid heavy packages (CSV/DataFrames/Plots) — the `analysis/` pipeline parses CSVs and renders charts (SVG) with zero dependencies on purpose.

The repo is **all about the `analysis/` pipeline on QQQ daily data**. There is a top-level `old/` directory of unrelated 2024 legacy scripts — **ignore it entirely**; it has no bearing on current work.

## Running scripts

```bash
export PATH="$HOME/.juliaup/bin:$PATH"
julia --startup-file=no analysis/signal.jl                  # ⭐ today's trade signal (the day-to-day tool)
julia --startup-file=no analysis/sma_study/run_analysis.jl  # the broader strategy sweep / ranking study
julia --startup-file=no analysis/sma_study/plot_results.jl  # render results/sma_study/equity_curves.svg
```

## Repository layout

- `data/` — per-ETF historical CSVs for **DIA, GLD, IWM, QQQ, SPY, TIP, TLT, XLE**. Filenames encode the range as `TICKER (ENDts _ STARTts).csv` (17-digit `YYYYMMDD...`). A ticker may have **multiple** files (a long history plus a fresh overlapping pull); `load_ticker` merges all of them by date — overlap of any size is deduped, newest pull (larger end-timestamp) wins. Drop in a newer file to extend the series.
- `analysis/` — the backtesting toolkit and drivers (below). Outputs land in `analysis/results/`, which **mirrors the script layout**: blend artifacts in `results/` root, `results/sma_study/`, `results/tests/`.

### `analysis/` structure
- **Module** — `QQQBacktest.jl` + `src/{data,indicators,engine,metrics,strategies,crossasset,evaluate}.jl`: a causal **long/flat** backtester that judges strategies on CAGR **and** max drawdown vs buy-and-hold, with rolling multi-timescale robustness. Signals are lagged one day (no look-ahead); cash earns a configurable rate; turnover is charged a cost.
- **`analysis/` root — production (the adopted overlay).** `signal.jl` prints today's buy-hold/sell-wait call. The adopted strategy is the **either-on blend** (`blend_either_on`): long if EITHER a 50/200 SMA fast-reentry **trend** filter OR a CCI(40)/TMA(200) **momentum** filter (`cci_band_tma_switch`) is long — they fail in opposite regimes, so the blend covers both. `blend_avg` is the smoother ½-size alternative. Also here: `build_blend_pages.jl`, `blend_finalists_compare.jl`, `blend_walkforward.jl`, `plot_blend_finalists.jl`. Execution guide: `analysis/STRATEGY.md` §4c; study writeup: `analysis/README.md`.
- **`sma_study/`** — the earlier SMA-flagship study: `run_analysis.jl` (sweep/rank/flagship), `walkforward.jl`, `cross_asset_analysis.jl`, `report.jl`, `plot_results.jl`/`plot_hybrid.jl`/`plot_recent.jl`/`plot_universe.jl`, `build_report.jl`/`build_onepager.jl`. Its flagship is a 50/200 SMA trend filter (`fast_reentry`, "Standard"). **Note:** `fast_reentry` MUST keep its `hold` parameter (default 10) — without the minimum-hold it whipsaws ~33×/yr.
- **`tests/`** — exploratory/development scripts behind the blend (CCI band & TMA-switch sweeps and walk-forwards, the 1999–2009 lost-decade study, the earlier finalists comparison). These are studies kept for the record, **not** a unit-test suite.

Scripts in `sma_study/` and `tests/` anchor their paths via `dirname(@__DIR__)`: the module and `results/` live in `analysis/`, the `data/` directory at the repo root.

## Data format notes

- **Only the first 6 columns are trusted**: Date, Open, High, Low, Close, Volume. The loader **ignores everything past column 6** — source files may append technical-indicator columns (CCI, `MA ...`, Awesome, MACD/Signal/hist, ADX/+DI/-DI), but their count and meaning are NOT guaranteed across pulls. So **all indicators are computed ourselves** from OHLCV (`src/indicators.jl`: `sma`/`ema`/`tma`/`rsi`/`cci`/`macd`/`awesome`/`adx`); strategies never read provider indicator columns.
- **Dates** are ISO timestamps (`1999-03-10T05:00:00.000Z`) — parse the leading 10-char date.
- **Volume** is quoted with thousands separators (`"5,232,202"`) — strip commas before parsing to a number.
