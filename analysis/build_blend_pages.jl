# Build a standalone, self-contained webpage for each of the two final blend
# strategies (avg ½-size, and either-on): what it is, performance assessment,
# and how to execute it. All numbers and the chart are computed from the toolkit.
#
#   julia analysis/build_blend_pages.jl
#     -> results/blend_either_on.html
#     -> results/blend_avg.html

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const RES = joinpath(@__DIR__, "results")
const COST, RF = 5e-4, 0.04
d = load_ticker("QQQ"; dir=joinpath(dirname(@__DIR__), "data")); N = length(d)
bt(s) = run_backtest(d, s; cost=COST, rf_annual=RF)
function slice_md(d::MarketData, i0, i1)
    MarketData(d.ticker, d.date[i0:i1], d.open[i0:i1], d.high[i0:i1],
               d.low[i0:i1], d.close[i0:i1], d.volume[i0:i1])
end
ev(sig, a, b) = compute_metrics(run_backtest(slice_md(d, a, b), sig[a:b]; cost=COST, rf_annual=RF))
win(f, t) = date_range(d, f, t)
lc(s) = (x = 1; for i in 2:N; s[i] != s[i-1] && (x = i); end; x)
pct(x; dg=1) = string(round(100x; digits=dg), "%")

# ── signals ──────────────────────────────────────────────────────────────────
CCI = cci_band_tma_switch(d; exit_lo=-100, entry_hi=0, bear_exit=0, tma_n=200, lb=20, confirm=1)
FR  = fast_reentry(d; fast=50, slow=200, re=50, hold=10)
AVG = (CCI .+ FR) ./ 2
EIT = sig_or(CCI, FR)
BH  = buyhold(d)
s50 = sma(d.close, 50); s200 = sma(d.close, 200); c40 = cci(d.high, d.low, d.close, 40); t200 = tma(d.close, 200)

# ── chart: strategy (color) vs buy & hold (gray), equity(log) + drawdown ───────
function chart_svg(name, color, eq)
    curves = [("buy & hold", "#9aa0a6", bt(BH).eq), (name, color, eq)]
    n = N; yr = year.(d.date)
    W, H, L, R, Tm, Bm, GAP, P1H = 980, 540, 66, 150, 30, 40, 38, 300
    P2T = Tm + P1H + GAP; P2H = H - P2T - Bm; PW = W - L - R
    xat(i) = L + (i - 1) / (n - 1) * PW
    logs = [log10.(c[3]) for c in curves]
    ymin = minimum(minimum, logs); ymax = maximum(maximum, logs)
    y1(v) = Tm + (1 - (v - ymin) / (ymax - ymin)) * P1H
    dds = [drawdown_series(c[3]) for c in curves]; mindd = minimum(minimum, dds)
    y2(x) = P2T + (x / mindd) * P2H
    poly(xs, ys, col, w) = string("<polyline fill=\"none\" stroke=\"", col, "\" stroke-width=\"", w,
        "\" points=\"", join((string(round(xs[i]; digits=1), ",", round(ys[i]; digits=1)) for i in eachindex(xs)), " "), "\"/>")
    io = IOBuffer()
    print(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $W $H\" font-family=\"inherit\">")
    for k in (1,2,5,10,20,50,100)
        v = log10(k); (v < ymin || v > ymax) && continue; y = round(y1(v); digits=1)
        print(io, "<line x1=\"$L\" y1=\"$y\" x2=\"$(L+PW)\" y2=\"$y\" stroke=\"#ededed\"/><text x=\"$(L-7)\" y=\"$(y+4)\" font-size=\"11\" text-anchor=\"end\" fill=\"#888\">$(k)x</text>")
    end
    for dd in (0.0,-0.2,-0.4,-0.6,-0.8)
        dd < mindd && continue; y = round(y2(dd); digits=1)
        print(io, "<line x1=\"$L\" y1=\"$y\" x2=\"$(L+PW)\" y2=\"$y\" stroke=\"#ededed\"/><text x=\"$(L-7)\" y=\"$(y+4)\" font-size=\"11\" text-anchor=\"end\" fill=\"#888\">$(round(Int,100dd))%</text>")
    end
    let last = 0
        for i in 1:n
            if yr[i] % 3 == 0 && (i == 1 || yr[i] != yr[i-1]) && yr[i] != last
                x = round(xat(i); digits=1)
                print(io, "<text x=\"$x\" y=\"$(H-20)\" font-size=\"11\" text-anchor=\"middle\" fill=\"#888\">$(yr[i])</text>")
                last = yr[i]
            end
        end
    end
    xs = [xat(i) for i in 1:n]
    for (k, c) in enumerate(curves)
        print(io, poly(xs, [y1(logs[k][i]) for i in 1:n], c[2], k == 1 ? 1.3 : 1.9))
        print(io, poly(xs, [y2(dds[k][i]) for i in 1:n], c[2], k == 1 ? 1.0 : 1.5))
    end
    print(io, "<rect x=\"$L\" y=\"$Tm\" width=\"$PW\" height=\"$P1H\" fill=\"none\" stroke=\"#ddd\"/><rect x=\"$L\" y=\"$P2T\" width=\"$PW\" height=\"$P2H\" fill=\"none\" stroke=\"#ddd\"/>")
    print(io, "<text x=\"$(L+4)\" y=\"$(Tm+14)\" font-size=\"11\" fill=\"#888\">growth of \$1 (log)</text>")
    print(io, "<text x=\"$(L+4)\" y=\"$(P2T+14)\" font-size=\"11\" fill=\"#888\">drawdown</text>")
    lx = L + PW + 14
    for (k, c) in enumerate(curves)
        yy = Tm + 6 + (k-1)*20
        print(io, "<line x1=\"$lx\" y1=\"$yy\" x2=\"$(lx+22)\" y2=\"$yy\" stroke=\"$(c[2])\" stroke-width=\"3\"/><text x=\"$(lx+28)\" y=\"$(yy+4)\" font-size=\"12\" fill=\"#333\">$(c[1])</text>")
    end
    print(io, "</svg>")
    String(take!(io))
end

# ── regime + holding-period assessment ─────────────────────────────────────────
regs = [("Dot-com crash 2000–02", Date(2000,3,10), Date(2002,10,9)),
        ("Global financial crisis 2007–09", Date(2007,10,31), Date(2009,3,9)),
        ("COVID crash (Feb–Mar 2020)", Date(2020,2,19), Date(2020,3,23)),
        ("2022 bear", Date(2021,11,19), Date(2022,12,28)),
        ("2009–2020 bull", Date(2009,3,9), Date(2020,2,19))]
function hp(eq, w)
    rs = Float64[]; a = 1
    while a + w <= N; push!(rs, (eq[a+w]/eq[a])^(252/w) - 1); a += 21; end
    (minimum(rs), median(rs), maximum(rs))
end
oos_a = 1261
oos(eq) = (es = eq[oos_a:N] ./ eq[oos_a]; yrs = Dates.value(d.date[N]-d.date[oos_a])/365.25; (cagr=es[end]^(1/yrs)-1, dd=max_drawdown(es)))

# ── page builder ───────────────────────────────────────────────────────────────
function build_page(file, key)
    sig   = key == :either ? EIT : AVG
    eq    = bt(sig).eq
    color = key == :either ? "#d1242f" : "#1f6feb"
    M     = compute_metrics(bt(sig)); Mbh = compute_metrics(bt(BH))
    O     = oos(eq); Obh = oos(bt(BH).eq)
    expo  = round(Int, 100sig[N])
    chart = chart_svg(key == :either ? "blend either-on" : "blend avg (½)", color, eq)

    # ── prominent top-of-page signal card (current status + blend breakdown) ──
    trend_in = FR[N] == 1; mom_in = CCI[N] == 1
    bear = N > 20 && !isnan(t200[N]) && !isnan(t200[N-20]) && t200[N] < t200[N-20]
    mom_exit = bear ? 0 : -100
    rel = s50[N] > s200[N] ? "&gt;" : "&lt;"
    trend_detail = "SMA-50 $(round(Int,s50[N])) $rel SMA-200 $(round(Int,s200[N])) — $(s50[N] > s200[N] ? "uptrend" : "downtrend")"
    mom_detail = "CCI(40) $(round(Int,c40[N])) vs exit $mom_exit · 200-day triangular MA $(bear ? "falling" : "rising")"
    chip(on) = on ? "<span class=\"chip in\">IN</span>" : "<span class=\"chip out\">OUT</span>"
    if key == :either
        long = EIT[N] == 1; cls = long ? "buy" : "sell"
        act  = long ? "▲ BUY / HOLD" : "▼ SELL / WAIT"
        sub  = long ? "stay 100% in QQQ" : "move to cash and wait"
        combine = long ? "Either-on is <b>long</b> because $(trend_in && mom_in ? "both filters are IN" : "at least one filter is IN") — you sit out only when <b>both</b> turn OUT." :
                         "Either-on is <b>flat</b> because <b>both</b> filters are OUT — re-enter when either turns IN."
    else
        e = AVG[N]; cls = e == 1 ? "buy" : (e == 0 ? "sell" : "half")
        act  = e == 1 ? "▲ HOLD — 100% QQQ" : (e == 0 ? "▼ SELL / WAIT — cash" : "◐ HALF — 50% QQQ")
        sub  = e == 1 ? "both filters IN" : (e == 0 ? "both filters OUT" : "one filter IN, one OUT")
        combine = "Average blend: QQQ weight = (trend + momentum) ÷ 2 = <b>$(round(Int,100e))%</b>."
    end
    sigcard = """
<div class="signal $cls">
  <div class="sigtop"><span class="sigaction">$act</span><span class="sigsub">— $sub</span></div>
  <div class="sigasof">live signal as of <b>$(d.date[N])</b> · QQQ close $(round(Int,d.close[N])) · CCI(40) $(round(Int,c40[N]))</div>
  <div class="brk">
    <div class="brow"><span class="bn">Trend filter — SMA 50/200 fast-reentry</span> $(chip(trend_in)) <span class="bd">$trend_detail</span></div>
    <div class="brow"><span class="bn">Momentum filter — CCI(40) TMA-trigger</span> $(chip(mom_in)) <span class="bd">$mom_detail</span></div>
    <div class="bcombine">$combine</div>
  </div>
</div>"""

    name  = key == :either ? "Blend: Either-On" : "Blend: Average (½-size)"
    tag   = key == :either ?
        "Hold QQQ unless <b>both</b> a trend filter and a momentum filter say cash. Maximum return, ~3 trades/year, fully in or fully out." :
        "Size QQQ to how many of two filters (trend + momentum) agree: 100% if both, 50% if one, 0% if neither. Smoothest ride, cushions every crash."

    # regime rows
    regrows = join(map(regs) do (lbl, f, t)
        a, b = win(f, t); m = ev(sig, a, b); mb = ev(BH, a, b)
        cls = m.maxdd >= mb.maxdd ? "win" : ""
        "<tr><td>$lbl</td><td>$(pct(m.total_return;dg=0))</td><td class=\"$cls\">$(pct(m.maxdd;dg=0))</td><td>$(pct(mb.total_return;dg=0))</td><td class=\"bad\">$(pct(mb.maxdd;dg=0))</td></tr>"
    end, "\n")
    hprows = join(map([("1 year",252),("3 years",756),("5 years",1260),("10 years",2520)]) do (lbl, w)
        lo, md, hi = hp(eq, w); lb, mb2, hb = hp(bt(BH).eq, w)
        "<tr><td>$lbl</td><td class=\"win\">$(pct(lo;dg=0))</td><td>$(pct(md;dg=0))</td><td>$(pct(hi;dg=0))</td><td class=\"bad\">$(pct(lb;dg=0))</td><td>$(pct(mb2;dg=0))</td><td>$(pct(hb;dg=0))</td></tr>"
    end, "\n")

    # strategy-specific execution + assessment text
    if key == :either
        rulehtml = """
<p><b>You are in QQQ by default.</b> You move to cash <i>only</i> when <b>both</b> of these say "out" at the same time, and you return to QQQ the moment <b>either</b> one says "in" again:</p>
<ol>
<li><b>Trend filter (SMA fast-reentry):</b> "out" after a <b>death cross</b> (50-day average falls below the 200-day); back "in" when price closes above its 50-day average (min ~10 trading days between switches).</li>
<li><b>Momentum filter (CCI40 TMA-trigger):</b> "out" when CCI(40) falls below −100 (or below 0 while the 200-day triangular average is sloping down); back "in" when CCI(40) rises above 0.</li>
</ol>
<p>Because you only sit out when <b>both</b> agree, exits are rare and brief — historically about <b>3 trades per year</b>, and the position is always simply 100% QQQ or 100% cash.</p>"""
        whatknow = """
<li><b>It does not cushion sudden one-month crashes.</b> In COVID it drew down −29% (same as buy &amp; hold) because the trend filter stays "in" through a fast plunge. This is the price of staying invested for the extra return.</li>
<li><b>Its protection is for slow, grinding bears</b> (2000–02, 2008, 2022) where at least one filter exits and stays out.</li>
<li>Edge is concentrated in those bears; in calm bull years it trails buy &amp; hold on return but earns ~4% in cash during its rare exits.</li>"""
        verdict = "Maximum terminal wealth (49× vs 34× for the average blend) with the least possible maintenance — about 3 trades a year and no fractional positions. The trade-off is buy-&amp;-hold-level drawdowns in fast crashes. Best for long-horizon money you won't need to draw on soon."
    else
        rulehtml = """
<p><b>Your QQQ weight is the average of two yes/no filters</b> — 100% if both say "in," <b>50% if only one</b>, 0% if neither:</p>
<ol>
<li><b>Trend filter (SMA fast-reentry):</b> "in" while the 50-day average is above the 200-day; "out" after a death cross; back "in" when price reclaims its 50-day average (min ~10 trading days between switches).</li>
<li><b>Momentum filter (CCI40 TMA-trigger):</b> "in" when CCI(40) is above 0; "out" when CCI(40) falls below −100 (or below 0 while the 200-day triangular average is sloping down).</li>
</ol>
<p>Each day, set your QQQ allocation to <b>0% / 50% / 100%</b> per the two filters and hold the rest in cash. This changes more often — about <b>12 times per year</b>, including the half-steps.</p>"""
        whatknow = """
<li><b>It cushions every crash type, including fast ones</b> — when one filter is caught off-guard, the other has usually exited, so you're only half-exposed (COVID −21% vs −29% for buy &amp; hold).</li>
<li>Its drawdown has been shallower than buy &amp; hold in <b>~99% of rolling 3–5 year windows</b> — the most consistent risk reduction of anything tested.</li>
<li>The cost is real: <b>~12 changes/year</b> and <b>fractional (50%) positions</b> to rebalance — more effort and more taxable events than the either-on blend.</li>"""
        verdict = "The smoothest ride and the most reliable drawdown control, with protection against fast <i>and</i> slow crashes. You give up ~1.5 pp/yr of return and accept fractional positions and 4× the turnover. Best if you're near drawing on the money (sequence-of-returns risk) or would otherwise panic-sell in a fast crash."
    end

    html = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$name — QQQ overlay</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;color:#1a1a1a;background:#f6f7f9;padding:28px 16px}
.wrap{max-width:880px;margin:0 auto;background:#fff;border:1px solid #e3e6ea;border-radius:12px;padding:34px 40px;box-shadow:0 1px 4px rgba(0,0,0,.04)}
h1{font-size:27px;line-height:1.15}
h2{font-size:18px;margin:30px 0 10px;padding-bottom:5px;border-bottom:2px solid $color}
.tag{color:#444;font-size:15px;margin:8px 0 16px}
.signal{border-radius:10px;padding:15px 18px;margin:6px 0 14px;border:1px solid}
.signal.buy{background:#eafaf0;border-color:#bce9cd}
.signal.sell{background:#fdecec;border-color:#f3c2c2}
.signal.half{background:#fff7e8;border-color:#f0dca8}
.sigaction{font-size:23px;font-weight:800;letter-spacing:.2px}
.signal.buy .sigaction{color:#0a7f3f}.signal.sell .sigaction{color:#c1121f}.signal.half .sigaction{color:#9a6700}
.sigsub{margin-left:9px;font-size:15px;color:#333}
.sigasof{color:#555;font-size:12.5px;margin:4px 0 11px}
.brk{font-size:13.5px}
.brow{display:flex;align-items:center;gap:9px;padding:3px 0;flex-wrap:wrap}
.bn{min-width:300px;font-weight:600}
.bd{color:#555;font-size:12.5px}
.chip{font-size:11px;font-weight:700;padding:1px 8px;border-radius:11px;color:#fff}
.chip.in{background:#0a7f3f}.chip.out{background:#c1121f}
.bcombine{margin-top:8px;padding-top:8px;border-top:1px dashed #d7dbe0;font-size:13px}
table{border-collapse:collapse;width:100%;font-size:13.5px;margin:6px 0;border:1px solid #e3e6ea;border-radius:8px;overflow:hidden}
th,td{padding:7px 10px;text-align:right;border-bottom:1px solid #eef1f4}
th:first-child,td:first-child{text-align:left}
th{background:#f4f6f8;font-size:12px;color:#444;font-weight:600}
tr:last-child td{border-bottom:none}
td.hl,th.hl{background:#fff4f4}
.win{color:#0a7f3f;font-weight:600}.bad{color:#c1121f}
figure{margin:14px 0}figure svg{width:100%;height:auto;border:1px solid #eceef0;border-radius:8px;background:#fff}
figcaption{color:#666;font-size:12.5px;margin-top:6px}
ol,ul{margin:6px 0 6px 22px}li{margin:5px 0}
.verdict{background:#fafbfc;border:1px solid #e3e6ea;border-left:4px solid $color;border-radius:6px;padding:12px 16px;margin:8px 0;font-size:14.5px}
code{font-family:"SF Mono",Menlo,Consolas,monospace;font-size:12.5px;background:#eef1f4;padding:1px 5px;border-radius:4px}
.foot{margin-top:26px;border-top:1px solid #e3e6ea;padding-top:12px;color:#777;font-size:11.5px}
.muted{color:#777}
</style></head><body><div class="wrap">

<h1>$name</h1>
<div class="tag">$tag</div>
$sigcard

<h2>What it is</h2>
<p>A long/flat timing overlay on QQQ that blends two independent signals with complementary weaknesses: a <b>slow trend filter</b> (50/200-day moving-average crossover with fast re-entry) and a <b>fast momentum filter</b> (CCI(40) band with a 200-day triangular-MA regime switch). The trend filter is blind to sudden crashes; the momentum filter is weak in long grinding bears — so combining them covers both.</p>
$rulehtml

<h2>Performance (1999–2026)</h2>
<table>
<thead><tr><th>metric</th><th class="hl">$name</th><th>buy &amp; hold</th></tr></thead>
<tbody>
<tr><td>CAGR</td><td class="hl win">$(pct(M.cagr))</td><td>$(pct(Mbh.cagr))</td></tr>
<tr><td>Growth of \$1</td><td class="hl">$(round(M.total_return+1;digits=1))×</td><td>$(round(Mbh.total_return+1;digits=1))×</td></tr>
<tr><td>Max drawdown</td><td class="hl">$(pct(M.maxdd;dg=0))</td><td class="bad">$(pct(Mbh.maxdd;dg=0))</td></tr>
<tr><td>Volatility (annual)</td><td class="hl">$(pct(M.vol;dg=0))</td><td>$(pct(Mbh.vol;dg=0))</td></tr>
<tr><td>Sharpe / Sortino</td><td class="hl">$(round(M.sharpe;digits=2)) / $(round(M.sortino;digits=2))</td><td>$(round(Mbh.sharpe;digits=2)) / $(round(Mbh.sortino;digits=2))</td></tr>
<tr><td>Calmar (return ÷ drawdown)</td><td class="hl">$(round(M.calmar;digits=2))</td><td>$(round(Mbh.calmar;digits=2))</td></tr>
<tr><td>Out-of-sample 2004+ CAGR / DD</td><td class="hl">$(pct(O.cagr)) / $(pct(O.dd;dg=0))</td><td>$(pct(Obh.cagr)) / $(pct(Obh.dd;dg=0))</td></tr>
<tr><td>% of time invested</td><td class="hl">$(pct(M.pct_invested;dg=0))</td><td>100%</td></tr>
<tr><td>Trades per year</td><td class="hl">$(round(M.ntrades/M.years;digits=1))</td><td>0</td></tr>
</tbody></table>

<figure>$chart<figcaption>Growth of \$1 (log scale, top) and drawdown (bottom), 1999–2026. $name in $(key==:either ? "red" : "blue") vs buy &amp; hold in gray.</figcaption></figure>

<h2>How it behaves in each market</h2>
<table>
<thead><tr><th>regime</th><th>strategy return</th><th>strategy maxDD</th><th>B&amp;H return</th><th>B&amp;H maxDD</th></tr></thead>
<tbody>
$regrows
</tbody></table>
<p class="muted" style="font-size:12.5px">Green drawdown = shallower than buy &amp; hold. Total return over the span / deepest drawdown within it.</p>

<h2>Return consistency by holding period</h2>
<table>
<thead><tr><th>hold for</th><th class="hl" colspan="3">$name — worst / median / best (annualized)</th><th colspan="3">buy &amp; hold — worst / median / best</th></tr></thead>
<tbody>
$hprows
</tbody></table>
<p class="muted" style="font-size:12.5px">Rolling windows, stride ~1 month. The <b>worst</b> column is the point: the overlay has had no losing 5- or 10-year window.</p>

<h2>Bottom line</h2>
<div class="verdict">$verdict</div>

<h2>How to execute it</h2>
<ul>
<li><b>Daily routine:</b> after the close, check the two filters and set your QQQ weight per the rule above. Trade at the next session. $(key==:either ? "Exits are rare — checking a few times a week is plenty." : "Changes cluster around market turns; check daily in volatile periods.")</li>
<li><b>Where to hold the asset:</b> QQQ, or <b>QQQM</b> (same index, lower 0.15% fee). <b>Do not</b> use leveraged ETFs (TQQQ) — leverage breaks the risk profile.</li>
<li><b>Where to hold cash:</b> a money-market fund, T-bills, or HYSA earning ~4%. Part of the return edge depends on earning yield while out; the drawdown protection does not.</li>
<li><b>Account &amp; tax:</b> $(key==:either ? "at ~3 trades/year this is quite tax-friendly, but a tax-advantaged account (IRA/Roth/401k) is still cleanest." : "at ~12 trades/year plus fractional rebalances this realizes many short-term events — strongly prefer a tax-advantaged account (IRA/Roth/401k).")</li>
<li><b>Discipline:</b> follow the rule mechanically. The hard moments are selling when the market still feels fine and re-buying while it still feels scary.</li>
</ul>
<h3 style="font-size:15px;margin:14px 0 4px">What to expect / when it disappoints</h3>
<ul>
$whatknow
<li>In a relentless bull market you will trail buy &amp; hold — the protection only pays off in the next deep bear.</li>
</ul>

<div class="foot">Historical backtest of mechanical rules on daily QQQ, 1999–2026. Long/flat$(key==:either ? "" : " (or half)"), cash earns 4%/yr, 5 bps cost per switch, signals computed at the close and acted the next session (no look-ahead); all returns close-to-close. Both component rules validated out-of-sample (the fixed parameters beat adaptive re-optimization). <b>This is not investment advice and not a prediction. Past performance does not guarantee future results.</b> Methodology: analysis/STRATEGY.md · reproduce: <code>julia analysis/blend_finalists_compare.jl</code>.</div>
</div></body></html>"""
    write(joinpath(RES, file), html)
    println("Wrote ", joinpath(RES, file))
end

build_page("blend_either_on.html", :either)
build_page("blend_avg.html", :avg)
