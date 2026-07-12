# QQQ_long_term_strategy

**Live signal: <https://truedichotomy.github.io/QQQ_long_term_strategy/>** — auto-updated
each market day after the close by a GitHub Actions cron. When the trade action changes,
the cron publishes a [GitHub release](../../releases) — Watch this repo (Custom → Releases)
to get those by email, or subscribe to the [releases feed](../../releases.atom) by RSS;
a private ntfy.sh push topic is also notified.

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

That one command **pulls the latest QQQ data when it's worth it** from a free public source
(Yahoo Finance — no API key, no data-service site), merges it into `data/`, prints the current
**buy-hold / sell-wait** call for **both blends** with the two-filter breakdown, and refreshes the
web app's bundled data. No data to hunt down. To spare the free API the pull is **throttled** — it
only happens when the local data is over an hour old *and* either the US market is open or the local
data has fallen behind the most recent completed session (an idle closed market whose last close you
already hold needs no pull, but a run after a few days away still catches up). Add `--fetch` to force
a refresh, or `--no-fetch` to run offline. Before noon ET the call is read off the last completed session; after noon it uses today's
still-forming bar, to plan tomorrow's trade.

**No Julia?** Open **[web/index.html](web/index.html)** in any browser — it shows the signal
from the bundled history (refreshed whenever you run `signal.jl`), with tabs for either blend
and an "as of" date for any past day. You can also drop a newer CSV on it to extend its own
local database. The browser can't fetch the data source directly (CORS), which is why the
auto-pull lives in `signal.jl`. See [web/README.md](web/README.md).

## Where things are

- **[analysis/](analysis/)** — the toolkit and all the work. Start with
  **[analysis/STRATEGY.md](analysis/STRATEGY.md)** (the strategy + how to run it as an
  investor) and **[analysis/README.md](analysis/README.md)** (the study behind it).
  Layout: production blend scripts in `analysis/` root, the earlier SMA-flagship study
  in `analysis/sma_study/`, exploratory studies in `analysis/tests/`, outputs in
  `analysis/results/`.
- **[data/](data/)** — daily OHLCV CSVs per ETF (only the 6 OHLCV columns are used; all
  indicators are computed from price).

Pure base Julia + stdlib — nothing to install.

## License & disclaimer

Copyright © 2026 Donglai Gong. **All rights reserved** — publicly viewable for reference
and education; no license to use, copy, or redistribute without written permission. See
[LICENSE](LICENSE).

**Not investment advice.** This project describes a mechanical backtest rule; past
performance does not guarantee future results, and the data or signal may be delayed,
incomplete, or wrong. Any trading or investment decision you make is yours alone — the
author accepts no responsibility or liability for losses arising from the use of, or
reliance on, anything in this repository or on the signal page.
