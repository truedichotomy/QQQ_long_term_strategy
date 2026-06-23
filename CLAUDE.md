# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal quantitative investment analysis project written in Julia (`.jl` scripts run directly, not a package). There is no build system or test suite. Julia **is** installed, but at `~/.juliaup/bin/julia` and **not on `PATH`** — prefix it (`export PATH="$HOME/.juliaup/bin:$PATH"`) or call the full path. The global package env is empty, so prefer **pure base Julia + stdlib** (`Statistics`, `Printf`, `Dates`) and avoid adding heavy packages (CSV/DataFrames/Plots) unless asked — the `analysis/` pipeline parses CSVs and renders charts (SVG) with zero dependencies on purpose.

## Running scripts

```bash
export PATH="$HOME/.juliaup/bin:$PATH"
julia --startup-file=no analysis/signal.jl              # ⭐ today's trade signal (adopted either-on blend) — the day-to-day tool
julia --startup-file=no analysis/sma_study/run_analysis.jl  # the QQQ technical-strategy study (see analysis/README.md)
julia --startup-file=no analysis/sma_study/plot_results.jl  # render results/sma_study/equity_curves.svg
julia old/QQQ_analysis.jl                               # legacy script (needs CSV/DataFrames/Plots installed)
```

Layout under `analysis/`: root holds the **module + the two production blend scripts** (`signal.jl`, `build_blend_pages.jl`, `blend_finalists_compare.jl`, `blend_walkforward.jl`, `plot_blend_finalists.jl`); `sma_study/` holds the original SMA-flagship study; `tests/` holds the exploratory CCI/band-sensitivity scripts. Moved scripts anchor paths via `dirname(@__DIR__)` (module/results in `analysis/`, data at repo root).

The legacy `old/` scripts are meant to be explored in the REPL — most end on a bare expression that is the "output"; `include(...)` them to keep variables live. They depend on `CSV, Dates, DataFrames, Statistics, Plots`. The `analysis/` pipeline runs fine from the shell and writes artifacts to `analysis/results/`.

## Repository layout (mid-reorganization)

The working tree is being restructured (the `old/`→`data/`/`analysis/` moves are uncommitted):
- `old/` — the original 2024 scripts and data. Treat as legacy/reference.
- `data/` — current data: per-ETF historical CSVs for **DIA, GLD, IWM, QQQ, SPY, TIP, TLT, XLE**. Filenames encode the range as `TICKER (ENDtimestamp _ STARTtimestamp).csv` (17-digit zero-padded `YYYYMMDD...`). A ticker may have **multiple** files (e.g. a long history plus a fresh overlapping pull); `load_ticker` merges all of them by date — overlap of any size is deduped, newest pull (larger end-timestamp) wins. Just drop in a newer file to extend the series.
- `analysis/` — the current backtesting toolkit (`QQQBacktest` module: `src/{data,indicators,engine,metrics,strategies,crossasset,evaluate}.jl`) plus driver scripts. It backtests **long/flat** technical strategies on daily QQQ, judging them on CAGR **and** max drawdown vs buy-and-hold, with rolling multi-timescale robustness checks. Signals are lagged one day (no look-ahead); cash earns a configurable rate; turnover is charged a cost. The chosen strategy is a QQQ 50/200 SMA trend filter in two variants — **Standard** (`fast_reentry`: re-enter when price reclaims the 50-day SMA, ~10-day min hold) as the central strategy and **Conservative** (`sma_cross` 50/200 golden cross) as the lower-turnover alternative; execution guide in `analysis/STRATEGY.md`, study writeup in `analysis/README.md`. Note: `fast_reentry` MUST keep its `hold` parameter (default 10) — without the minimum-hold it whipsaws ~33×/yr. The adopted day-to-day overlay is now the **either-on blend** of that SMA filter with a CCI(40)/TMA momentum filter (`blend_either_on`; see STRATEGY.md §4c) — `signal.jl` (analysis/ root) reports its live buy-hold/sell-wait call. Drivers by folder: root = blend production (`signal.jl`, `build_blend_pages.jl`, `blend_finalists_compare.jl`, `blend_walkforward.jl`, `plot_blend_finalists.jl`); `sma_study/` = `run_analysis.jl` (sweep/rank), `cross_asset_analysis.jl`, `report.jl`, `plot_results.jl`/`plot_hybrid.jl`/`plot_recent.jl`/`plot_universe.jl`, `build_report.jl`/`build_onepager.jl`; `tests/` = exploratory CCI/band sweeps & walk-forwards. Outputs land in `analysis/results/`.

## The two models (they are unrelated — don't conflate them)

**Value-averaging calculators** (`old/investment_value_averaging_calculator*.jl`) — forward-looking contribution planners, not backtests. They convert an anticipated *annual* return into a per-period compound rate (`(1+annual)^(1/periods) - 1`), then iterate a target portfolio value for each trading period of the year. `...calculator2.jl` is the newer one and additionally tracks cumulative shares acquired; it carries multiple scenarios as commented-out `#= ... =#` blocks (VOO/QQQ at different dates), with only the active one uncommented — preserve that pattern when editing.

**Mean-reversion backtest** (`old/QQQ_analysis.jl`) — tests the rule `T = -X/(X+1)`, where `X` is a day's fractional price change and `T` is the fraction of current value to buy (X<0) or sell (X>0). It compares this daily-rebalanced value path `V`/principal `P` against buy-and-hold `BH` over a date window (`t0`..`tN`).

## Data format gotcha

The new `data/` CSVs are **not** in the same format as `old/QQQ_2000-2024.csv`, and `QQQ_analysis.jl` was written for the old format. Before pointing existing code at `data/`:
- **Date**: new files use ISO timestamps (`1999-03-10T05:00:00.000Z`); old files use plain dates (`2000-03-13`). Parse to `Date` accordingly.
- **Volume**: new files quote it with thousands separators (`"5,232,202"`) — strip commas before parsing to a number. Old files have plain integers.
- **Columns**: ONLY the first 6 columns (Date, Open, High, Low, Close, Volume) are trusted and parsed — the `analysis/` loader **ignores everything past column 6**. New files happen to append ~13 technical-indicator columns (CCI, `MA ...`, Awesome, MACD/Signal/hist, ADX/+DI/-DI), but their count/meaning are NOT guaranteed across pulls, so **all indicators are computed ourselves** from OHLCV (`analysis/src/indicators.jl`: `sma`/`ema`/`tma`/`rsi`/`cci`/`macd`/`awesome`/`adx`). Strategies never read provider indicator columns. (The legacy `old/` scripts still expect the old `Adj Close` format — unchanged.)
