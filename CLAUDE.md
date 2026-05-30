# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal quantitative investment analysis project written in Julia (`.jl` scripts run directly, not a package). There is no build system, test suite, or Julia project environment (`Project.toml`/`Manifest.toml`) — scripts are run top-to-bottom and inspected interactively. Julia is **not currently installed** on this machine.

## Running scripts

```bash
julia old/QQQ_analysis.jl          # run a whole script
julia                              # then include("old/QQQ_analysis.jl") in the REPL to keep results live
```

Scripts are meant to be explored in the REPL: most end on a bare expression (e.g. the results table or a final value) that is the "output." Re-run from the REPL rather than the shell so the variables stay inspectable. `QQQ_analysis.jl` depends on `CSV, Dates, DataFrames, Statistics, Plots`; the calculators use only base Julia. Install missing packages with `import Pkg; Pkg.add("...")`.

## Repository layout (mid-reorganization)

The working tree is being restructured (these moves are uncommitted):
- `old/` — the original 2024 scripts and data. Treat as legacy/reference.
- `data/` — current data: per-ETF historical CSVs for **DIA, GLD, IWM, QQQ, SPY, TIP, TLT, XLE**. Filenames encode the range as `TICKER (ENDtimestamp _ STARTtimestamp).csv` (17-digit zero-padded `YYYYMMDD...`).
- `analysis/` — empty; intended home for new analysis scripts written against `data/`.

## The two models (they are unrelated — don't conflate them)

**Value-averaging calculators** (`old/investment_value_averaging_calculator*.jl`) — forward-looking contribution planners, not backtests. They convert an anticipated *annual* return into a per-period compound rate (`(1+annual)^(1/periods) - 1`), then iterate a target portfolio value for each trading period of the year. `...calculator2.jl` is the newer one and additionally tracks cumulative shares acquired; it carries multiple scenarios as commented-out `#= ... =#` blocks (VOO/QQQ at different dates), with only the active one uncommented — preserve that pattern when editing.

**Mean-reversion backtest** (`old/QQQ_analysis.jl`) — tests the rule `T = -X/(X+1)`, where `X` is a day's fractional price change and `T` is the fraction of current value to buy (X<0) or sell (X>0). It compares this daily-rebalanced value path `V`/principal `P` against buy-and-hold `BH` over a date window (`t0`..`tN`).

## Data format gotcha

The new `data/` CSVs are **not** in the same format as `old/QQQ_2000-2024.csv`, and `QQQ_analysis.jl` was written for the old format. Before pointing existing code at `data/`:
- **Date**: new files use ISO timestamps (`1999-03-10T05:00:00.000Z`); old files use plain dates (`2000-03-13`). Parse to `Date` accordingly.
- **Volume**: new files quote it with thousands separators (`"5,232,202"`) — strip commas before parsing to a number. Old files have plain integers.
- **Columns**: new files append ~13 technical-indicator columns (CCI, several `MA ...` moving averages, Awesome oscillator, MACD/Signal/hist, ADX/+DI/-DI) and have **no `Adj Close`**; old files have `Adj Close` and no indicators. `Close` exists in both. Early rows have empty indicator cells until each indicator's lookback window fills.
