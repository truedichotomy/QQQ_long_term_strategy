# Chart: buy & hold vs fixed 50/200 vs fast-reentry hybrid (full sample).
# Two stacked panels — growth of $1 (log) and drawdown. Pure base Julia SVG.
#
#   julia analysis/plot_hybrid.jl     # -> results/hybrid_vs_fixed.svg

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Dates

const OUTDIR = joinpath(@__DIR__, "results")
const SVG = joinpath(OUTDIR, "hybrid_vs_fixed.svg")
d = load_ticker("QQQ"; dir=joinpath(dirname(@__DIR__), "data"))
bt(s) = run_backtest(d, s; cost=5e-4, rf_annual=0.04).eq

curves = [
    ("buy & hold",               "#888888", bt(buyhold(d))),
    ("Conservative (50/200)",    "#1f6feb", bt(sma_cross(d; fast=50, slow=200))),
    ("Standard (fast re-entry)", "#d1242f", bt(fast_reentry(d))),
]
n = length(d); yr = year.(d.date)

# geometry
W, H, L, R, Tm, Bm, GAP, P1H = 1060, 700, 72, 176, 34, 44, 46, 372
P2T = Tm + P1H + GAP; P2H = H - P2T - Bm; PW = W - L - R
xat(i) = L + (i - 1) / (n - 1) * PW
logs = [log10.(c[3]) for c in curves]
ymin = minimum(minimum, logs); ymax = maximum(maximum, logs)
y1(v) = Tm + (1 - (v - ymin) / (ymax - ymin)) * P1H
dds = [drawdown_series(c[3]) for c in curves]
mindd = minimum(minimum, dds)
y2(x) = P2T + (x / mindd) * P2H
poly(xs, ys, col, w) = string("<polyline fill=\"none\" stroke=\"", col, "\" stroke-width=\"", w,
    "\" points=\"", join((string(round(xs[i]; digits=1), ",", round(ys[i]; digits=1)) for i in eachindex(xs)), " "), "\"/>")

io = IOBuffer()
print(io, """<svg xmlns="http://www.w3.org/2000/svg" width="$W" height="$H" font-family="Helvetica,Arial,sans-serif">
<rect width="$W" height="$H" fill="white"/>
<text x="$L" y="20" font-size="17" font-weight="bold">QQQ $(yr[1])–$(yr[end]): Standard (fast re-entry) vs Conservative (50/200) vs buy &amp; hold</text>
""")
for k in (1, 2, 5, 10, 20, 50, 100)
    v = log10(k); (v < ymin || v > ymax) && continue
    y = round(y1(v); digits=1)
    print(io, "<line x1=\"$L\" y1=\"$y\" x2=\"$(L+PW)\" y2=\"$y\" stroke=\"#e6e6e6\"/><text x=\"$(L-8)\" y=\"$(y+4)\" font-size=\"12\" text-anchor=\"end\" fill=\"#555\">$(k)x</text>")
end
print(io, "<text x=\"16\" y=\"$(Tm+P1H÷2)\" font-size=\"12\" fill=\"#555\" transform=\"rotate(-90 16 $(Tm+P1H÷2))\" text-anchor=\"middle\">growth of \$1 (log)</text>")
for dd in (0.0, -0.2, -0.4, -0.6, -0.8)
    dd < mindd && continue
    y = round(y2(dd); digits=1)
    print(io, "<line x1=\"$L\" y1=\"$y\" x2=\"$(L+PW)\" y2=\"$y\" stroke=\"#e6e6e6\"/><text x=\"$(L-8)\" y=\"$(y+4)\" font-size=\"12\" text-anchor=\"end\" fill=\"#555\">$(round(Int,100dd))%</text>")
end
print(io, "<text x=\"16\" y=\"$(P2T+P2H÷2)\" font-size=\"12\" fill=\"#555\" transform=\"rotate(-90 16 $(P2T+P2H÷2))\" text-anchor=\"middle\">drawdown</text>")
let last = 0
    for i in 1:n
        if yr[i] % 3 == 0 && (i == 1 || yr[i] != yr[i-1]) && yr[i] != last
            x = round(xat(i); digits=1)
            print(io, "<line x1=\"$x\" y1=\"$Tm\" x2=\"$x\" y2=\"$(Tm+P1H)\" stroke=\"#f4f4f4\"/><line x1=\"$x\" y1=\"$P2T\" x2=\"$x\" y2=\"$(P2T+P2H)\" stroke=\"#f4f4f4\"/><text x=\"$x\" y=\"$(H-22)\" font-size=\"12\" text-anchor=\"middle\" fill=\"#555\">$(yr[i])</text>")
            last = yr[i]
        end
    end
end
xs = [xat(i) for i in 1:n]
for (k, c) in enumerate(curves)
    print(io, poly(xs, [y1(logs[k][i]) for i in 1:n], c[2], 1.6))
    print(io, poly(xs, [y2(dds[k][i]) for i in 1:n], c[2], 1.2))
end
print(io, "<rect x=\"$L\" y=\"$Tm\" width=\"$PW\" height=\"$P1H\" fill=\"none\" stroke=\"#ccc\"/><rect x=\"$L\" y=\"$P2T\" width=\"$PW\" height=\"$P2H\" fill=\"none\" stroke=\"#ccc\"/>")
lx = L + PW + 16; ly = Tm + 8
esc(s) = replace(s, "&" => "&amp;")
for (k, c) in enumerate(curves)
    yy = ly + (k - 1) * 22
    print(io, "<line x1=\"$lx\" y1=\"$yy\" x2=\"$(lx+26)\" y2=\"$yy\" stroke=\"$(c[2])\" stroke-width=\"2.6\"/><text x=\"$(lx+32)\" y=\"$(yy+4)\" font-size=\"13\">$(esc(c[1]))</text>")
end
let yrs = (Dates.value(d.date[end] - d.date[1])) / 365.25,
    cagr = [round(100 * (c[3][end]^(1 / yrs) - 1); digits=1) for c in curves],
    mdd  = [round(Int, 100 * max_drawdown(c[3])) for c in curves],
    fin  = [round(c[3][end]; digits=1) for c in curves],
    texts = ["CAGR  $(cagr[1]) / $(cagr[2]) / $(cagr[3]) %",
             "maxDD  $(mdd[1]) / $(mdd[2]) / $(mdd[3]) %",
             "final  $(fin[1]) / $(fin[2]) / $(fin[3]) x"]
    for (j, t) in enumerate(texts)
        print(io, "<text x=\"$lx\" y=\"$(ly+66+18*(j-1))\" font-size=\"11.5\" fill=\"#333\">$t</text>")
    end
end
print(io, "</svg>")
write(SVG, take!(io))
println("Wrote ", SVG)

# optional PNG (aspect-preserving; macOS qlmanage crops wide SVGs into squares — don't use it)
let rsvg = Sys.which("rsvg-convert")
    rsvg !== nothing && run(`$rsvg -w 1600 $SVG -o $(replace(SVG, ".svg" => ".png"))`)
end
