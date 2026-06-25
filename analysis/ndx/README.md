# NASDAQ 100 1985–2026: the QQQ blend overlay on real daily NDX data

The marquee test. NDX is **the index QQQ tracks** — so this is the adopted blend run on its
own underlying, but back to **1985** (vs QQQ's data from 1999), capturing the 1987 crash and
the *entire* dot-com round trip from a 1990s base. Same code (`blend_either_on` / `blend_avg`,
unchanged), same engine, same parameters. Real daily OHLC, 10,428 sessions.

**Headline: the textbook win — the overlay BEATS buy-and-hold on return *and* cuts the worst
drawdown by more than half.** This is the "trends hard, crashes hard" asset the filters were
built for, and it shows.

```
1985–2026   (cash 4%/yr, 5 bps/trade, price index)
                          CAGR    growth     maxDD    Calmar   %inv   trades
buy & hold              14.1%    234×      −82.9%    0.17     100%      1
trend (50/200)          15.9%    443×      −39.9%    0.40      82%    195
momentum (CCI40/TMA)    14.1%    234×      −38.1%    0.37      72%    339
either-on (adopted)     17.1%    678×      −39.9%    0.43      89%    123
avg (½-size)            15.3%    359×      −31.5%    0.49      77%    513
```

- **Return:** `either-on` adds **+3.0 pp/yr** over buy-and-hold (17.1% vs 14.1%) — 678× vs
  234× over 41 years. `avg` also beats it (+1.2 pp).
- **Drawdown:** −82.9% → −39.9% (either-on) / −31.5% (avg). The dot-com −83% collapse is
  cut to −31% / −27%.
- **Risk-adjusted:** Calmar leaps from 0.17 to 0.43 / 0.49 — a different risk profile entirely.

## Where the edge comes from (return over span / deepest drawdown within)

| regime | span | buy & hold | either-on | avg (½) |
|---|---|---:|---:|---:|
| 1987 crash | 0.4 y | −20% / −40% | −16% / −40% | **−6% / −24%** |
| 1990s bull | 9.5 y | **+2440%** / −23% | +2175% / −23% | +1304% / −21% |
| **dot-com crash** | 2.5 y | **−83% / −83%** | **−31% / −36%** | −27% / −29% |
| GFC | 1.4 y | −52% / −54% | −27% / −31% | **−23% / −25%** |
| 2009–2020 bull | 10.9 y | **+831%** / −23% | +522% / −22% | +384% / −16% |
| COVID crash | 0.1 y | −28% / −28% | −28% / −28% | **−20% / −20%** |
| 2022 bear | 0.8 y | −35% / −35% | −14% / −18% | **−9% / −11%** |
| **FULL** | 41.4 y | +23264% / −83% | **+67717% / −40%** | +35787% / −31% |

The whole return edge is **the dot-com crash**: sidestepping a −83% collapse (the filters
exited and held cash through 2000–02) means re-entering the 2003+ recovery from a vastly
higher base. `either-on` still keeps the fast-crash blind spot (1987 −16%, COVID −28%, with
buy-and-hold); `avg` is the only variant that cushions those.

## How NDX compares to the other indices

Running the *same* overlay across four indices reveals a clean gradient — the **return**
benefit scales with how hard the asset trends and crashes; the **drawdown** protection is
universal:

| index | period | ann.vol | B&H CAGR | either-on CAGR | Δ return | B&H maxDD → either-on |
|---|---|---:|---:|---:|---:|---:|
| **NASDAQ 100** (this) | 1985–2026 | 25.7% | 14.1% | **17.1%** | **+3.0 pp** | −83% → −40% |
| QQQ *(STRATEGY.md)* | 1999–2026 | — | 10.2% | 15.3% | +5.1 pp | −83% → −37% |
| S&P 500 | 1970–2026 | 17.2% | 8.0% | 8.3% | +0.3 pp | −57% → −37% |
| Dow (DJI) | 1970–2026 | 17.0% | 7.7% | 6.0% | −1.7 pp | −54% → −45% |

NDX/QQQ (volatile, deep-crashing) are where the overlay *adds* return; the choppy Dow is
where it *costs* return. NDX's edge (+3.0) looks smaller than QQQ's (+5.1) only because this
longer window starts before the bubble — B&H's NDX CAGR is flattered by the 1990s mega-bull —
but the overlay still wins outright.

## Variant choice

Here `either-on` is the pick (highest return, +3 pp, halves drawdown) — the same conclusion
as QQQ, and the *opposite* of the Dow (where `avg` is preferred). `avg` is the better
risk-adjusted ride (Calmar 0.49, cushions 1987/COVID/2022) if you want the smoothest path.

## Caveats

- **Price index, no dividends** (~0.5–1%/yr on NDX — small, tech pays little). Adds slightly
  to buy-and-hold; the overlay collects it ~80% of the time.
- Flat 4% cash; a time-varying rate (high in the late-80s/90s) would help the overlay, which
  is in cash ~20% of the time. Standard engine assumptions (one-day lag, 5 bps/trade).

## Reproduce

```bash
export PATH="$HOME/.juliaup/bin:$PATH"
julia --startup-file=no analysis/ndx/backtest.jl   # metrics, regime table, rolling win-rates
julia --startup-file=no analysis/ndx/plot.jl        # blend_NDX_1985_2026.svg
```

*Historical backtest of mechanical rules on one index — not investment advice.*
