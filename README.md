# investment

Personal quantitative investment research in Julia — a zero-dependency backtesting
toolkit that designs and validates **long/flat timing overlays on QQQ** (be fully in
QQQ or in cash), judged on return **and** drawdown versus buy-and-hold.

The adopted strategy is the **either-on blend**: hold QQQ unless *both* a slow trend
filter (50/200-day SMA with fast re-entry) and a fast momentum filter (CCI(40) with a
200-day triangular-MA regime switch) say "out." The two fail in opposite market
regimes, so blending them keeps most of buy-and-hold's return while roughly halving the
worst drawdowns — at about three trades a year.

## Get today's trade signal

```bash
export PATH="$HOME/.juliaup/bin:$PATH"     # Julia lives in ~/.juliaup/bin
julia --startup-file=no analysis/signal.jl
```

Prints the current **buy-hold / sell-wait** call with the two-filter breakdown.

To refresh the data first (no manual download, no data-service site), fetch the latest
bars from a free public source and re-run:

```bash
julia --startup-file=no analysis/fetch_data.jl   # pull the last 10 trading days of QQQ → data/
julia --startup-file=no analysis/signal.jl       # signal on the refreshed data
```

`fetch_data.jl` writes a CSV into `data/` that the loader merges by date automatically
(newest pull wins on overlap). You can also drop in any `QQQ (…).csv` export by hand.

## Where things are

- **[analysis/](analysis/)** — the toolkit and all the work. Start with
  **[analysis/STRATEGY.md](analysis/STRATEGY.md)** (the strategy + how to run it as an
  investor) and **[analysis/README.md](analysis/README.md)** (the study behind it).
  Layout: production blend scripts in `analysis/` root, the earlier SMA-flagship study
  in `analysis/sma_study/`, exploratory studies in `analysis/tests/`, outputs in
  `analysis/results/`.
- **[data/](data/)** — daily OHLCV CSVs per ETF (only the 6 OHLCV columns are used; all
  indicators are computed from price).

Pure base Julia + stdlib — nothing to install. Not investment advice; past performance
does not guarantee future results.
