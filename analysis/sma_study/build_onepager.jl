# One-page, print-optimized summary of the QQQ trend-filter strategy.
# Writes a compact HTML sized for a single Letter page; render to PDF with:
#   chrome --headless --no-pdf-header-footer --print-to-pdf=... file://....html
# (the run wrapper in the shell does this). Numbers computed from the toolkit;
# the equity chart is inlined from results/hybrid_vs_fixed.svg.
#
#   julia analysis/build_onepager.jl     # -> results/QQQ_strategy_1page.html

include(joinpath(dirname(@__DIR__), "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const RES = joinpath(dirname(@__DIR__), "results", "sma_study"); const OUT = joinpath(RES, "QQQ_strategy_1page.html")
const COST, RF = 5e-4, 0.04
d = load_ticker("QQQ"; dir=joinpath(dirname(dirname(@__DIR__)), "data")); N = length(d)
bt(s) = run_backtest(d, s; cost=COST, rf_annual=RF)
bh = bt(buyhold(d)); st = bt(fast_reentry(d)); cn = bt(sma_cross(d; fast=50, slow=200))
Mbh, Mst, Mcn = compute_metrics(bh), compute_metrics(st), compute_metrics(cn)
pct(x; dg=1) = string(round(100x; digits=dg), "%")
oos_a = 1261
oos(b) = (es = b.eq[oos_a:N] ./ b.eq[oos_a]; yrs = Dates.value(d.date[N] - d.date[oos_a]) / 365.25; (cagr=es[end]^(1/yrs)-1, dd=max_drawdown(es)))
obh, ost, ocn = oos(bh), oos(st), oos(cn)
s50 = sma(d.close, 50); s200 = sma(d.close, 200)
fsig = fast_reentry(d); csig = sma_cross(d; fast=50, slow=200)
lc(s) = (x=1; for i in 2:N; s[i]!=s[i-1] && (x=i); end; x)
svg = isfile(joinpath(RES, "hybrid_vs_fixed.svg")) ? read(joinpath(RES, "hybrid_vs_fixed.svg"), String) : ""

html = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>QQQ Trend-Filter — one page</title>
<style>
@page { size: Letter; margin: 11mm; }
*{box-sizing:border-box;margin:0;padding:0}
body{font:10px/1.38 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;color:#1a1a1a;-webkit-print-color-adjust:exact;print-color-adjust:exact}
h1{font-size:18px;line-height:1.1}
.sub{color:#555;font-size:10.5px;margin:2px 0 6px}
.banner{background:#eafbf0;border:1px solid #bce9cd;border-radius:5px;padding:5px 9px;margin-bottom:8px;font-size:10px}
.banner b.l{color:#0a7f3f;font-size:12px}
.grid{display:flex;gap:10px;align-items:flex-start}
.left{flex:0 0 54%}.right{flex:1}
figure svg{width:100%;height:auto;border:1px solid #e3e6ea;border-radius:5px;display:block}
figcaption{color:#666;font-size:8.5px;margin-top:2px}
table{border-collapse:collapse;width:100%;font-size:9.5px;border:1px solid #e3e6ea;border-radius:5px;overflow:hidden}
th,td{padding:3.5px 6px;text-align:right;border-bottom:1px solid #eef1f4}
th:first-child,td:first-child{text-align:left}
th{background:#f4f6f8;font-size:8.5px;color:#444}
tr:last-child td{border-bottom:none}
td.std,th.std{background:#fdeef0}
.win{color:#0a7f3f;font-weight:700}.bad{color:#d1242f}
.pick{background:#fdeef0;border:1px solid #f3c2c2;border-radius:5px;padding:6px 9px;margin-top:7px;font-size:9.5px}
.pick b{color:#a31515}
h2{font-size:11px;margin:9px 0 3px;border-bottom:1px solid #e3e6ea;padding-bottom:2px}
.cols{display:flex;gap:14px}.cols>div{flex:1}
.r{font-size:9.3px}.r b{color:#1f6feb}
ul{margin:0 0 0 14px}li{margin:1px 0;font-size:9.3px}
.foot{margin-top:8px;border-top:1px solid #e3e6ea;padding-top:4px;color:#777;font-size:8px}
code{font-family:"SF Mono",Menlo,Consolas,monospace;font-size:8.8px;background:#eef1f4;padding:0 3px;border-radius:3px}
</style></head><body>
<h1>QQQ Trend-Filter Strategy</h1>
<div class="sub">Long/flat timing — hold QQQ while its trend is up (50-day average above the 200-day), step aside to cash when it rolls over. Captures most of buy-and-hold's return at roughly half the drawdown.</div>
<div class="banner"><b class="l">▲ LONG</b> &nbsp;as of $(d.date[N]) · close $(round(d.close[N];digits=0)) · SMA-50 $(round(s50[N];digits=0)) &gt; SMA-200 $(round(s200[N];digits=0)). &nbsp; <b>Standard</b> since $(d.date[lc(fsig)]) · <b>Conservative</b> since $(d.date[lc(csig)]).</div>
<div class="grid">
  <div class="left">
    <figure>$svg<figcaption>Growth of \$1 (log) and drawdown, 1999–2026. Standard (red) compounds fastest; both filters dodge the −83% dot-com crash that buy &amp; hold (gray) takes in full.</figcaption></figure>
  </div>
  <div class="right">
    <table>
      <thead><tr><th>1999–2026</th><th class="std">Standard</th><th>Conserv.</th><th>Buy&amp;hold</th></tr></thead>
      <tbody>
      <tr><td>CAGR</td><td class="std win">$(pct(Mst.cagr))</td><td>$(pct(Mcn.cagr))</td><td>$(pct(Mbh.cagr))</td></tr>
      <tr><td>Growth of \$1</td><td class="std">$(round(Mst.total_return+1;digits=1))×</td><td>$(round(Mcn.total_return+1;digits=1))×</td><td>$(round(Mbh.total_return+1;digits=1))×</td></tr>
      <tr><td>Max drawdown</td><td class="std">$(pct(Mst.maxdd;dg=0))</td><td>$(pct(Mcn.maxdd;dg=0))</td><td class="bad">$(pct(Mbh.maxdd;dg=0))</td></tr>
      <tr><td>Sharpe</td><td class="std">$(round(Mst.sharpe;digits=2))</td><td>$(round(Mcn.sharpe;digits=2))</td><td>$(round(Mbh.sharpe;digits=2))</td></tr>
      <tr><td>Calmar</td><td class="std">$(round(Mst.calmar;digits=2))</td><td>$(round(Mcn.calmar;digits=2))</td><td>$(round(Mbh.calmar;digits=2))</td></tr>
      <tr><td>OOS 2004+ CAGR</td><td class="std">$(pct(ost.cagr))</td><td>$(pct(ocn.cagr))</td><td>$(pct(obh.cagr))</td></tr>
      <tr><td>OOS drawdown</td><td class="std">$(pct(ost.dd;dg=0))</td><td>$(pct(ocn.dd;dg=0))</td><td class="bad">$(pct(obh.dd;dg=0))</td></tr>
      <tr><td>Trades / yr</td><td class="std">$(round(Mst.ntrades/Mst.years;digits=1))</td><td>$(round(Mcn.ntrades/Mcn.years;digits=1))</td><td>0</td></tr>
      </tbody>
    </table>
    <div class="pick"><b>If you pick one asset:</b> QQQ, run with the <b>Standard</b> variant — best risk-adjusted return and validated out-of-sample. <b>SOXX</b> (Conservative variant) is the higher-octane alternative; both beat the other 8 ETFs tested. <b>VGT</b> ranks well in-sample but its edge doesn't confirm out-of-sample.</div>
  </div>
</div>
<div class="cols">
  <div>
    <h2>The rules</h2>
    <div class="r"><b>Standard (central):</b> hold QQQ while SMA-50 &gt; SMA-200; sell to cash on a death cross (SMA-50 &lt; SMA-200); after an exit, re-enter as soon as price closes back above its 50-day SMA — don't wait for the golden cross; keep each position ≥ ~10 trading days. ~5 trades/yr.</div>
    <div class="r" style="margin-top:4px"><b>Conservative:</b> same, but re-enter only on a full golden cross. Simpler, ~1 trade/yr, tighter crash control, lower return.</div>
  </div>
  <div>
    <h2>What to know</h2>
    <ul>
      <li>Edge is concentrated in <b>bear markets</b>; it trails buy-and-hold in sustained bulls.</li>
      <li>Hold cash in <b>T-bills / money-market</b> (~4%) — part of the return edge depends on it.</li>
      <li>Use a <b>tax-advantaged account</b> (switches realize gains). Use QQQ/QQQM, not leveraged TQQQ.</li>
      <li>Won't dodge <b>sudden one-month crashes</b> (COVID); whipsaws in choppy sideways markets.</li>
    </ul>
  </div>
</div>
<div class="foot">Historical backtest of mechanical rules on daily QQQ, 1999–2026; cash earns 4%/yr, 5 bps cost per switch, signals acted next session (no look-ahead). <b>Not investment advice; past performance does not guarantee future results.</b> Full report: QQQ_strategy.html · methodology: analysis/STRATEGY.md.</div>
</body></html>"""
write(OUT, html)
println("Wrote ", OUT)
