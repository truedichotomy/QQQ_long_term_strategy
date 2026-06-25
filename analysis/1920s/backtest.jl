# Run the adopted QQQ blend overlay on the DJIA 1920-1955 series extracted from
# the screenshot. "Treat DJIA like QQQ": the SAME strategy code (blend_either_on /
# blend_avg from src/strategies.jl) via the SAME engine. Only-a-close is recoverable
# from a line chart, so O=H=L=C (CCI then uses the close as its typical price).
using Dates, Printf, Statistics
include(joinpath(dirname(@__DIR__), "QQQBacktest.jl")); using .QQQBacktest

# --- load the interpolated business-day series into a MarketData --------------
lines = readlines(joinpath(@__DIR__, "djia_daily.csv"))[2:end]
dates = [Date(split(l,",")[1]) for l in lines]
close = [parse(Float64, split(l,",")[2]) for l in lines]
d = MarketData("DJIA", dates, copy(close), copy(close), copy(close), copy(close), zeros(length(close)))
@printf("DJIA series: %s .. %s  (%d business days)  %.0f -> %.0f\n\n",
        dates[1], dates[end], length(dates), close[1], close[end])

# --- signals (identical parameters to the adopted QQQ blend) ------------------
mom, trend = blend_components(d)
either = blend_either_on(d)
avg    = blend_avg(d)
sigs = ["buy & hold"=>buyhold(d), "trend (50/200 fast-reentry)"=>trend,
        "momentum (CCI40/TMA200)"=>mom, "either-on (adopted)"=>either, "avg (½-size)"=>avg]

function table(rf)
    @printf("\n========  cash %.0f%%/yr, 5 bps/trade  ========\n", 100rf)
    println(METRIC_HEADER)
    res = Dict{String,Any}()
    for (name,s) in sigs
        b = run_backtest(d, s; cost=5e-4, rf_annual=rf)
        println(metric_row(name, compute_metrics(b)))
        res[name] = b
    end
    return res
end
res = table(0.01)
table(0.00); table(0.04)

# --- where buy & hold bled: the Great Depression drawdown --------------------
bh = res["buy & hold"]
dd = drawdown_series(bh.eq); itr = argmin(dd); ipk = argmax(bh.eq[1:itr])
@printf("\nBuy & hold worst drawdown: %.1f%%  peak %s (%.0f) -> trough %s (%.0f)\n",
        100*dd[itr], dates[ipk], close[ipk], dates[itr], close[itr])
for nm in ["either-on (adopted)","avg (½-size)"]
    @printf("  %-20s same-window drawdown: %.1f%%   full-period maxDD %.1f%%\n",
            nm, 100*(res[nm].eq[itr]/maximum(res[nm].eq[1:itr])-1),
            100*max_drawdown(res[nm].eq))
end

# --- trade timeline around the big turns -------------------------------------
function trades(b, from, to)
    out = Tuple{Date,Float64,Float64}[]
    for i in 2:length(b.pos)
        if b.pos[i] != b.pos[i-1] && from <= dates[i] <= to
            push!(out, (dates[i], b.pos[i], close[i]))
        end
    end
    out
end
println("\nEither-on position changes through the Crash & Depression (1929-1934):")
for (dt,p,pr) in trades(res["either-on (adopted)"], Date(1929,1,1), Date(1934,12,31))
    @printf("  %s  -> %3.0f%% invested   (DJIA %.0f)\n", dt, 100p, pr)
end
println("Either-on position changes 1937-1942 & 1946-1949:")
for (dt,p,pr) in vcat(trades(res["either-on (adopted)"], Date(1937,1,1), Date(1942,12,31)),
                      trades(res["either-on (adopted)"], Date(1946,1,1), Date(1949,12,31)))
    @printf("  %s  -> %3.0f%% invested   (DJIA %.0f)\n", dt, 100p, pr)
end

# --- regime sub-period table (total return over span / deepest dd within) ----
regimes = [("1920-21 post-WWI bear", Date(1920,1,1), Date(1921,8,31)),
           ("Roaring 20s bull",      Date(1921,8,1), Date(1929,9,30)),
           ("Crash + Depression",    Date(1929,9,1), Date(1932,7,31)),
           ("New Deal recovery",     Date(1932,7,1), Date(1937,3,31)),
           ("1937-38 recession",     Date(1937,3,1), Date(1938,4,30)),
           ("WWII era",              Date(1938,4,1), Date(1945,12,31)),
           ("Postwar bull",          Date(1949,6,1), Date(1955,12,30)),
           ("FULL 1920-1955",        Date(1920,1,1), Date(1955,12,30))]
idxof(t) = clamp(findfirst(>=(t), dates) === nothing ? length(dates) : findfirst(>=(t), dates), 1, length(dates))
spanret(eq,i0,i1) = eq[i1]/eq[i0]-1
spandd(eq,i0,i1)  = max_drawdown(@view eq[i0:i1])
println("\nRegime breakdown — total return over span / deepest drawdown within:")
@printf("%-24s %-13s %16s %16s %16s\n","regime","span(yrs)","buy & hold","either-on","avg(½)")
for (nm,a,bb) in regimes
    i0,i1 = idxof(a), idxof(bb); yrs = Dates.value(dates[i1]-dates[i0])/365.25
    cell(k)=@sprintf("%+5.0f%% / %4.0f%%",100*spanret(res[k].eq,i0,i1),100*spandd(res[k].eq,i0,i1))
    @printf("%-24s %-13.1f %16s %16s %16s\n", nm, yrs,
            cell("buy & hold"), cell("either-on (adopted)"), cell("avg (½-size)"))
end
