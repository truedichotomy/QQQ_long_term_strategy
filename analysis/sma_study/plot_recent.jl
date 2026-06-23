# Last-10-year relative performance: buy & hold vs fixed 50/200 vs fast-reentry.
# Top panel  — growth of $1 rebased to 1.0 at the start of the window (linear).
# Bottom panel — performance RELATIVE to buy & hold (strategy/B&H, rebased to 1.0):
#   above the 1.0 line = cumulatively ahead of B&H, below = behind.
#
#   julia analysis/plot_recent.jl     # -> results/recent_10yr.svg (+ .png if rsvg-convert present)

include(joinpath(dirname(@__DIR__), "QQQBacktest.jl"))
using .QQQBacktest
using Dates, Printf

const OUTDIR = joinpath(dirname(@__DIR__), "results", "sma_study")
const SVG = joinpath(OUTDIR, "recent_10yr.svg")
d = load_ticker("QQQ"; dir=joinpath(dirname(dirname(@__DIR__)), "data"))
bt(s) = run_backtest(d, s; cost=5e-4, rf_annual=0.04).eq

# full-history backtests (correct warm-up / regime state), then slice last 10 years
eq_bh = bt(buyhold(d))
eq_fx = bt(sma_cross(d; fast=50, slow=200))
eq_fr = bt(fast_reentry(d; fast=50, slow=200, re=50))
i0, i1 = date_range(d, d.date[end] - Year(10), d.date[end])
N = i1 - i0 + 1
yr = year.(@view d.date[i0:i1])

reb(eq) = (e = eq[i0:i1]; e ./ e[1])              # rebased growth, starts at 1.0
g_bh, g_fx, g_fr = reb(eq_bh), reb(eq_fx), reb(eq_fr)
rel(g) = g ./ g_bh                                # relative to B&H (B&H ≡ 1.0)
r_fx, r_fr = rel(g_fx), rel(g_fr)

curves = [("buy & hold", "#888888", g_bh), ("Conservative (50/200)", "#1f6feb", g_fx), ("Standard (fast re-entry)", "#d1242f", g_fr)]

# geometry (two panels)
W, H, L, R, Tm, Bm, GAP, P1H = 1060, 700, 74, 184, 34, 46, 50, 360
P2T = Tm + P1H + GAP; P2H = H - P2T - Bm; PW = W - L - R
xat(i) = L + (i - 1) / (N - 1) * PW
gmax = maximum(maximum, (g_bh, g_fx, g_fr)); gmin = min(1.0, minimum(minimum, (g_bh, g_fx, g_fr)))
y1(v) = Tm + (1 - (v - gmin) / (gmax - gmin)) * P1H
rmin = min(minimum(r_fx), minimum(r_fr), 1.0) - 0.02
rmax = max(maximum(r_fx), maximum(r_fr), 1.0) + 0.02
y2(v) = P2T + (1 - (v - rmin) / (rmax - rmin)) * P2H
poly(ys, col, w) = string("<polyline fill=\"none\" stroke=\"", col, "\" stroke-width=\"", w, "\" points=\"",
    join((string(round(xat(i); digits=1), ",", round(ys[i]; digits=1)) for i in 1:N), " "), "\"/>")
esc(s) = replace(s, "&" => "&amp;")

io = IOBuffer()
print(io, """<svg xmlns="http://www.w3.org/2000/svg" width="$W" height="$H" viewBox="0 0 $W $H" font-family="Helvetica,Arial,sans-serif">
<rect width="$W" height="$H" fill="white"/>
<text x="$L" y="20" font-size="17" font-weight="bold">QQQ last 10 years ($(yr[1])–$(yr[end])): relative performance, \$1 rebased at start</text>
""")
# panel 1 gridlines (growth multiple, nice integer steps)
step1 = gmax > 6 ? 1.0 : 0.5
let v = 1.0
    while v <= gmax + 1e-9
        if v >= gmin
            y = round(y1(v); digits=1)
            print(io, "<line x1=\"$L\" y1=\"$y\" x2=\"$(L+PW)\" y2=\"$y\" stroke=\"#ededed\"/><text x=\"$(L-8)\" y=\"$(y+4)\" font-size=\"12\" text-anchor=\"end\" fill=\"#555\">$(round(v;digits=1))x</text>")
        end
        v += step1
    end
end
print(io, "<text x=\"16\" y=\"$(Tm+P1H÷2)\" font-size=\"12\" fill=\"#555\" transform=\"rotate(-90 16 $(Tm+P1H÷2))\" text-anchor=\"middle\">growth of \$1 (rebased)</text>")
# panel 2 gridlines (relative, with emphasized 1.0 line)
let v = ceil(rmin / 0.05) * 0.05
    while v <= rmax + 1e-9
        y = round(y2(v); digits=1)
        emph = abs(v - 1.0) < 1e-9
        print(io, "<line x1=\"$L\" y1=\"$y\" x2=\"$(L+PW)\" y2=\"$y\" stroke=\"$(emph ? "#999" : "#ededed")\" stroke-width=\"$(emph ? 1.3 : 1)\"/><text x=\"$(L-8)\" y=\"$(y+4)\" font-size=\"12\" text-anchor=\"end\" fill=\"#555\">$(round(Int,100v))%</text>")
        v += 0.05
    end
end
print(io, "<text x=\"16\" y=\"$(P2T+P2H÷2)\" font-size=\"12\" fill=\"#555\" transform=\"rotate(-90 16 $(P2T+P2H÷2))\" text-anchor=\"middle\">relative to buy &amp; hold</text>")
# year ticks (every year)
let last = 0
    for i in 1:N
        if yr[i] != last
            x = round(xat(i); digits=1)
            print(io, "<line x1=\"$x\" y1=\"$Tm\" x2=\"$x\" y2=\"$(Tm+P1H)\" stroke=\"#f5f5f5\"/><line x1=\"$x\" y1=\"$P2T\" x2=\"$x\" y2=\"$(P2T+P2H)\" stroke=\"#f5f5f5\"/><text x=\"$x\" y=\"$(H-24)\" font-size=\"12\" text-anchor=\"middle\" fill=\"#555\">$(yr[i])</text>")
            last = yr[i]
        end
    end
end
# curves
for (_, col, g) in curves; print(io, poly([y1(v) for v in g], col, 1.7)); end
print(io, poly([y2(v) for v in r_fx], "#1f6feb", 1.7))
print(io, poly([y2(v) for v in r_fr], "#d1242f", 1.7))
# panel borders
print(io, "<rect x=\"$L\" y=\"$Tm\" width=\"$PW\" height=\"$P1H\" fill=\"none\" stroke=\"#ccc\"/><rect x=\"$L\" y=\"$P2T\" width=\"$PW\" height=\"$P2H\" fill=\"none\" stroke=\"#ccc\"/>")
# legend with 10-yr CAGR / maxDD
yrs = Dates.value(d.date[i1] - d.date[i0]) / 365.25
lx = L + PW + 16; ly = Tm + 8
for (k, c) in enumerate(curves)
    g = c[3]; cagr = round(100 * (g[end]^(1 / yrs) - 1); digits=1); mdd = round(Int, 100 * max_drawdown(g))
    yy = ly + (k - 1) * 40
    print(io, "<line x1=\"$lx\" y1=\"$yy\" x2=\"$(lx+24)\" y2=\"$yy\" stroke=\"$(c[2])\" stroke-width=\"2.6\"/><text x=\"$(lx+30)\" y=\"$(yy+4)\" font-size=\"13\">$(esc(c[1]))</text>")
    print(io, "<text x=\"$(lx)\" y=\"$(yy+18)\" font-size=\"11\" fill=\"#444\">CAGR $(cagr)%  DD $(mdd)%</text>")
end
print(io, "</svg>")
write(SVG, take!(io))
println("Wrote ", SVG)

# optional PNG (aspect-preserving; qlmanage crops wide SVGs into squares — don't use it)
let rsvg = Sys.which("rsvg-convert")
    rsvg !== nothing && run(`$rsvg -w 1600 $SVG -o $(replace(SVG, ".svg" => ".png"))`)
end
