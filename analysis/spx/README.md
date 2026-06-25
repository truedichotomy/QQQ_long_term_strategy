# S&P 500 1970–2026: the QQQ blend overlay on real daily SPX data

A real out-of-sample test on the broad U.S. large-cap index. Same code
(`blend_either_on` / `blend_avg`, unchanged), same engine, same parameters as the QQQ study.
Real daily OHLC, 14,241 sessions, Jan-1970 → Jun-2026.

**Headline: on the S&P the overlay is roughly *return-neutral* while cutting drawdown by a
third — a clear risk-adjusted improvement.** It sits between its strong QQQ/NASDAQ result and
its weak Dow result, as the index's character does.

```
1970–2026   (cash 4%/yr, 5 bps/trade, price index)
                          CAGR    growth     maxDD    Calmar   %inv   trades
buy & hold               8.0%     79×      −56.8%    0.14     100%      1
trend (50/200)           8.5%     98×      −33.9%    0.25      81%    281
momentum (CCI40/TMA)     6.0%     26×      −41.8%    0.14      71%    527
either-on (adopted)      8.3%     90×      −36.8%    0.23      88%    205
avg (½-size)             7.3%     55×      −29.1%    0.25      76%    771
```

- **Return:** `either-on` edges buy-and-hold (8.3% vs 8.0%, +0.3 pp); `avg` trails by 0.7 pp.
  Essentially a tie — the overlay neither adds nor costs much on the S&P.
- **Drawdown:** −56.8% → −36.8% (either-on) / −29.1% (avg) — cut by a third to a half.
- **Risk-adjusted:** Calmar nearly doubles, 0.14 → 0.23 / 0.25. *This* is the real gain on
  the S&P: same return, far less pain. `either-on` beats B&H on return in 45% of rolling
  5-yr windows but is shallower-drawdown in 80% (avg: 40% / 89%).

## Where it helps and where it doesn't (return over span / deepest drawdown within)

| regime | span | buy & hold | either-on | avg (½) |
|---|---|---:|---:|---:|
| 1973–74 bear | 2.0 y | −42% / −48% | −35% / −37% | **−25% / −27%** |
| 1980s bull | 5.1 y | **+203%** / −14% | +197% / −12% | +146% / −11% |
| 1987 crash | 0.4 y | −22% / −34% | −18% / −33% | **−10% / −21%** |
| 1990s bull | 9.5 y | **+385%** / −19% | +328% / −19% | +193% / −14% |
| **dot-com crash** | 2.5 y | −49% / −49% | **−21% / −21%** | −18% / −19% |
| **GFC** | 1.4 y | −57% / −57% | −31% / −32% | **−25% / −25%** |
| 2009–2020 bull | 10.9 y | **+401%** / −20% | +199% / −20% | +152% / −15% |
| COVID crash | 0.1 y | −34% / −34% | −34% / −34% | **−21% / −21%** |
| 2022 bear | 0.8 y | −25% / −25% | −17% / −17% | **−13% / −13%** |
| **FULL** | 56.5 y | +7769% / −57% | **+8930% / −37%** | +5367% / −29% |

- **Wins:** the slow grinding bears — dot-com (−21% vs −49%) and GFC (−31% vs −57%) — plus
  the 1973–74 bear. That's where `either-on` claws back its full-period return lead.
- **Losses:** the long bulls (being out/half-out bleeds return) and fast one-shot crashes
  (`either-on` rode COVID −34% with B&H; the slow trend filter can't turn in a day). `avg`
  cushions the fast ones (1987 −10%, COVID −21%).

## How SPX compares to the other indices

Same overlay, four indices — the **return** benefit scales with how hard the asset trends and
crashes; the **drawdown** protection is universal:

| index | period | ann.vol | B&H CAGR | either-on CAGR | Δ return | B&H maxDD → either-on |
|---|---|---:|---:|---:|---:|---:|
| NASDAQ 100 | 1985–2026 | 25.7% | 14.1% | 17.1% | +3.0 pp | −83% → −40% |
| QQQ *(STRATEGY.md)* | 1999–2026 | — | 10.2% | 15.3% | +5.1 pp | −83% → −37% |
| **S&P 500** (this) | 1970–2026 | 17.2% | 8.0% | **8.3%** | **+0.3 pp** | −57% → −37% |
| Dow (DJI) | 1970–2026 | 17.0% | 7.7% | 6.0% | −1.7 pp | −54% → −45% |

The S&P lands in the middle: less concentrated/volatile than the NASDAQ (so a smaller return
edge) but more cleanly trending than the price-weighted Dow (so it doesn't *lose* return like
the Dow does).

## Variant choice

A genuine toss-up on the S&P: `either-on` for the slight return edge + a one-third drawdown
cut, or `avg` for the smoothest ride (best Calmar 0.25, cushions fast crashes, shallower than
B&H in 89% of 5-yr windows). Both are defensible risk-adjusted improvements here.

## Caveats

- **Price index, no dividends** (~2%/yr on the S&P). Adding them *widens* buy-and-hold's edge,
  since it's always invested while the overlay sits in cash ~12–24% of the time.
- Flat 4% cash understates the high-rate 1970s–80s, when the overlay was parked in cash
  through the 1973–74 bear earning 8–15% — that cuts the other way. Standard engine
  assumptions (one-day lag, 5 bps/trade).

## Reproduce

```bash
export PATH="$HOME/.juliaup/bin:$PATH"
julia --startup-file=no analysis/spx/backtest.jl   # metrics, regime table, rolling win-rates
julia --startup-file=no analysis/spx/plot.jl        # blend_SPX_1970_2026.svg
```

*Historical backtest of mechanical rules on one index — not investment advice.*
