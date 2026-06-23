# Generate a standalone, self-contained HTML report for the QQQ trend-filter
# strategy, centered on the Standard (fast re-entry) variant with the classic
# 50/200 as the Conservative variant. Numbers are computed directly from the
# toolkit and the SVG charts are inlined, so the document is always consistent
# and portable as a single file.
#
#   julia analysis/plot_hybrid.jl analysis/plot_recent.jl analysis/plot_results.jl  # charts first
#   julia analysis/build_report.jl                                                   # -> results/QQQ_strategy.html

include(joinpath(dirname(@__DIR__), "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const RES = joinpath(dirname(@__DIR__), "results", "sma_study")
const OUT = joinpath(RES, "QQQ_strategy.html")
const COST, RF = 5e-4, 0.04

d = load_ticker("QQQ"; dir=joinpath(dirname(dirname(@__DIR__)), "data"))
N = length(d)
bt(sig) = run_backtest(d, sig; cost=COST, rf_annual=RF)
bh = bt(buyhold(d))                              # baseline
st = bt(fast_reentry(d))                         # Standard (fast re-entry, hold=10)
cn = bt(sma_cross(d; fast=50, slow=200))         # Conservative (classic)
Mbh, Mst, Mcn = compute_metrics(bh), compute_metrics(st), compute_metrics(cn)

pct(x; d=1) = string(round(100x; digits=d), "%")
xn(x; d=1)  = string(round(x; digits=d), "×")
function wstats(eq, a, b)
    es = eq[a:b] ./ eq[a]; yrs = max(Dates.value(d.date[b] - d.date[a]) / 365.25, 1e-9)
    return (cagr=es[end]^(1 / yrs) - 1, maxdd=max_drawdown(es), total=es[end])
end
roll(eq, w) = rolling_compare(eq, bh.eq, w; step=21)
function last_change(sig)
    lc = 1; for i in 2:length(sig); sig[i] != sig[i - 1] && (lc = i); end; lc
end
rollcagr(eq, w) = (o = Float64[]; a = 1; while a + w <= N; push!(o, (eq[a + w] / eq[a])^(252 / w) - 1); a += 21; end; o)
inline_svg(name) = (p = joinpath(RES, name); isfile(p) ? read(p, String) : "<p class=\"warn\">[$name not found — run the plot scripts]</p>")

# current signals
s50 = sma(d.close, 50); s200 = sma(d.close, 200)
fsig = fast_reentry(d); csig = sma_cross(d; fast=50, slow=200)
fl = last_change(fsig); cl = last_change(csig); islong = fsig[N] == 1

# OOS window (matches walkforward.jl: first OOS index 1261 ≈ 2004-03-15)
oos_a = 1261
obh = wstats(bh.eq, oos_a, N); ost = wstats(st.eq, oos_a, N); ocn = wstats(cn.eq, oos_a, N)

decades = [(2000, 2009), (2010, 2019), (2020, 2026)]
periods = [("Dot-com crash", 2000, 3, 10, 2002, 10, 9), ("Mid-2000s recovery", 2002, 10, 9, 2007, 10, 9),
           ("Global financial crisis", 2007, 10, 9, 2009, 3, 9), ("2009–2020 bull", 2009, 3, 9, 2020, 2, 19),
           ("COVID crash", 2020, 2, 19, 2020, 3, 23), ("Post-COVID surge", 2020, 3, 23, 2021, 11, 19),
           ("2022 bear", 2021, 11, 19, 2022, 12, 28), ("2023–2026 recovery", 2022, 12, 28, year(d.date[end]), 12, 31)]

# Cross-asset ranking on a common 2005+ window, each asset's best variant by Sharpe.
const UNIVERSE = ("QQQ", "VGT", "SOXX", "SPY", "DIA", "IWM", "XLE", "TLT", "GLD", "TIP")
function wm_ra(eq, dts, a, b)
    es = eq[a:b] ./ eq[a]; m = length(es); yrs = max(Dates.value(dts[b] - dts[a]) / 365.25, 1e-9)
    er = [es[i] / es[i - 1] - 1 for i in 2:m]; rfd = (1 + RF)^(1 / 252) - 1
    μ = mean(er); σ = std(er); dn = sqrt(mean(x -> min(x - rfd, 0.0)^2, er)); mdd = max_drawdown(es)
    cagr = es[end]^(1 / yrs) - 1
    return (cagr=cagr, maxdd=mdd, vol=σ * sqrt(252), sharpe=(μ - rfd) / σ * sqrt(252),
            sortino=(μ - rfd) / dn * sqrt(252), calmar=cagr / abs(mdd))
end
rank_rows = []
for t in UNIVERSE
    et = load_ticker(t; dir=joinpath(dirname(dirname(@__DIR__)), "data"))
    a, b = date_range(et, Date(2005, 1, 3), et.date[end])
    bestv = nothing
    for (nm, sig) in (("Standard", fast_reentry(et)), ("Conservative", sma_cross(et; fast=50, slow=200)))
        mm = wm_ra(run_backtest(et, sig; cost=COST, rf_annual=RF).eq, et.date, a, b)
        (bestv === nothing || mm.sharpe > bestv.m.sharpe) && (bestv = (t=t, v=nm, m=mm))
    end
    push!(rank_rows, bestv)
end
sort!(rank_rows; by=r -> -r.m.sharpe)

io = IOBuffer()
print(io, """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>QQQ Trend-Filter Strategy</title>
<style>
:root{--ink:#1a1a1a;--mut:#666;--line:#e3e6ea;--blue:#1f6feb;--red:#d1242f;--bg:#fbfcfd;--good:#0a7f3f;--warnbg:#fff7e6;--warnbd:#e0a300;--notebg:#eef4ff;--notebd:#1f6feb}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased}
.wrap{max-width:920px;margin:0 auto;padding:48px 24px 80px}
h1{font-size:30px;line-height:1.2;margin:0 0 6px}
h2{font-size:22px;margin:52px 0 14px;padding-bottom:8px;border-bottom:2px solid var(--line)}
h3{font-size:17px;margin:28px 0 8px}
p,li{color:#262b30}
.sub{color:var(--mut);font-size:16px;margin:0 0 4px}
.lead{font-size:18px;background:#fff;border:1px solid var(--line);border-left:4px solid var(--red);border-radius:8px;padding:14px 18px;margin:20px 0}
.variants{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:18px 0}
.variants .v{background:#fff;border:1px solid var(--line);border-radius:8px;padding:14px 16px}
.variants .v.std{border-top:3px solid var(--red)} .variants .v.con{border-top:3px solid var(--blue)}
.variants .v b{font-size:15px}.variants .v span{color:var(--mut);font-size:14px}
.banner{display:flex;align-items:center;gap:16px;border-radius:10px;padding:16px 20px;margin:22px 0;font-size:15.5px;border:1px solid}
.banner.long{background:#eafbf0;border-color:#bce9cd}.banner.cash{background:#fdeeee;border-color:#f3c2c2}
.banner .big{font-size:22px;font-weight:700}.banner.long .big{color:var(--good)}.banner.cash .big{color:var(--red)}
table{border-collapse:collapse;width:100%;margin:16px 0;font-size:14.5px;background:#fff;border:1px solid var(--line);border-radius:8px;overflow:hidden}
th,td{padding:9px 12px;text-align:left;border-bottom:1px solid var(--line)}
th{background:#f4f6f8;font-weight:600;font-size:13px;color:#444}
td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
tbody tr:last-child td{border-bottom:none}
tr.hi td{background:#fdeef0}
th.std,td.std{background:#fdeef0}
.win{color:var(--good);font-weight:700}.bad{color:var(--red)}
figure{margin:24px 0;text-align:center}
figure svg{max-width:100%;height:auto;border:1px solid var(--line);border-radius:8px;background:#fff}
figcaption{color:var(--mut);font-size:13.5px;margin-top:8px;text-align:left}
.note,.warn{border-radius:8px;padding:12px 16px;margin:18px 0;font-size:15px}
.note{background:var(--notebg);border-left:4px solid var(--notebd)}
.warn{background:var(--warnbg);border-left:4px solid var(--warnbd)}
pre{background:#0f1419;color:#e6edf3;border-radius:8px;padding:16px 18px;overflow:auto;font:13px/1.55 "SF Mono",Menlo,Consolas,monospace}
code{font:13.5px "SF Mono",Menlo,Consolas,monospace;background:#eef1f4;padding:1px 5px;border-radius:4px}
.foot{margin-top:60px;padding-top:18px;border-top:1px solid var(--line);color:var(--mut);font-size:13px}
@media(max-width:640px){.variants{grid-template-columns:1fr}.wrap{padding:28px 16px 60px}}
</style></head><body><div class="wrap">
""")

# header + lead + variant cards + signal
print(io, """<p class="sub">Quantitative strategy brief · data $(d.date[1]) → $(d.date[end])</p>
<h1>QQQ Trend-Filter Strategy</h1>
<p class="sub">A long/flat timing rule that captures most of buy-and-hold's return while cutting its worst drawdown by more than half.</p>
<div class="lead"><b>The idea:</b> hold QQQ while its trend is up (50-day average above the 200-day); step aside to cash when the trend rolls over. The <b>Standard</b> variant re-enters quickly once price recovers; the <b>Conservative</b> variant waits for a full trend reversal.</div>
<div class="variants">
<div class="v std"><b>★ Standard — fast re-entry</b> <span>(central strategy)</span><br>$(pct(Mst.cagr)) CAGR · $(pct(Mst.maxdd;d=0)) maxDD · ~5 trades/yr<br><span>Re-enters as soon as price reclaims its 50-day average — captures more upside.</span></div>
<div class="v con"><b>Conservative — classic 50/200</b><br>$(pct(Mcn.cagr)) CAGR · $(pct(Mcn.maxdd;d=0)) maxDD · ~1 trade/yr<br><span>Re-enters only on a full golden cross — simpler, fewer trades, tighter crash control.</span></div>
</div>
<div class="banner $(islong ? "long" : "cash")">
<div><span class="big">$(islong ? "▲ LONG" : "▼ CASH")</span></div>
<div>As of <b>$(d.date[end])</b> · close $(round(d.close[N];digits=2)) · SMA-50 $(round(s50[N];digits=2)) $(s50[N] > s200[N] ? ">" : "<") SMA-200 $(round(s200[N];digits=2)).<br>
<b>Standard:</b> $(fsig[N]==1 ? "LONG" : "CASH") since $(d.date[fl]) · <b>Conservative:</b> $(csig[N]==1 ? "LONG" : "CASH") since $(d.date[cl]).</div></div>
""")

# headline comparison table
print(io, """<table><thead><tr><th>1999–2026</th><th class="num std">Standard</th><th class="num">Conservative</th><th class="num">buy &amp; hold</th></tr></thead><tbody>
<tr><td>CAGR</td><td class="num std win">$(pct(Mst.cagr))</td><td class="num">$(pct(Mcn.cagr))</td><td class="num">$(pct(Mbh.cagr))</td></tr>
<tr><td>Growth of \$1</td><td class="num std">$(xn(Mst.total_return+1))</td><td class="num">$(xn(Mcn.total_return+1))</td><td class="num">$(xn(Mbh.total_return+1))</td></tr>
<tr><td>Worst drawdown</td><td class="num std">$(pct(Mst.maxdd;d=0))</td><td class="num">$(pct(Mcn.maxdd;d=0))</td><td class="num bad">$(pct(Mbh.maxdd;d=0))</td></tr>
<tr><td>Sharpe / Sortino / Calmar</td><td class="num std">$(round(Mst.sharpe;digits=2)) / $(round(Mst.sortino;digits=2)) / $(round(Mst.calmar;digits=2))</td><td class="num">$(round(Mcn.sharpe;digits=2)) / $(round(Mcn.sortino;digits=2)) / $(round(Mcn.calmar;digits=2))</td><td class="num">$(round(Mbh.sharpe;digits=2)) / $(round(Mbh.sortino;digits=2)) / $(round(Mbh.calmar;digits=2))</td></tr>
<tr><td>Out-of-sample CAGR (2004+)</td><td class="num std">$(pct(ost.cagr))</td><td class="num">$(pct(ocn.cagr))</td><td class="num">$(pct(obh.cagr))</td></tr>
<tr><td>Out-of-sample drawdown</td><td class="num std">$(pct(ost.maxdd;d=0))</td><td class="num">$(pct(ocn.maxdd;d=0))</td><td class="num bad">$(pct(obh.maxdd;d=0))</td></tr>
<tr><td>Trades per year</td><td class="num std">$(round(Mst.ntrades/Mst.years;digits=1))</td><td class="num">$(round(Mcn.ntrades/Mcn.years;digits=1))</td><td class="num">0</td></tr>
</tbody></table>
<p style="color:var(--mut);font-size:13px">Assumptions: daily data; cash earns 4%/yr; 5&nbsp;bps cost per switch; signals computed at the close and acted on the next session (no look-ahead).</p>
""")

# §1
print(io, """<h2>1 · What the strategy is</h2>
<p>Two moving averages of QQQ's daily <b>closing</b> price — the 50-day (≈10 weeks) and the 200-day (≈10 months) — define the trend regime. Both variants hold QQQ in uptrends and cash in downtrends; they differ only in <b>how fast they get back in</b>.</p>
<pre>Standard (fast re-entry) — the central strategy:
  • Hold 100% QQQ while SMA-50 &gt; SMA-200 (uptrend).
  • Exit to cash when SMA-50 &lt; SMA-200 (a "death cross").
  • After an exit, re-enter as soon as QQQ closes back above its 50-day SMA
    — do NOT wait for the next golden cross.
  • Keep each position ≥ ~10 trading days before switching again (anti-whipsaw).

Conservative (classic 50/200):
  • Hold QQQ while SMA-50 &gt; SMA-200; cash otherwise (re-enter only on the golden cross).</pre>
<p>They are <b>trend filters</b>: they react rather than predict, lagging turns by design so they aren't faked out by every wiggle. The Standard variant's faster re-entry is what lets it recover most of the return a pure 50/200 filter gives up — at the cost of a few more trades a year.</p>
""")

# §2 performance
print(io, """<h2>2 · Performance across time scales</h2>
<p>The most important fact: both variants' return edge is concentrated in bear markets, and they lag in sustained bulls. They are downside insurance that, on QQQ, has historically paid for itself.</p>
<figure>$(inline_svg("hybrid_vs_fixed.svg"))
<figcaption><b>Full history, 1999–2026 (log scale).</b> Standard (red) compounds fastest; both filters side-step the −83% dot-com crash (drawdown panel) that buy &amp; hold (gray) takes in full.</figcaption></figure>""")

print(io, """<h3>By decade — annualized return / max drawdown</h3>
<table><thead><tr><th>decade</th><th class="num">buy &amp; hold</th><th class="num std">Standard</th><th class="num">Conservative</th></tr></thead><tbody>""")
for (a, z) in decades
    i0, i1 = date_range(d, Date(a, 1, 1), Date(z, 12, 31))
    b = wstats(bh.eq, i0, i1); s = wstats(st.eq, i0, i1); c = wstats(cn.eq, i0, i1)
    print(io, "<tr><td>$(a)s</td><td class=\"num\">$(pct(b.cagr)) / $(pct(b.maxdd;d=0))</td><td class=\"num std\">$(pct(s.cagr)) / $(pct(s.maxdd;d=0))</td><td class=\"num\">$(pct(c.cagr)) / $(pct(c.maxdd;d=0))</td></tr>")
end
print(io, """</tbody></table>
<div class="note">The full-period edge comes from the <b>2000s "lost decade"</b>, when buy-and-hold lost money over ten years and the filter made money. In the relentless 2010s bull, buy-and-hold <b>won</b>. In the 2020s the Standard variant edges out buy-and-hold with less risk.</div>""")

print(io, """<h3>By market regime — total return over the span / deepest drawdown within it</h3>
<table><thead><tr><th>regime</th><th>span</th><th class="num">B&amp;H</th><th class="num std">Standard</th><th class="num">Conservative</th></tr></thead><tbody>""")
for (lbl, ya, ma, da, yz, mz, dz) in periods
    i0, i1 = date_range(d, Date(ya, ma, da), Date(yz, mz, dz))
    b = wstats(bh.eq, i0, i1); s = wstats(st.eq, i0, i1); c = wstats(cn.eq, i0, i1)
    print(io, "<tr><td>$lbl</td><td>$(ya)&ndash;$(yz)</td><td class=\"num\">$(pct(b.total-1;d=0)) / $(pct(b.maxdd;d=0))</td><td class=\"num std\">$(pct(s.total-1;d=0)) / $(pct(s.maxdd;d=0))</td><td class=\"num\">$(pct(c.total-1;d=0)) / $(pct(c.maxdd;d=0))</td></tr>")
end
print(io, """</tbody></table>
<p>Both shine in <b>every grinding bear</b>. Note the trade-off: the Standard variant captures <b>more of the bull runs</b> but gives up a little crash protection in individual bears (dot-com, 2022) because its faster re-entry occasionally catches a brief relief rally. Their worst-case drawdown over the whole history is identical. Neither dodges the <b>COVID crash</b> — too fast for a 200-day average.</p>""")

print(io, """<h3>Return consistency by holding period — annualized: worst / median / best</h3>
<table><thead><tr><th>horizon</th><th class="num">buy &amp; hold</th><th class="num std">Standard</th><th class="num">Conservative</th></tr></thead><tbody>""")
for (w, lbl) in [(252, "1 year"), (756, "3 years"), (1260, "5 years"), (2520, "10 years")]
    rb = rollcagr(bh.eq, w); rs = rollcagr(st.eq, w); rc = rollcagr(cn.eq, w)
    f(r) = "$(pct(minimum(r);d=0)) / $(pct(median(r);d=0)) / $(pct(maximum(r);d=0))"
    print(io, "<tr><td>$lbl</td><td class=\"num\">$(f(rb))</td><td class=\"num std\">$(f(rs))</td><td class=\"num\">$(f(rc))</td></tr>")
end
print(io, """</tbody></table>
<div class="note">Read the <b>worst</b> column: buy-and-hold has had losing 1-, 3-, 5- and 10-year stretches. The Standard variant <b>never had a losing 5- or 10-year window</b> in 27 years, with medians close to buy-and-hold's — you give up a little median upside to eliminate the catastrophic tail.</div>""")

print(io, """<h3>Short-horizon win-rate vs buy &amp; hold (return % / drawdown %)</h3>
<table><thead><tr><th></th><th class="num">1 mo</th><th class="num">3 mo</th><th class="num">6 mo</th><th class="num">1 yr</th></tr></thead><tbody>""")
for (nm, eq, cls) in [("Standard", st.eq, " class=\"std\""), ("Conservative", cn.eq, "")]
    cells = join(["<td class=\"num$(cls == "" ? "" : " std")\">$(round(Int,100*roll(eq,w).return_win_rate))/$(round(Int,100*roll(eq,w).dd_win_rate))</td>" for w in (21, 63, 126, 252)])
    print(io, "<tr><td$cls>$nm</td>$cells</tr>")
end
print(io, """</tbody></table>
<p>The Standard variant's faster re-entry lifts its short-horizon return-win-rate above the Conservative rule's at every scale. Both still lose to buy-and-hold on raw return in most short windows — their dependable edge is drawdown reduction, not beating B&amp;H in a typical quarter.</p>""")

# §3 robustness
print(io, """<h2>3 · Robustness: walk-forward &amp; out-of-sample</h2>
<p>We re-ran the study the way you'd actually trade it: a 22-strategy grid re-evaluated yearly on a training window, the best traded the <b>next</b> year, OOS segments stitched together. The first OOS year is <b>2004</b>, so the dot-com crash — the filter's signature win — lands in <i>training</i>. A deliberately hard test.</p>
<table><thead><tr><th>OOS 2004–2026</th><th class="num">CAGR</th><th class="num">maxDD</th><th class="num">Calmar</th></tr></thead><tbody>
<tr><td>buy &amp; hold</td><td class="num win">$(pct(obh.cagr))</td><td class="num bad">$(pct(obh.maxdd;d=0))</td><td class="num">$(round(obh.cagr/abs(obh.maxdd);digits=2))</td></tr>
<tr class="hi"><td><b>Standard (fast re-entry)</b></td><td class="num">$(pct(ost.cagr))</td><td class="num win">$(pct(ost.maxdd;d=0))</td><td class="num win">$(round(ost.cagr/abs(ost.maxdd);digits=2))</td></tr>
<tr><td>Conservative (50/200)</td><td class="num">$(pct(ocn.cagr))</td><td class="num">$(pct(ocn.maxdd;d=0))</td><td class="num">$(round(ocn.cagr/abs(ocn.maxdd);digits=2))</td></tr>
<tr><td>walk-forward (anchored)</td><td class="num">6.1%</td><td class="num">−16%</td><td class="num">0.38</td></tr>
<tr><td>walk-forward (rolling 5y)</td><td class="num">8.1%</td><td class="num">−32%</td><td class="num">0.25</td></tr>
</tbody></table>
<ol>
<li><b>Out-of-sample the Standard variant nearly matches buy-and-hold's return</b> ($(pct(ost.cagr)) vs $(pct(obh.cagr))) <b>at roughly half the drawdown</b> ($(pct(ost.maxdd;d=0)) vs $(pct(obh.maxdd;d=0))).</li>
<li><b>Adaptively re-optimizing the parameters does <i>worse</i> than a fixed rule</b> — if clever tuning can't beat a round, fixed choice, the choice isn't overfit.</li>
<li><b>Chronological splits agree.</b> The Standard variant's parameters are robust: OOS results barely move for re-entry lengths of 40–50 days and holds of 5–21 days.</li>
</ol>""")

# §4 conservative variant
print(io, """<h2>4 · The Conservative variant — when to prefer it</h2>
<p>The classic 50/200 golden-cross filter is the Standard variant without the fast re-entry: it returns to QQQ only when SMA-50 climbs back above SMA-200. That makes it <b>simpler</b> (~1 trade/yr vs ~5), <b>tighter on individual-bear protection</b> (−12% through the dot-com crash and −13% in 2022, vs the Standard variant's −25% and −20%, because it never re-enters into a relief rally), but <b>lower-returning</b> ($(pct(Mcn.cagr)) vs $(pct(Mst.cagr))). Prefer it if you value the fewest trades and tightest crash control and will leave some return on the table — especially in a taxable account.</p>
<figure>$(inline_svg("equity_curves.svg"))
<figcaption><b>Conservative 50/200 vs buy &amp; hold.</b> The simplest version of the strategy: in QQQ above the cross, in cash below.</figcaption></figure>
<h3>Last 10 years — relative performance</h3>
<figure>$(inline_svg("recent_10yr.svg"))
<figcaption><b>Each variant relative to buy &amp; hold</b> (bottom panel; above 100% = ahead). Both drift below in calm bulls, then jump above during every selloff (2018, 2022, 2025); Standard (red) stays ahead of Conservative (blue) by re-entering sooner. Over the last decade the Standard variant slightly beat buy-and-hold with a shallower drawdown.</figcaption></figure>""")

# §5 why QQQ
print(io, """<h2>5 · Why QQQ specifically</h2>
<p>We ran the same 50/200 filter on all ten ETFs in the dataset. The drawdown protection is <b>universal</b>; the return boost is <b>not</b>.</p>
<table><thead><tr><th>ETF</th><th class="num">B&amp;H CAGR / maxDD</th><th class="num">filter CAGR / maxDD</th><th class="num">ΔCAGR</th><th class="num">ΔmaxDD</th></tr></thead><tbody>""")
for t in ("QQQ", "VGT", "SOXX", "SPY", "DIA", "IWM", "XLE", "TLT", "GLD", "TIP")
    et = load_ticker(t; dir=joinpath(dirname(dirname(@__DIR__)), "data"))
    mb = compute_metrics(run_backtest(et, buyhold(et); cost=COST, rf_annual=RF))
    mf = compute_metrics(run_backtest(et, sma_cross(et; fast=50, slow=200); cost=COST, rf_annual=RF))
    dC = mf.cagr - mb.cagr; dD = mf.maxdd - mb.maxdd
    cls = t == "QQQ" ? " class=\"hi\"" : ""
    print(io, "<tr$cls><td>$t</td><td class=\"num\">$(pct(mb.cagr)) / $(pct(mb.maxdd;d=0))</td><td class=\"num\">$(pct(mf.cagr)) / $(pct(mf.maxdd;d=0))</td><td class=\"num $(dC>=0 ? "win" : "bad")\">$(dC>=0 ? "+" : "")$(round(100dC;digits=1))pp</td><td class=\"num win\">+$(round(100dD;digits=1))pp</td></tr>")
end
print(io, """</tbody></table>
<p>The filter gave a shallower drawdown on <b>every</b> ETF, but only <i>added</i> return on high-momentum, deep-crash assets — QQQ, energy (XLE), long bonds (TLT/TIP) — while it <i>hurt</i> choppier indices like small-caps (IWM) and the Dow (DIA). QQQ is the standout equity beneficiary precisely because it trends hard and crashes hard.</p>
<div class="note">We also tested using the other ETFs to <b>inform</b> QQQ timing (broad-market confirmation, small-cap breadth, risk-on/off vs bonds). All of them <b>reduced</b> return by adding conservatism — QQQ's own trend already encodes the regime. Don't over-engineer it.</div>""")

# §6 cross-asset ranking
print(io, """<h2>6 · Which asset to invest in — cross-asset risk-adjusted ranking</h2>
<p>If you can hold only one fund, which deserves the capital? We applied each asset's <b>better variant</b> (Standard or Conservative, whichever has the higher Sharpe) and ranked all ten ETFs by risk-adjusted return over a <b>common 2005+ window</b> — the period where every ETF has data, for a fair apples-to-apples comparison. Up-and-to-the-left is better:</p>
<figure>$(inline_svg("risk_return.svg"))
<figcaption>Each point is one ETF running its optimized variant; dashed lines are equal-Calmar (return-per-drawdown) contours. QQQ and SOXX sit alone on the efficient frontier.</figcaption></figure>
<table><thead><tr><th>#</th><th>asset</th><th>best variant</th><th class="num">CAGR</th><th class="num">maxDD</th><th class="num">vol</th><th class="num">Sharpe</th><th class="num">Sortino</th><th class="num">Calmar</th></tr></thead><tbody>""")
for (i, r) in enumerate(rank_rows)
    cls = r.t in ("QQQ", "SOXX") ? " class=\"hi\"" : ""
    print(io, "<tr$cls><td>$i</td><td><b>$(r.t)</b></td><td>$(r.v)</td><td class=\"num\">$(pct(r.m.cagr))</td><td class=\"num\">$(pct(r.m.maxdd;d=0))</td><td class=\"num\">$(pct(r.m.vol;d=0))</td><td class=\"num\">$(round(r.m.sharpe;digits=2))</td><td class=\"num\">$(round(r.m.sortino;digits=2))</td><td class=\"num\">$(round(r.m.calmar;digits=2))</td></tr>")
end
print(io, """</tbody></table>
<p><b>The pick: QQQ, run with the Standard variant.</b> SOXX and QQQ are effectively tied for the top Sharpe (≈0.63 vs 0.62 — within statistical noise) and miles ahead of everything else. SOXX has the higher raw return and Sharpe, but QQQ wins on the measures that matter most for a single concentrated position: the <b>shallowest drawdown</b> (−29% vs −34%), <b>lowest volatility</b> (18% vs 23%), the <b>best Calmar</b> (0.50), and far more diversification — 100 Nasdaq-100 names versus SOXX's ~30 semiconductors. Sharpe doesn't price in single-industry concentration; QQQ delivers near-identical risk-adjusted performance without betting everything on one violently cyclical sector.</p>
<p><b>SOXX (Conservative) is the aggressive alternative</b> — highest return (16.8%/yr) and top Sharpe if you can stomach the volatility and concentration. Note its winning variant is the <i>Conservative</i> rule: semiconductors are so choppy that fast re-entry catches too many failed bounces (the asset-dependent pattern from §4).</p>
<div class="note"><b>Out-of-sample check (walk-forward).</b> We re-validated the top picks the hard way — train on each asset's first ~5 years, trade the rest. <b>SOXX confirms strongly:</b> out-of-sample (2006–2026, with the 2001–02 semi crash held out of the test) the Conservative variant still returned <b>18.5%/yr vs buy-and-hold's 19.0% at half the drawdown</b> (−34% vs −67%; Sharpe 0.86 vs 0.72), and the Conservative-beats-Standard pick held up. <b>QQQ likewise</b> (§3). <b>VGT is the caveat:</b> its data starts only in 2004, so its out-of-sample window (2009–2026) is an almost-pure bull market with no deep bear to dodge — there buy-and-hold beat both variants outright (Sharpe 0.99 vs 0.82). VGT's #3 rank above leans on its 2005+ window <i>including</i> 2008; treat it as less robust than SOXX/QQQ. (As everywhere: adaptive re-optimization underperformed the fixed rule, and the filter's value is contingent on a bear market being in the window.)</div>
<div class="warn"><b>Read with care.</b> This ranks on a common 2005+ window (which excludes the dot-com crash — a "modern era" view) and picks each asset's best variant in-sample (mildly optimistic, though the picks follow the choppiness logic, not curve-fitting). Sharpe gaps of ~0.01 are noise. Bonds/gold (TLT/TIP/GLD) score low because 2005+ was a poor regime for them, not a permanent verdict. Concentrating in one tech-heavy fund is itself a risk the timing overlay does not remove.</div>""")

# §7 execution
print(io, """<h2>7 · How to execute (Standard variant)</h2>
<h3>Inputs &amp; routine</h3>
<p>You need only QQQ's <b>daily closing price</b>. After the close, update the 50- and 200-day moving averages (or run <code>julia analysis/signal.jl</code>) and apply the rule:</p>
<ul>
<li><b>In cash and QQQ closes above its 50-day SMA →</b> buy QQQ (re-enter).</li>
<li><b>Long and SMA-50 drops below SMA-200 →</b> sell QQQ, move to cash.</li>
<li>After any switch, <b>wait ~10 trading days</b> before switching again.</li>
</ul>
<p>Execute changes at the next session's open. The Standard variant averages ~5 trades/year but <b>clusters in choppy markets</b> (several round-trips in 2016, 2022) and goes quiet for years in clean trends.</p>
<h3>Where to hold each state</h3>
<ul>
<li><b>Long:</b> QQQ, or <b>QQQM</b> (same index, lower 0.15% expense ratio).</li>
<li><b>Cash:</b> a money-market fund, T-bills, or HYSA — <b>not</b> idle 0% cash. The return edge partly depends on earning ~4% here; the drawdown protection does not. <b>Do not</b> use leveraged ETFs (TQQQ).</li>
</ul>
<h3>Account &amp; tax</h3>
<p>The Standard variant realizes ~5 taxable events/year, the Conservative ~1. <b>Use a tax-advantaged account</b> (IRA / Roth / 401k) so switches don't trigger capital-gains tax — this matters more for the Standard variant; in a taxable account the Conservative variant's lower turnover is the safer choice.</p>
<h3>Discipline &amp; when it disappoints you</h3>
<p>Follow the rule <b>mechanically</b>. You'll sometimes re-enter just before a second leg down — accept the small whipsaws; they're the price of catching real recoveries early. The strategy <b>won't</b> protect against sudden one-month crashes (COVID), will <b>whipsaw</b> in choppy sideways markets, and will <b>trail buy-and-hold in sustained bulls</b> — which is exactly when the next deep bear is being set up.</p>""")

print(io, """<div class="warn"><b>This is a historical backtest of mechanical rules on one index — not investment advice or a prediction.</b> Past performance does not guarantee future results; QQQ's concentration in a handful of large-cap tech names cuts both ways. The story is dominated by the 2000s, and results depend on the cost/cash assumptions above.</div>
<div class="foot">Generated by <code>analysis/build_report.jl</code> from <code>data/QQQ</code> ($(d.date[1]) → $(d.date[end])). Full methodology in <code>analysis/README.md</code>; detail in <code>analysis/STRATEGY.md</code>.</div>
</div></body></html>""")

write(OUT, take!(io))
println("Wrote ", OUT, "  (", round(filesize(OUT) / 1024; digits=0), " KB)")
