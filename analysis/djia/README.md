# DJIA 1970–2026: the QQQ blend overlay on real daily Dow data

A genuine out-of-sample test. The blend's parameters were chosen on QQQ (1999–2026);
here the **same code** (`blend_either_on` / `blend_avg`, unchanged) runs on **real daily
DJIA, Dec-1969 → Jun-2026** (`data/DJI …csv`, 14,248 sessions). Unlike the
[1920s screenshot experiment](../1920s/), this is real intraday OHLC — no smoothing.

**Headline: on the Dow the overlay's *return* edge does not transfer — it costs ~2 pp/yr —
but its *drawdown* protection does.** That is the opposite of the QQQ result, and it is
exactly what the study's own cross-asset caveat predicted (`STRATEGY.md §5`: the 50/200
filter *hurt* return on the choppier Dow). QQQ trends hard and crashes hard, so the filters
add return; the Dow chops and its crashes are often one-shot, so they don't.

```
1970–2026   (cash 4%/yr, 5 bps/trade, price index)
                          CAGR    growth    maxDD    Calmar   %inv   trades
buy & hold               7.7%     66×      −53.8%    0.14     100%      1
trend (50/200)           5.9%     25×      −42.6%    0.14      80%    319
momentum (CCI40/TMA)     4.5%     12×      −35.4%    0.13      70%    597
either-on (adopted)      6.0%     27×      −44.6%    0.13      88%    225
avg (½-size)             5.3%     19×      −32.7%    0.16      75%    864
```

- **Return:** both blends *trail* buy-and-hold — either-on by −1.7 pp/yr, avg by −2.4 pp/yr.
  Over 56 years that compounds to a wide terminal gap (66× vs 27× / 19×).
- **Drawdown:** both *cut* it — worst drawdown −54% → −45% (either-on) / −33% (avg). `avg`
  roughly halves the deepest hole.
- **Risk-adjusted:** essentially a wash. Calmar is 0.14 (B&H) vs 0.13 (either-on) / 0.16
  (avg). The overlay trades return for drawdown roughly 1-for-1 — no free lunch on the Dow,
  whereas on QQQ the same overlay lifts Calmar from 0.12 to ~0.41.

## avg vs either-on: the normal ordering is restored

This closes the question raised by the smoothed 1920s series (where `avg` oddly out-returned
`either-on`). On **real daily** data the expected QQQ ordering holds:

- `either-on` wins **return** (6.0% vs 5.3%) — full exposure compounds.
- `avg` wins **drawdown** (−33% vs −45%) and is shallower than B&H in **91%** of rolling
  5-yr windows (either-on 67%).

So `avg` out-returning `either-on` was indeed a smoothing artifact — confirmed.

## Where it helps and where it doesn't (return over span / deepest drawdown within)

| regime | span | buy & hold | either-on | avg (½) |
|---|---|---:|---:|---:|
| 1973–74 bear | 2.0 y | −40% / −45% | −43% / −45% | **−30% / −31%** |
| 1980s bull | 5.1 y | **+224%** / −16% | +190% / −18% | +151% / −13% |
| 1987 crash | 0.4 y | −24% / −36% | −23% / −36% | **−15% / −25%** |
| 1990s bull | 9.3 y | **+366%** / −19% | +297% / −19% | +197% / −14% |
| dot-com crash | 2.7 y | −38% / −38% | −34% / −34% | **−32% / −32%** |
| **GFC** | 1.4 y | −54% / −54% | −32% / −33% | **−24% / −26%** |
| 2009–2020 bull | 10.9 y | **+351%** / −19% | +201% / −19% | +121% / −19% |
| COVID crash | 0.1 y | −37% / −37% | −37% / −37% | **−22% / −22%** |
| 2022 bear | 0.8 y | −20% / −22% | **−11% / −15%** | −13% / −14% |
| **FULL** | 56.5 y | **+6494%** / −54% | +2576% / −45% | +1771% / −33% |

- **Wins** are the *slow, grinding* bears the trend filter is built for: GFC (−32/−24% vs
  −54%) and dot-com. `avg` cushions every crash including the fast ones.
- **Losses** are (a) the long **bulls**, where being out / half-out bleeds return (2009–20:
  B&H +351% vs +201% / +121%), and (b) **fast one-shot crashes** — `either-on` rode 1987
  (−23%) and COVID (−37%) down with B&H, because the slow trend filter can't turn in a day
  and (being an OR) `either-on` stays long while it's still "in." `avg` is the only variant
  that cushions those (−15%, −22%).

## Takeaway

On the Dow this overlay is a **drawdown-reduction tool that costs return**, not a return
enhancer — a risk-management choice. If you'd run it here, **`avg` is the variant to pick**
(best Calmar, 91% drawdown win-rate, cushions fast crashes) — the *opposite* of QQQ, where
`either-on` is preferred. The cleaner conclusion is the study's existing one: this family of
filters earns its keep on assets that **trend and crash hard** (QQQ, energy, long bonds), and
the price-weighted Dow isn't one of them.

## Caveats

- **Price index, no dividends.** The Dow's ~2–3%/yr dividends are excluded. Adding them
  *widens* B&H's lead, because B&H is always invested while the overlay sits in cash ~15–25%
  of the time — so the real total-return gap is a bit larger than shown.
- **Flat cash rate cuts the other way.** Cash earned a flat 4% here; in the high-rate
  1970s–80s T-bills paid 8–15%, and the overlay was in cash through the 1973–74 bear — a
  realistic time-varying rate would help it and partly offset the dividend drag.
- Same engine assumptions as the QQQ study (one-day signal lag, 5 bps/trade). DJIA is
  price-weighted, a different animal from cap-weighted QQQ.

## Reproduce

```bash
export PATH="$HOME/.juliaup/bin:$PATH"
julia --startup-file=no analysis/djia/backtest.jl   # metrics, regime table, rolling win-rates
julia --startup-file=no analysis/djia/plot.jl        # djia_blend_1970_2026.svg
```

*Historical backtest of mechanical rules on one index — not investment advice.*
