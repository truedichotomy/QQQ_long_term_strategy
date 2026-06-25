# The adopted QQQ blend overlay on a real daily index, same code / engine / params
# as the QQQ study. Set TICKER below. Price index (no dividends); cash earns rf.
const TICKER, INDEXNAME = "SPX", "S&P 500"
using Dates, Printf, Statistics
include(joinpath(dirname(@__DIR__), "QQQBacktest.jl")); using .QQQBacktest

d = load_ticker(TICKER; dir=joinpath(dirname(dirname(@__DIR__)), "data"))
dates, close = d.date, d.close
@printf("%s (%s): %s .. %s  (%d days)  %.0f -> %.0f\n",
        TICKER, INDEXNAME, dates[1], dates[end], length(d), close[1], close[end])

mom, trend = blend_components(d)
sigs = ["buy & hold"=>buyhold(d), "trend (50/200 fast-reentry)"=>trend,
        "momentum (CCI40/TMA200)"=>mom, "either-on (adopted)"=>blend_either_on(d),
        "avg (½-size)"=>blend_avg(d)]

function table(rf)
    @printf("\n========  cash %.0f%%/yr, 5 bps/trade  ========\n", 100rf)
    println(METRIC_HEADER)
    res = Dict{String,Any}()
    for (name,s) in sigs
        b = run_backtest(d, s; cost=5e-4, rf_annual=rf)
        println(metric_row(name, compute_metrics(b)))
        res[name] = b
    end
    res
end
res = table(0.04)
table(0.00); table(0.05)

bh = res["buy & hold"]; dd = drawdown_series(bh.eq); itr = argmin(dd); ipk = argmax(bh.eq[1:itr])
@printf("\nBuy & hold worst drawdown: %.1f%%  peak %s (%.0f) -> trough %s (%.0f)\n",
        100dd[itr], dates[ipk], close[ipk], dates[itr], close[itr])
for nm in ["either-on (adopted)","avg (½-size)"]
    @printf("  %-20s in that window: %.1f%%   full-period maxDD %.1f%%\n",
            nm, 100*(res[nm].eq[itr]/maximum(res[nm].eq[1:itr])-1), 100*max_drawdown(res[nm].eq))
end

idxof(t) = (j=findfirst(>=(t), dates); j===nothing ? length(dates) : j)
spanret(eq,i0,i1) = eq[i1]/eq[i0]-1
spandd(eq,i0,i1)  = max_drawdown(@view eq[i0:i1])
master = [("1973-74 bear",   Date(1973,1,1),  Date(1974,12,31)),
          ("1980s bull",     Date(1982,8,1),  Date(1987,8,31)),
          ("1987 crash",     Date(1987,8,1),  Date(1987,12,31)),
          ("1990s bull",     Date(1990,10,1), Date(2000,3,24)),
          ("dot-com crash",  Date(2000,3,24), Date(2002,10,9)),
          ("GFC",            Date(2007,10,9), Date(2009,3,9)),
          ("2009-2020 bull", Date(2009,3,9),  Date(2020,2,19)),
          ("COVID crash",    Date(2020,2,19), Date(2020,3,23)),
          ("2022 bear",      Date(2022,1,3),  Date(2022,10,12))]
regimes = [(nm,a,b) for (nm,a,b) in master if a >= dates[1] && b <= dates[end]]
push!(regimes, ("FULL "*string(year(dates[1]))*"-"*string(year(dates[end])), dates[1], dates[end]))
println("\nRegime breakdown — total return over span / deepest drawdown within:")
@printf("%-18s %-9s %16s %16s %16s\n","regime","yrs","buy & hold","either-on","avg(½)")
for (nm,a,bb) in regimes
    i0,i1 = idxof(a), idxof(bb); yrs = Dates.value(dates[i1]-dates[i0])/365.25
    cell(k)=@sprintf("%+6.0f%% /%4.0f%%",100*spanret(res[k].eq,i0,i1),100*spandd(res[k].eq,i0,i1))
    @printf("%-18s %-9.1f %16s %16s %16s\n", nm, yrs,
            cell("buy & hold"), cell("either-on (adopted)"), cell("avg (½-size)"))
end

function rollwin(res, k, win=252*5)
    eqk, eqb = res[k].eq, res["buy & hold"].eq; n=length(eqk); rb=0; db=0; c=0
    for i in 1:(n-win)
        c+=1
        (eqk[i+win]/eqk[i] > eqb[i+win]/eqb[i]) && (rb+=1)
        (max_drawdown(@view eqk[i:i+win]) > max_drawdown(@view eqb[i:i+win])) && (db+=1)
    end
    (100rb/c, 100db/c)
end
println("\nRolling 5-yr windows vs buy & hold  (return-beat % / shallower-drawdown %):")
for k in ["either-on (adopted)","avg (½-size)"]
    r,dw = rollwin(res,k); @printf("  %-20s %2.0f%% / %2.0f%%\n", k, r, dw)
end
