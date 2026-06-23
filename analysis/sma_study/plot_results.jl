# Dependency-free SVG chart of the flagship vs buy-and-hold, built from
# results/equity_curves.csv (written by run_analysis.jl). Two stacked panels:
# growth of $1 (log scale) on top, drawdown on the bottom. Pure base Julia.
#
#   julia analysis/run_analysis.jl     # produces the CSV
#   julia analysis/plot_results.jl     # produces results/equity_curves.svg

const HERE = dirname(@__DIR__)
const CSV  = joinpath(HERE, "results", "equity_curves.csv")
const SVG  = joinpath(HERE, "results", "equity_curves.svg")
const SUMMARY = joinpath(HERE, "results", "flagship_summary.csv")

# headline numbers come from run_analysis.jl so the chart never goes stale
summ = Dict{String,Tuple{String,String}}()
for ln in readlines(SUMMARY)[2:end]
    f = split(ln, ","); summ[f[1]] = (f[2], f[3])
end
flagname = summ["name"][1]
fmtpct(s) = string(round(100 * parse(Float64, s); digits=1), "%")
fmtx(s)   = string(round(parse(Float64, s); digits=1), "x")

# ---- read CSV (date, close, bh_equity, flagship_equity, pos, bh_dd, flag_dd) ----
rows = readlines(CSV)[2:end]
n = length(rows)
year = Vector{Int}(undef, n)
bh   = Vector{Float64}(undef, n); fl   = Vector{Float64}(undef, n)
ddb  = Vector{Float64}(undef, n); ddf  = Vector{Float64}(undef, n)
pos  = Vector{Float64}(undef, n)
for (i, ln) in enumerate(rows)
    f = split(ln, ",")
    year[i] = parse(Int, f[1][1:4])
    bh[i]  = parse(Float64, f[3]); fl[i] = parse(Float64, f[4])
    pos[i] = parse(Float64, f[5])
    ddb[i] = parse(Float64, f[6]); ddf[i] = parse(Float64, f[7])
end

# ---- geometry ----
const W, H = 1060, 700
const L, R, Tm, Bm = 72, 176, 34, 44
const GAP = 46
const P1H = 372
const P2T = Tm + P1H + GAP
const P2H = H - P2T - Bm
const PW = W - L - R

xat(i) = L + (i - 1) / (n - 1) * PW

log10bh = log10.(bh); log10fl = log10.(fl)
ymin = min(minimum(log10bh), minimum(log10fl))
ymax = max(maximum(log10bh), maximum(log10fl))
y1(v) = Tm + (1 - (v - ymin) / (ymax - ymin)) * P1H

mindd = min(minimum(ddb), minimum(ddf))
y2(dd) = P2T + (dd / mindd) * P2H

polyline(xs, ys, color, w) =
    string("<polyline fill=\"none\" stroke=\"", color, "\" stroke-width=\"", w,
           "\" points=\"", join((string(round(xs[i]; digits=1), ",", round(ys[i]; digits=1)) for i in eachindex(xs)), " "), "\"/>")

io = IOBuffer()
print(io, """<svg xmlns="http://www.w3.org/2000/svg" width="$W" height="$H" viewBox="0 0 $W $H" font-family="Helvetica,Arial,sans-serif">
<rect width="$W" height="$H" fill="white"/>
<text x="$L" y="20" font-size="17" font-weight="bold">QQQ: $flagname vs buy &amp; hold ($(year[1])–$(year[end]))</text>
""")

# equity gridlines (nice multiples within range)
for k in (1, 2, 5, 10, 20, 50, 100)
    v = log10(k)
    (v < ymin - 1e-9 || v > ymax + 1e-9) && continue
    y = y1(v)
    print(io, "<line x1=\"$L\" y1=\"$(round(y;digits=1))\" x2=\"$(L+PW)\" y2=\"$(round(y;digits=1))\" stroke=\"#e6e6e6\"/>")
    print(io, "<text x=\"$(L-8)\" y=\"$(round(y+4;digits=1))\" font-size=\"12\" text-anchor=\"end\" fill=\"#555\">$(k)x</text>")
end
print(io, "<text x=\"16\" y=\"$(Tm+P1H/2)\" font-size=\"12\" fill=\"#555\" transform=\"rotate(-90 16 $(Tm+P1H/2))\" text-anchor=\"middle\">growth of \$1 (log)</text>")

# drawdown gridlines
for d in (0.0, -0.2, -0.4, -0.6, -0.8)
    d < mindd - 1e-9 && continue
    y = y2(d)
    print(io, "<line x1=\"$L\" y1=\"$(round(y;digits=1))\" x2=\"$(L+PW)\" y2=\"$(round(y;digits=1))\" stroke=\"#e6e6e6\"/>")
    print(io, "<text x=\"$(L-8)\" y=\"$(round(y+4;digits=1))\" font-size=\"12\" text-anchor=\"end\" fill=\"#555\">$(round(Int,100d))%</text>")
end
print(io, "<text x=\"16\" y=\"$(P2T+P2H/2)\" font-size=\"12\" fill=\"#555\" transform=\"rotate(-90 16 $(P2T+P2H/2))\" text-anchor=\"middle\">drawdown</text>")

# x-axis year labels (every 3rd year)
let lastyr = 0
    for i in 1:n
        if year[i] != lastyr && year[i] % 3 == 0 && (i == 1 || year[i] != year[i-1])
            x = round(xat(i); digits=1)
            print(io, "<line x1=\"$x\" y1=\"$Tm\" x2=\"$x\" y2=\"$(Tm+P1H)\" stroke=\"#f2f2f2\"/>")
            print(io, "<line x1=\"$x\" y1=\"$P2T\" x2=\"$x\" y2=\"$(P2T+P2H)\" stroke=\"#f2f2f2\"/>")
            print(io, "<text x=\"$x\" y=\"$(H-22)\" font-size=\"12\" text-anchor=\"middle\" fill=\"#555\">$(year[i])</text>")
            lastyr = year[i]
        end
    end
end

const CBH = "#888888"   # buy & hold
const CFL = "#1f6feb"   # flagship

# equity curves
print(io, polyline([xat(i) for i in 1:n], [y1(log10bh[i]) for i in 1:n], CBH, 1.6))
print(io, polyline([xat(i) for i in 1:n], [y1(log10fl[i]) for i in 1:n], CFL, 1.6))
# drawdown curves
print(io, polyline([xat(i) for i in 1:n], [y2(ddb[i]) for i in 1:n], CBH, 1.2))
print(io, polyline([xat(i) for i in 1:n], [y2(ddf[i]) for i in 1:n], CFL, 1.4))

# panel borders
print(io, "<rect x=\"$L\" y=\"$Tm\" width=\"$PW\" height=\"$P1H\" fill=\"none\" stroke=\"#cccccc\"/>")
print(io, "<rect x=\"$L\" y=\"$P2T\" width=\"$PW\" height=\"$P2H\" fill=\"none\" stroke=\"#cccccc\"/>")

# legend
lx = L + PW + 16; ly = Tm + 8
print(io, "<line x1=\"$lx\" y1=\"$ly\" x2=\"$(lx+26)\" y2=\"$ly\" stroke=\"$CFL\" stroke-width=\"2.4\"/>")
print(io, "<text x=\"$(lx+32)\" y=\"$(ly+4)\" font-size=\"13\">$flagname</text>")
print(io, "<line x1=\"$lx\" y1=\"$(ly+22)\" x2=\"$(lx+26)\" y2=\"$(ly+22)\" stroke=\"$CBH\" stroke-width=\"2.4\"/>")
print(io, "<text x=\"$(lx+32)\" y=\"$(ly+26)\" font-size=\"13\">buy &amp; hold</text>")
print(io, "<text x=\"$lx\" y=\"$(ly+60)\" font-size=\"12\" fill=\"#333\">CAGR $(fmtpct(summ["cagr"][1])) / $(fmtpct(summ["cagr"][2]))</text>")
print(io, "<text x=\"$lx\" y=\"$(ly+78)\" font-size=\"12\" fill=\"#333\">maxDD $(fmtpct(summ["maxdd"][1])) / $(fmtpct(summ["maxdd"][2]))</text>")
print(io, "<text x=\"$lx\" y=\"$(ly+96)\" font-size=\"12\" fill=\"#333\">final $(fmtx(summ["total"][1])) / $(fmtx(summ["total"][2]))</text>")

print(io, "</svg>")
write(SVG, take!(io))
println("Wrote ", SVG)

# optional PNG (aspect-preserving; macOS qlmanage crops wide SVGs into squares — don't use it)
let rsvg = Sys.which("rsvg-convert")
    rsvg !== nothing && run(`$rsvg -w 1600 $SVG -o $(replace(SVG, ".svg" => ".png"))`)
end
