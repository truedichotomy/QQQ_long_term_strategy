# Chart: the QQQ blend overlay applied to DJIA 1920-1955 (extracted from the
# screenshot). Top panel: DJIA (log) with the either-on overlay's OUT-of-market
# stretches shaded — you can see it step aside for 1929-32, 1937, 1946. Bottom:
# growth of $1 (log), buy & hold vs either-on vs avg.  Pure base-Julia SVG.
#   julia analysis/1920s/plot.jl   ->  djia_blend_1920_1955.svg
using Dates, Printf
include(joinpath(dirname(@__DIR__), "QQQBacktest.jl")); using .QQQBacktest

lines = readlines(joinpath(@__DIR__,"djia_daily.csv"))[2:end]
dates = [Date(split(l,",")[1]) for l in lines]
close = [parse(Float64, split(l,",")[2]) for l in lines]
d = MarketData("DJIA", dates, copy(close), copy(close), copy(close), copy(close), zeros(length(close)))
mom, trend = blend_components(d)
bt(s) = run_backtest(d, s; cost=5e-4, rf_annual=0.01)
bh = bt(buyhold(d)); eo = bt(blend_either_on(d)); av = bt(blend_avg(d))
n = length(d); yr = year.(dates)

W,H,L,R,Tm,Bm,GAP,P1H = 1060,720,70,150,40,46,46,300
P2T = Tm+P1H+GAP; P2H = H-P2T-Bm; PW = W-L-R
xat(i) = L + (i-1)/(n-1)*PW
# top panel: log price
pmin,pmax = log10(minimum(close)), log10(maximum(close))
y1(v) = Tm + (1-(log10(v)-pmin)/(pmax-pmin))*P1H
# bottom panel: log growth of $1
curves = [("buy & hold","#888888",bh.eq),("either-on","#d1242f",eo.eq),("avg (½)","#1f6feb",av.eq)]
logs = [log10.(c[3]) for c in curves]
gmin = minimum(minimum,logs); gmax = maximum(maximum,logs)
y2(v) = P2T + (1-(log10(v)-gmin)/(gmax-gmin))*P2H
poly(xs,ys,col,w) = string("<polyline fill=\"none\" stroke=\"",col,"\" stroke-width=\"",w,
    "\" points=\"",join((string(round(xs[i];digits=1),",",round(ys[i];digits=1)) for i in eachindex(xs))," "),"\"/>")

io = IOBuffer()
print(io,"""<svg xmlns="http://www.w3.org/2000/svg" width="$W" height="$H" viewBox="0 0 $W $H" font-family="Helvetica,Arial,sans-serif">
<rect width="$W" height="$H" fill="white"/>
<text x="$L" y="22" font-size="17" font-weight="bold">DJIA 1920–1955 (extracted from chart) — the QQQ either-on blend overlay vs buy &amp; hold</text>
<text x="$L" y="40" font-size="12" fill="#555">Top: DJIA index (log), red bands = overlay in CASH.  Bottom: growth of \$1 (log), 1%/yr cash while out.</text>
""")
# out-of-market shading (either-on pos==0)
let i=1
    while i<=n
        if eo.pos[i]==0
            j=i; while j<n && eo.pos[j+1]==0; j+=1; end
            x0=round(xat(i);digits=1); x1=round(xat(j);digits=1)
            print(io,"<rect x=\"$x0\" y=\"$Tm\" width=\"$(round(x1-x0+0.6;digits=1))\" height=\"$P1H\" fill=\"#d1242f\" fill-opacity=\"0.12\"/>")
            i=j+1
        else; i+=1; end
    end
end
# price gridlines
for v in (40,60,100,150,200,300,400,500)
    (v<minimum(close)||v>maximum(close)) && continue
    y=round(y1(v);digits=1)
    print(io,"<line x1=\"$L\" y1=\"$y\" x2=\"$(L+PW)\" y2=\"$y\" stroke=\"#eee\"/><text x=\"$(L-8)\" y=\"$(y+4)\" font-size=\"12\" text-anchor=\"end\" fill=\"#555\">$v</text>")
end
const ST = 3                       # subsample polylines (keeps file light & crisp)
idxs = unique(vcat(collect(1:ST:n), n))
print(io,poly([xat(i) for i in idxs],[y1(close[i]) for i in idxs],"#222",1.4))
print(io,"<text x=\"16\" y=\"$(Tm+P1H÷2)\" font-size=\"12\" fill=\"#555\" transform=\"rotate(-90 16 $(Tm+P1H÷2))\" text-anchor=\"middle\">DJIA index (log)</text>")
# growth gridlines
for k in (1,2,5,10,20,50,100)
    v=log10(k); (v<gmin||v>gmax) && continue
    y=round(y2(k);digits=1)
    print(io,"<line x1=\"$L\" y1=\"$y\" x2=\"$(L+PW)\" y2=\"$y\" stroke=\"#eee\"/><text x=\"$(L-8)\" y=\"$(y+4)\" font-size=\"12\" text-anchor=\"end\" fill=\"#555\">$(k)x</text>")
end
for (nm,col,eq) in curves
    print(io,poly([xat(i) for i in idxs],[y2(eq[i]) for i in idxs],col, nm=="buy & hold" ? 1.4 : 1.8))
end
print(io,"<text x=\"16\" y=\"$(P2T+P2H÷2)\" font-size=\"12\" fill=\"#555\" transform=\"rotate(-90 16 $(P2T+P2H÷2))\" text-anchor=\"middle\">growth of \$1 (log)</text>")
# year ticks
let last=0
    for i in 1:n
        if yr[i]%3==0 && (i==1||yr[i]!=yr[i-1]) && yr[i]!=last
            x=round(xat(i);digits=1)
            print(io,"<line x1=\"$x\" y1=\"$Tm\" x2=\"$x\" y2=\"$(Tm+P1H)\" stroke=\"#f6f6f6\"/><line x1=\"$x\" y1=\"$P2T\" x2=\"$x\" y2=\"$(P2T+P2H)\" stroke=\"#f6f6f6\"/><text x=\"$x\" y=\"$(H-24)\" font-size=\"11\" text-anchor=\"middle\" fill=\"#555\">$(yr[i])</text>")
            last=yr[i]
        end
    end
end
# legend + endpoint labels
lx=L+10; ly=P2T+16
for (nm,col,eq) in curves
    disp = replace(nm, "&"=>"&amp;")
    print(io,"<rect x=\"$lx\" y=\"$(ly-9)\" width=\"14\" height=\"4\" fill=\"$col\"/><text x=\"$(lx+19)\" y=\"$(ly-4)\" font-size=\"12\" fill=\"#333\">$disp ($(Int(round(eq[end])))x)</text>"); global ly+=18
end
print(io,"</svg>")
write(joinpath(@__DIR__,"djia_blend_1920_1955.svg"), String(take!(io)))
println("wrote djia_blend_1920_1955.svg")
