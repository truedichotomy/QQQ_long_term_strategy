# Risk vs return scatter — the best trend-filter variant for each ETF, on a
# common 2005+ window. y = CAGR (return), x = |max drawdown| (risk). Dashed
# radial lines are iso-Calmar (return-per-drawdown) contours: points on a
# steeper line are better risk-adjusted. Pure base Julia SVG.
#
#   julia analysis/plot_universe.jl     # -> results/risk_return.svg (+ .png)

include(joinpath(dirname(@__DIR__), "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const RES = joinpath(dirname(@__DIR__), "results", "sma_study"); const SVG = joinpath(RES, "risk_return.svg")
const RF = 0.04
bt(d, s) = run_backtest(d, s; cost=5e-4, rf_annual=RF)
function wm(eq, dts, a, b)
    es = eq[a:b] ./ eq[a]; m = length(es); yrs = max(Dates.value(dts[b] - dts[a]) / 365.25, 1e-9)
    er = [es[i] / es[i-1] - 1 for i in 2:m]; rfd = (1 + RF)^(1/252) - 1
    μ = mean(er); σ = std(er)
    (cagr=es[end]^(1/yrs) - 1, maxdd=max_drawdown(es), sharpe=(μ - rfd) / σ * sqrt(252))
end

tickers = ("QQQ","VGT","SOXX","SPY","DIA","IWM","XLE","TLT","GLD","TIP")
pts = []
for t in tickers
    d = load_ticker(t; dir=joinpath(dirname(dirname(@__DIR__)), "data"))
    a, b = date_range(d, Date(2005,1,3), d.date[end])
    best = nothing
    for (nm, sig) in (("Std", fast_reentry(d)), ("Con", sma_cross(d; fast=50, slow=200)))
        m = wm(bt(d, sig).eq, d.date, a, b)
        (best === nothing || m.sharpe > best.s) && (best = (t=t, v=nm, c=m.cagr, dd=abs(m.maxdd), s=m.sharpe))
    end
    push!(pts, best)
end

# geometry
W, H, L, R, T, B = 1000, 640, 70, 30, 40, 58
PW = W - L - R; PH = H - T - B
xmax = 0.50; ymax = 0.20
X(dd) = L + dd / xmax * PW
Y(c) = T + (1 - c / ymax) * PH
esc(s) = replace(s, "&" => "&amp;")
io = IOBuffer()
print(io, """<svg xmlns="http://www.w3.org/2000/svg" width="$W" height="$H" viewBox="0 0 $W $H" font-family="Helvetica,Arial,sans-serif">
<rect width="$W" height="$H" fill="white"/>
<text x="$L" y="24" font-size="17" font-weight="bold">Risk vs return — best trend-filter variant per ETF (2005–2026)</text>
""")
# iso-Calmar dashed lines
for (cal, lbl) in ((0.5, "Calmar 0.5"), (0.3, "Calmar 0.3"))
    x2 = xmax; y2 = cal * x2
    if y2 > ymax; y2 = ymax; x2 = y2 / cal; end
    print(io, "<line x1=\"$(X(0))\" y1=\"$(Y(0))\" x2=\"$(round(X(x2);digits=1))\" y2=\"$(round(Y(y2);digits=1))\" stroke=\"#cdd6df\" stroke-dasharray=\"5 4\"/>")
    print(io, "<text x=\"$(round(X(x2)-4;digits=1))\" y=\"$(round(Y(y2)-5;digits=1))\" font-size=\"11\" fill=\"#9aa6b2\" text-anchor=\"end\">$lbl</text>")
end
# axes grid
for c in 0:0.05:ymax
    y = round(Y(c); digits=1)
    print(io, "<line x1=\"$L\" y1=\"$y\" x2=\"$(L+PW)\" y2=\"$y\" stroke=\"#eef1f4\"/><text x=\"$(L-8)\" y=\"$(y+4)\" font-size=\"11\" text-anchor=\"end\" fill=\"#555\">$(round(Int,100c))%</text>")
end
for dd in 0:0.1:xmax
    x = round(X(dd); digits=1)
    print(io, "<line x1=\"$x\" y1=\"$T\" x2=\"$x\" y2=\"$(T+PH)\" stroke=\"#eef1f4\"/><text x=\"$x\" y=\"$(H-34)\" font-size=\"11\" text-anchor=\"middle\" fill=\"#555\">$(round(Int,100dd))%</text>")
end
print(io, "<text x=\"$(L+PW/2)\" y=\"$(H-12)\" font-size=\"12.5\" text-anchor=\"middle\" fill=\"#333\">maximum drawdown (risk →)</text>")
print(io, "<text x=\"18\" y=\"$(T+PH/2)\" font-size=\"12.5\" fill=\"#333\" transform=\"rotate(-90 18 $(T+PH/2))\" text-anchor=\"middle\">CAGR (return →)</text>")
# points
for p in pts
    x = X(p.dd); y = Y(p.c)
    top = p.t in ("QQQ", "SOXX")
    col = top ? "#0a7f3f" : (p.s >= 0.4 ? "#1f6feb" : "#9aa6b2")
    r = top ? 8 : 6
    print(io, "<circle cx=\"$(round(x;digits=1))\" cy=\"$(round(y;digits=1))\" r=\"$r\" fill=\"$col\" fill-opacity=\"0.85\"/>")
    print(io, "<text x=\"$(round(x+11;digits=1))\" y=\"$(round(y+4;digits=1))\" font-size=\"$(top ? 13 : 12)\" font-weight=\"$(top ? "700" : "400")\" fill=\"#222\">$(p.t) ($(p.v))</text>")
end
print(io, "<rect x=\"$L\" y=\"$T\" width=\"$PW\" height=\"$PH\" fill=\"none\" stroke=\"#ccc\"/>")
print(io, "<text x=\"$(L+PW)\" y=\"$(T-8)\" font-size=\"11\" fill=\"#9aa6b2\" text-anchor=\"end\">up-and-left = better risk-adjusted · Std=fast re-entry, Con=classic 50/200</text>")
print(io, "</svg>")
write(SVG, take!(io)); println("Wrote ", SVG)
let rsvg = Sys.which("rsvg-convert"); rsvg !== nothing && run(`$rsvg -w 1500 $SVG -o $(replace(SVG, ".svg" => ".png"))`); end
