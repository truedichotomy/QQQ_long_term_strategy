# Chart: the QQQ blend overlay on a real daily index. Two stacked panels — growth
# of $1 (log) and drawdown — buy & hold vs either-on vs avg. Pure base-Julia SVG.
const TICKER, INDEXNAME = "SPX", "S&P 500"
const SUBTITLE = "Same overlay as QQQ. On the S&amp;P it roughly matches buy &amp; hold on return while cutting drawdown by a third. Cash 4%/yr, 5 bps/trade."
using Dates, Printf
include(joinpath(dirname(@__DIR__), "QQQBacktest.jl")); using .QQQBacktest

d = load_ticker(TICKER; dir=joinpath(dirname(dirname(@__DIR__)), "data"))
n = length(d); yr = year.(d.date)
bt(s) = run_backtest(d, s; cost=5e-4, rf_annual=0.04).eq
curves = [("buy & hold","#888888",bt(buyhold(d))),
          ("either-on","#d1242f",bt(blend_either_on(d))),
          ("avg (½)","#1f6feb",bt(blend_avg(d)))]

W,H,L,R,Tm,Bm,GAP,P1H = 1060,720,72,150,40,46,46,360
P2T=Tm+P1H+GAP; P2H=H-P2T-Bm; PW=W-L-R
xat(i)=L+(i-1)/(n-1)*PW
logs=[log10.(c[3]) for c in curves]; gmin=minimum(minimum,logs); gmax=maximum(maximum,logs)
y1(v)=Tm+(1-(log10(v)-gmin)/(gmax-gmin))*P1H
dds=[drawdown_series(c[3]) for c in curves]; mindd=minimum(minimum,dds)
y2(x)=P2T+(x/mindd)*P2H
ST=3; idxs=unique(vcat(collect(1:ST:n),n))
poly(xs,ys,col,w)=string("<polyline fill=\"none\" stroke=\"",col,"\" stroke-width=\"",w,
  "\" points=\"",join((string(round(xs[i];digits=1),",",round(ys[i];digits=1)) for i in eachindex(xs))," "),"\"/>")
title = replace(INDEXNAME, "&"=>"&amp;")

io=IOBuffer()
print(io,"""<svg xmlns="http://www.w3.org/2000/svg" width="$W" height="$H" viewBox="0 0 $W $H" font-family="Helvetica,Arial,sans-serif">
<rect width="$W" height="$H" fill="white"/>
<text x="$L" y="22" font-size="17" font-weight="bold">$title $(yr[1])–$(yr[end]) (real daily) — the QQQ blend overlay vs buy &amp; hold</text>
<text x="$L" y="40" font-size="12" fill="#555">$SUBTITLE</text>
""")
for k in (1,2,5,10,20,50,100,200,500)
    v=log10(k); (v<gmin||v>gmax)&&continue; y=round(y1(k);digits=1)
    print(io,"<line x1=\"$L\" y1=\"$y\" x2=\"$(L+PW)\" y2=\"$y\" stroke=\"#eee\"/><text x=\"$(L-8)\" y=\"$(y+4)\" font-size=\"12\" text-anchor=\"end\" fill=\"#555\">$(k)x</text>")
end
for (nm,col,eq) in curves
    print(io,poly([xat(i) for i in idxs],[y1(eq[i]) for i in idxs],col, nm=="buy & hold" ? 1.6 : 1.8))
end
print(io,"<text x=\"16\" y=\"$(Tm+P1H÷2)\" font-size=\"12\" fill=\"#555\" transform=\"rotate(-90 16 $(Tm+P1H÷2))\" text-anchor=\"middle\">growth of \$1 (log)</text>")
for ddv in (0.0,-0.1,-0.2,-0.3,-0.4,-0.5,-0.6,-0.7,-0.8)
    ddv<mindd && continue; y=round(y2(ddv);digits=1)
    print(io,"<line x1=\"$L\" y1=\"$y\" x2=\"$(L+PW)\" y2=\"$y\" stroke=\"#eee\"/><text x=\"$(L-8)\" y=\"$(y+4)\" font-size=\"12\" text-anchor=\"end\" fill=\"#555\">$(round(Int,100ddv))%</text>")
end
for (nm,col,eq) in curves
    print(io,poly([xat(i) for i in idxs],[y2(dds[findfirst(c->c[1]==nm,curves)][i]) for i in idxs],col,nm=="buy & hold" ? 1.6 : 1.8))
end
print(io,"<text x=\"16\" y=\"$(P2T+P2H÷2)\" font-size=\"12\" fill=\"#555\" transform=\"rotate(-90 16 $(P2T+P2H÷2))\" text-anchor=\"middle\">drawdown</text>")
let last=0
    for i in 1:n
        if yr[i]%5==0 && (i==1||yr[i]!=yr[i-1]) && yr[i]!=last
            x=round(xat(i);digits=1)
            print(io,"<line x1=\"$x\" y1=\"$Tm\" x2=\"$x\" y2=\"$(Tm+P1H)\" stroke=\"#f6f6f6\"/><line x1=\"$x\" y1=\"$P2T\" x2=\"$x\" y2=\"$(P2T+P2H)\" stroke=\"#f6f6f6\"/><text x=\"$x\" y=\"$(H-24)\" font-size=\"11\" text-anchor=\"middle\" fill=\"#555\">$(yr[i])</text>")
            last=yr[i]
        end
    end
end
lx=L+10; ly=Tm+18
for (nm,col,eq) in curves
    disp=replace(nm,"&"=>"&amp;")
    print(io,"<rect x=\"$lx\" y=\"$(ly-9)\" width=\"14\" height=\"4\" fill=\"$col\"/><text x=\"$(lx+19)\" y=\"$(ly-4)\" font-size=\"12\" fill=\"#333\">$disp ($(Int(round(eq[end])))x)</text>"); global ly+=18
end
print(io,"</svg>")
write(joinpath(@__DIR__,"blend_$(TICKER)_$(yr[1])_$(yr[end]).svg"), String(take!(io)))
println("wrote blend_$(TICKER)_$(yr[1])_$(yr[end]).svg")
