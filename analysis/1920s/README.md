# DJIA 1920–1955: the QQQ blend overlay through the Great Depression

An experiment: take a screenshot of the Dow Jones Industrial Average from 1920–1955,
**extract the index as a time series from the pixels**, then run the adopted QQQ
**either-on blend** overlay on it as if DJIA were QQQ. The period is the ultimate stress
test — it contains the 1929 crash and the −89% Depression collapse, the deepest drawdown
in U.S. large-cap history.

**Headline:** the overlay would have stepped to cash in October 1929, sidestepped the bulk
of the collapse, and turned buy-and-hold's `4.8×` price-only return (with an −84% drawdown)
into roughly `100×` at a fraction of the drawdown. The *direction* of that result is robust;
the *exact* risk numbers are flattered by the data being monthly (see Caveats).

```
                          CAGR    growth    maxDD     (cash 1%/yr, 5 bps/trade, price index)
buy & hold               4.4%      4.8×    −84.0%
trend filter (50/200)   11.4%     48×      −14.2%     ← most trustworthy (slow, trend-driven)
momentum (CCI40/TMA)    17.4%    323×       −2.9%     ← least trustworthy (feeds on daily extremes)
either-on (adopted)     13.9%    107×      −14.2%
avg (½-size)            14.4%    125×       −8.2%
```

## What was done

1. **Pixel extraction** (`extract.jl`). `sips` decodes the PNG to a 32-bit BMP; base Julia
   parses it. For every pixel column the blue plot line's median row is converted to an
   index value via an axis calibration fitted to the chart's horizontal gridlines
   (`value = 648.2 − 0.759·y`, fitted on the 300/400/500/600 gridlines). The line is
   resampled to **432 month-end closes**, Jan-1920 → Dec-1955.
   - *Validation:* the extracted year-end closes track the real DJIA within a few percent
     across all 36 years (1928: 301 vs actual 300; 1932: 62 vs 60; 1951: 269 vs 269;
     1955: 487 vs 488). The 1929→1932 peak-to-trough reads −84% (textbook −89%; the line's
     thickness shaves the wicks).
   - Output: `djia_monthly.csv`.
2. **To business days** (`extract.jl`). The monthly series is linearly interpolated onto
   ~252 business days/year (`djia_daily.csv`) so the day-tuned indicators keep their real
   horizons (200-"day" SMA ≈ 9.5 months, CCI(40) ≈ 2 months). Only a close is recoverable
   from a line chart, so **O=H=L=C** (CCI then uses the close as its typical price).
3. **Backtest** (`backtest.jl`). The *same* `blend_either_on` / `blend_avg` code from
   `src/strategies.jl`, run through the *same* engine. Cash earns 1%/yr (era-appropriate;
   sensitivities at 0% and 4% are also printed), 5 bps/trade.
4. **Chart** (`plot.jl` → `djia_blend_1920_1955.svg`): DJIA (log) with the overlay's
   out-of-market stretches shaded, over growth-of-$1.

## What it caught

The either-on overlay's position changes through the crash:

```
1929-10-22  → CASH    (DJIA 298, down from the ~348 summer peak — days before the worst)
1930–1932   mostly flat through the collapse, with brief whipsaws
1932-06-24  → INVESTED (DJIA 58, near the bottom)
```

It also stepped aside for the **1937–38** recession (−2% vs B&H −35%) and trimmed the
**1946** post-war break. Regime by regime (total return over span / deepest drawdown within):

| regime | span | buy & hold | either-on | avg (½) |
|---|---|---:|---:|---:|
| 1920–21 post-WWI bear | 1.7 y | −29% / −29% | +2% / −1% | +2% / −1% |
| Roaring 20s bull | 8.2 y | +333% / −11% | +341% / −10% | +374% / −6% |
| **Crash + Depression** | 2.9 y | **−81% / −83%** | **+6% / −10%** | **+8% / −5%** |
| New Deal recovery | 4.7 y | +210% / −14% | +230% / −12% | +228% / −7% |
| 1937–38 recession | 1.2 y | −35% / −39% | −2% / −6% | +0% / −3% |
| WWII era | 7.8 y | +75% / −34% | +147% / −8% | +153% / −5% |
| Postwar bull | 6.6 y | +180% / −7% | +187% / −4% | +185% / −2% |

The whole edge is the same as on QQQ: it's concentrated in the deep bear. The Depression
is exactly the "trends hard, crashes hard" regime the filters exploit — consistent with the
finding (`STRATEGY.md §5`) that the overlay *adds* return on deep-crash assets.

## Caveats — read before trusting the precise numbers

- **The risk metrics are optimistic.** The source is a *monthly* line; interpolating it to
  daily strips out intra-month volatility (annualized vol reads ~3% vs a real ~15–20%).
  Smooth data lets the filters turn with surgical precision and **understates drawdowns**.
  The momentum filter's −2.9% maxDD is fantasy; the blend's −8…−14% is too clean. On *real*
  daily 1929–32 data — with its +12% / −12% single days and violent bear rallies — the
  overlay would have whipsawed more and drawn down deeper. A fair expectation is **tens of
  percent** (the real-daily QQQ either-on maxDD is −37%), still a *fraction* of B&H's −84%.
  The **trend-filter row is the robust anchor** because it's driven by the slow monthly
  trend the chart genuinely captures.
- **Price index, no dividends.** 1920–55 dividend yields averaged ~5%. On a total-return
  basis buy-and-hold's CAGR is closer to ~9–10% (not 4.4%); the overlay would also collect
  dividends while invested (~77% of the time) plus cash while out. Dividends lift *both* and
  narrow the CAGR gap — but leave the **drawdown** gap untouched.
- **Extraction is ±a few %** on level and **±1–2 months** on timing (3 px/month resolution,
  linear-monthly date mapping). Fine for "would it have dodged the Depression?"; not for
  day-level claims.
- Costs were far higher than 5 bps in that era, but the overlay trades ~1.5×/yr (either-on),
  so it barely matters.

## Reproduce

```bash
export PATH="$HOME/.juliaup/bin:$PATH"
julia --startup-file=no analysis/1920s/extract.jl    # PNG → monthly → business-day CSVs
julia --startup-file=no analysis/1920s/backtest.jl   # metrics, trade timeline, regime table
julia --startup-file=no analysis/1920s/plot.jl       # djia_blend_1920_1955.svg
```

*A historical backtest of mechanical rules on a hand-extracted index — not investment advice.
The point is qualitative: a trend/momentum overlay that sidesteps deep bears would have
turned the single worst episode in market history from a −84% wipeout into a setback.*
