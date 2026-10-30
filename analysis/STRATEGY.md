# QQQ Timing Overlay — the either-on blend

**A long/flat timing rule for QQQ that beats buy-and-hold's return over the full record
while cutting its worst drawdown by roughly half — at about three trades a year.** It
blends two filters that fail in *opposite* market regimes, so together they cover both.
Two variants:

- **either-on** *(the adopted default)* — in QQQ unless **both** filters say "out."
  Highest return, ~3 trades/yr, simple all-in/all-out.
- **avg (½-size)** — hold the *average* of the two filters (0 / 50 / 100 % invested).
  Smoothest ride, cushions every crash type, but ~12 trades/yr and fractional positions.

| (1999-03 → 2026-10, cash earns the 3-month T-bill, 5 bps/trade) | **either-on** | avg (½) | buy & hold |
|---|---:|---:|---:|
| CAGR | **14.8 %** | 12.9 % | 10.0 % |
| Growth of \$1 | **45×** | 29× | 14× |
| Worst drawdown | −38 % | **−32 %** | −83 % |
| Sharpe / Sortino / Calmar | 0.66 / 0.94 / 0.39 | **0.68 / 0.96 / 0.40** | 0.42 / 0.60 / 0.12 |
| Out-of-sample 2004+ CAGR / maxDD | **14.4 % / −33 %** | 12.4 % / −27 % | 14.2 % / −54 % |
| Trades per year | **~3** | ~12 | 0 |
| Worst 10-yr return | **+5 %/yr** | +4 %/yr | −8 %/yr |

*Signals are computed at the close and acted on the next session (no look-ahead); all P&L
is close-to-close. Cash earns the actual daily 3-month T-bill yield (it averaged ~2 % over
this span), which is also the Sharpe/Sortino hurdle — earlier versions of this table assumed
a flat 4 %, which flattered the edge by ~0.2–0.5 pp/yr (§3d). Full methodology and the
strategies that lost are in [README.md](README.md).*

**Where it stands** (run `julia analysis/signal.jl` for live status):

```
QQQ as of 2026-10-29:  close 715   SMA-50 725 > SMA-200 679   CCI(40) -61
  Trend filter (SMA 50/200 fast-reentry):    IN   since 2025-06-30
  Momentum filter (CCI(40) -100/0 + TMA):    OUT  since 2026-10-23
  ► either-on:  ▲ BUY / HOLD — 100% QQQ        ► avg: ◐ HALF — 50% QQQ
```

---

## 1. What the strategy is

The blend combines a **slow trend filter** and a **fast momentum filter**, each of which
is independently a long/flat QQQ overlay (details in §2). The point of blending is that
their weaknesses are complementary:

- the **trend filter** is blind to *sudden* crashes (a 200-day average can't turn in a
  month — it sat through COVID at −29 %), but it handles long grinding bears well;
- the **momentum filter** reacts fast to crashes (−13 % in COVID) but, on its own, can be
  chopped up in a multi-year saw-toothed bear.

So one is strong exactly where the other is weak. The two blend rules:

```
either-on  (adopted default):
  • Hold QQQ whenever EITHER filter is "in."
  • Move to cash only when BOTH filters are "out"; re-enter the moment either turns "in."
  • All-in or all-out. ~3 trades/yr.

avg (½-size):
  • QQQ weight = (trend_in + momentum_in) / 2  →  0 %, 50 %, or 100 %.
  • Half-sized when the two disagree. ~12 trades/yr, fractional positions.
```

`either-on` maximizes return and minimizes effort; `avg` trades some return and turnover
for the smoothest, most consistent drawdown control. They are risk-adjusted equivalents
(Calmar 0.39 vs 0.40, Sharpe 0.66 vs 0.68) — the choice is return-and-simplicity vs
smoothness (see §3).

---

## 2. The two component filters

### 2a. Trend filter — SMA 50/200 with fast re-entry

Two moving averages of QQQ's daily **close** define the regime:

```
  • Hold QQQ while SMA-50 > SMA-200 (uptrend).
  • Exit to cash on a "death cross" (SMA-50 < SMA-200).
  • After an exit, re-enter as soon as price closes back above its 50-day SMA
    — don't wait for the next golden cross.
  • Keep each position ~10 trading days before switching again (anti-whipsaw).
```

It reacts to the *long* trend, lagging turns by design so it isn't faked out by wiggles.
Standalone it returns ~13.7 %/yr at −36 % drawdown over 1999–2026 — the strongest single
filter we found, and the flagship of the earlier SMA study (`analysis/sma_study/`). Its
one structural blind spot is the fast crash.

### 2b. Momentum filter — CCI(40) −100/0 with a triangular-MA switch

The Commodity Channel Index (CCI) measures how far price sits from its recent mean. This
filter is a hysteresis band on CCI(40) with a regime-dependent exit:

```
  • Enter when CCI(40) rises above 0; exit when CCI(40) falls below -100 (a deep washout).
  • BUT when the 200-day TRIANGULAR moving average is sloping down (a confirmed,
    sustained downtrend) the exit tightens to CCI(40) < 0 — i.e. it falls back to the
    reactive "CCI>0" rule that survives long grinding bears.
  • No multi-day confirmation: act on the close (confirming exits only deepens drawdown).
```

`cci_band_tma_switch` in the toolkit. It reacts to momentum extremes, so it catches fast
crashes the trend filter misses. The **triangular-MA switch is what fixes the momentum
filter's old weakness** — a plain CCI band got chopped up in the 2000–02 dot-com grind
(full-sample drawdown −66 %); gating the exit on the slow triangular-MA slope cuts that to
−32 % while leaving the modern-era behavior essentially untouched. (Lineage: this evolved
from a simpler CCI(50) −120/−40 band; the sweep/walk-forward studies are in `analysis/tests/`.)

---

## 3. Performance across time scales

The blend's edge, like its components', is **concentrated in bear markets** — but because
it diversifies two crash-response styles, its drawdown control is both deeper and more
consistent than either filter alone.

![either-on & avg vs buy & hold](results/blend_finalists.svg)

### 3a. By regime — total return over the span / deepest drawdown within it

| regime | span | buy & hold | avg (½) | either-on |
|---|---|---:|---:|---:|
| Dot-com crash | 2000–2002 | −83 % / −83 % | **−26 % / −32 %** | −30 % / −36 % |
| Global financial crisis | 2007–2009 | −53 % / −54 % | **−26 % / −26 %** | −31 % / −33 % |
| 2009–2020 bull | 2009–2020 | **+820 %** / −23 % | +370 % / −17 % | +530 % / −20 % |
| COVID crash | Feb–Mar 2020 | −28 % / −29 % | **−20 % / −21 %** | −28 % / −29 % |
| 2022 bear | 2021–2022 | −36 % / −36 % | **−15 % / −16 %** | −21 % / −21 % |
| 2023–2026 recovery | 2022–2026 | +184 % / −23 % | +128 % / −15 % | +156 % / −23 % |

This is the structural fork between the two variants. **`avg` cushions every crash type,
including fast ones** (COVID −21 %, 2022 −16 %), because whenever one filter is caught off
guard the other has usually exited, so you're only half-exposed. **`either-on` keeps the
trend filter's fast-crash blind spot** (COVID −29 %, same as buy-and-hold) — the price it
pays for staying fully invested and out-returning everything else.

### 3b. Return consistency by holding period — annualized: worst / median / best

| horizon | buy & hold | avg (½) | either-on |
|---|---:|---:|---:|
| 1 year | −65 / +16 / +118 | −17 / +11 / +96 | −19 / +13 / +118 |
| 3 years | −39 / +14 / +34 | −9 / +11 / +31 | −11 / +13 / +34 |
| 5 years | −20 / +14 / +28 | −1 / +11 / +25 | −1 / +13 / +28 |
| 10 years | −8 / +13 / +21 | **+4** / +10 / +20 | **+5** / +12 / +22 |

Read the **worst** column: buy-and-hold has had losing 1-, 3-, 5- and 10-year stretches;
neither blend has had a losing 10-year window in 27 years, and their worst 5-year windows
were roughly flat (−1 %/yr) against buy-and-hold's −20 %/yr. The price is in the middle:
`either-on`'s medians run ~1 pp/yr below buy-and-hold's, `avg`'s ~3 pp. You eliminate the
catastrophic tail at a modest cost to the typical outcome.

### 3c. Win-rate vs buy & hold (rolling windows: return-beat % / shallower-drawdown %)

| | 1 mo | 1 yr | 5 yr |
|---|---:|---:|---:|
| avg (½) | 38 / 84 | 30 / **88** | 52 / **89** |
| either-on | 36 / 70 | 43 / 66 | **60** / 77 |

The dependable edge is **drawdown**: `avg` is shallower than buy-and-hold in ~90 % of
rolling 1–5-year windows. (Earlier versions of this doc said ~99 %: that figure credited cash
a flat 4 % through the zero-rate 2010s, which padded the half-in-cash blend through ordinary
corrections. With real T-bill yields it is ~90 % — still the most consistent risk reduction
tested, but not near-certain.) On raw return both mostly trail buy-and-hold in short windows
(the full-sample CAGR edge comes from side-stepping deep bears), but `either-on` pulls ahead
on return at longer horizons (60 % of 5-yr windows).

### 3d. Cash and interest rates

Every number here credits cash the **actual daily 3-month T-bill yield** (`data/rates/`;
0 – 6 %, averaging 2.0 % over 1999–2026, ~4 % today) and uses it as the Sharpe hurdle.
`analysis/rates_review.jl` compares that with the old flat 4 % and with 0 % cash:

- **The edge is crash avoidance, not interest.** Versus earning nothing in cash, T-bills add
  only ~0.3 pp/yr to `either-on` and ~0.6 pp/yr to `avg`. The flat-4 % assumption overstated
  the edge over buy-and-hold by ~0.2 pp/yr (`either-on`) and ~0.5 pp/yr (`avg`).
- **The edge was earned outside zero-rate periods.** On days when bills paid < 1 % (43 % of
  the record) `either-on` returned 15.6 %/yr vs buy-and-hold's 16.6 %; at 1–3 % it was 9.3 % vs
  3.8 %, and at ≥ 3 % 17.9 % vs 6.4 %. Partly coincidence of when the bears happened (2000–02
  and 2022 came at ≥ 1 % rates), partly structural: in a zero-rate world sitting out pays
  nothing. The weak spot is the 2010s ZIRP decade (`either-on` 13.6 %/yr vs 16.5 %).
- **Rates don't change the choice of variant**: `either-on` out-returns `avg` in every rate
  band; `avg` wins only on drawdown.
- QQQ prices here exclude dividends (~0.6 %/yr); adding them lifts every line by about that
  much and leaves the edges unchanged.

---

## 4. Robustness: walk-forward & out-of-sample

The blends have **no free parameters** — each is a fixed combination of two filters whose
own parameters were already walk-forward validated (the round numbers beat adaptive
re-optimization, both for the SMA filter and the CCI band; see `analysis/sma_study/` and
`analysis/tests/`). So the question for the blend is whether *committing* to it does as well
out-of-sample as adaptively re-choosing among the building blocks each year.

| OOS 2004–2026 | CAGR | maxDD | Calmar |
|---|---:|---:|---:|
| buy & hold | 14.2 % | −54 % | 0.27 |
| **either-on (fixed)** | **14.4 %** | −33 % | 0.44 |
| avg (fixed) | 12.4 % | **−27 %** | **0.46** |
| adaptive walk-forward (re-picks yearly) | 12.2 % | −27 % | 0.46 |

`analysis/blend_walkforward.jl`. Two findings:

1. **Committing to a fixed blend does as well as adaptively re-selecting** among {B&H, trend,
   momentum, avg, either-on} each year: fixed `avg` matches the adaptive selector's Calmar
   (0.46) with slightly more return, and fixed `either-on` trades a little Calmar (0.44) for
   ~2 pp/yr more return. The adaptive selector *only ever picks a blend* (avg 82 % / either-on
   18 % of days), never a standalone — the combination isn't overfit. (Under the old flat-4 %
   cash the fixed blends beat adaptive outright; real T-bills narrow that to a tie.)
2. **Out-of-sample (dot-com in training), `either-on` still edges buy-and-hold on return**
   (14.4 % vs 14.2 %) at ~60 % of its drawdown — a far better risk-adjusted ride.

---

## 5. Why QQQ specifically

We ran the underlying 50/200 filter on all eight ETFs in the dataset. The drawdown
protection is **universal**; the return boost is **not** — it only *added* return on
high-momentum, deep-crash assets (QQQ, energy, long bonds, TIPS) and *hurt* choppier indices
like small-caps (IWM −5.1 pp/yr) and the Dow (DIA −3.2 pp). QQQ is the standout equity beneficiary
precisely because it trends hard and crashes hard — exactly what these filters exploit. Using
*other* ETFs to confirm QQQ timing only reduced return; QQQ's own price already encodes the
regime. (`analysis/sma_study/cross_asset_analysis.jl`.)

---

## 6. How to execute

### Inputs & routine
You need QQQ's daily **OHLC** (the CCI uses high/low/close; everything else uses the close).
After the close, update the two filters — or just run `julia analysis/signal.jl`, which
prints the call and the breakdown — and apply your chosen blend rule:

- **either-on:** be in QQQ unless *both* filters are out. Move to cash only when the trend
  filter is in a death cross **and** the momentum filter has exited; re-enter when either
  flips back in. Exits are rare (~3/yr) — checking a few times a week is plenty.
- **avg:** set your QQQ weight to 0 / 50 / 100 % per how many filters are in. Changes
  cluster around turns (~12/yr); check daily in volatile periods.

Execute changes at the next session.

### Where to hold each state
- **Long:** QQQ, or **QQQM** (same index, lower 0.15 % fee). **Do not** use leveraged ETFs
  (TQQQ) — leverage amplifies whipsaw and breaks the risk profile.
- **Cash:** a money-market fund, T-bills, or HYSA — *not* idle 0 % cash. The backtest credits
  the actual 3-month T-bill yield; that interest is a small part of the edge (~0.3 pp/yr for
  `either-on`, ~0.6 for `avg`), and the drawdown protection doesn't depend on it.

### Account & tax
`either-on` realizes ~3 taxable events/year — quite tax-friendly. `avg` realizes ~12 plus
fractional rebalances — **strongly prefer a tax-advantaged account** (IRA / Roth / 401k) for
it. If you must run in a taxable account, `either-on` is the cleaner choice.

### Discipline & when it disappoints
Follow the rule **mechanically**; the hard moments are selling while the market still feels
fine and re-buying while it still feels scary. Expect to **trail buy-and-hold in sustained
bulls** (the 2010s) until the next deep bear, which is when the overlay earns its keep. And
know the variants' blind spots: **`either-on` will ride a fast crash down** (COVID −29 %) —
if a sudden plunge is your main fear, use `avg`, which cushions it (−21 %).

The per-strategy webpages — `results/blend_either_on.html` and `results/blend_avg.html`
(built by `analysis/build_blend_pages.jl`) — carry the full assessment and a live signal card.

---

## 7. Reproduce / monitor

```bash
export PATH="$HOME/.juliaup/bin:$PATH"          # julia lives in ~/.juliaup/bin
# ── production: the adopted blend (analysis/ root) ──
julia analysis/signal.jl                        # both blends' call + breakdown; pulls data only if >1h old & (market open or behind a session) — --fetch forces, --no-fetch offline
julia analysis/fetch_data.jl                    # explicit fetch from a free source (last 10 trading days)
julia analysis/blend_finalists_compare.jl       # the full side-by-side battery (either-on vs avg vs B&H)
julia analysis/blend_walkforward.jl             # §4 out-of-sample validation
julia analysis/rates_review.jl                  # §3d real T-bill cash vs flat 4% vs 0%, by era / rate regime
julia analysis/build_blend_pages.jl             # the per-strategy execution webpages
julia analysis/plot_blend_finalists.jl          # the §3 equity + drawdown chart
# ── component studies ──
julia analysis/sma_study/run_analysis.jl        # the SMA trend-filter study (sweep / rank / walk-forward)
julia analysis/tests/cci_tma_robustness.jl      # the momentum filter's lb / TMA-period sensitivity
julia analysis/tests/cci_tma_walkforward.jl     # the momentum filter's out-of-sample test
```

---

*This is a historical backtest of mechanical rules on one index — not investment advice or
a prediction. Past performance does not guarantee future results; QQQ's defining feature,
concentration in a handful of large-cap tech names, cuts both ways. The story is dominated by
the 2000s, and results depend on the cost/cash assumptions above.*
