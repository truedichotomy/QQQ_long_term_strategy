# Detailed performance breakdown of the flagship (QQQ 50/200 golden cross) for
# the strategy document: by calendar year, by decade, and by historical regime,
# plus rolling-CAGR distributions. Writes results/{annual,period,rolling}_*.csv.
#
#   julia analysis/report.jl

include(joinpath(dirname(@__DIR__), "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST, RF = 5e-4, 0.04
const DATADIR = joinpath(dirname(dirname(@__DIR__)), "data")
const OUTDIR  = joinpath(dirname(@__DIR__), "results", "sma_study")
mkpath(OUTDIR)

d  = load_ticker("QQQ"; dir=DATADIR)
fl = run_backtest(d, sma_cross(d; fast=50, slow=200); cost=COST, rf_annual=RF)
bh = run_backtest(d, buyhold(d); cost=COST, rf_annual=RF)
yr = year.(d.date)

# ---- 1. by calendar year ----
println("Annual returns (QQQ buy & hold vs 50/200 strategy):")
@printf("%-6s %10s %10s %8s %8s\n", "year", "B&H", "strategy", "%inv", "edge")
println("-"^46)
lastidx = Dict{Int,Int}()
for i in eachindex(yr); lastidx[yr[i]] = i; end
years = sort(collect(keys(lastidx)))
annual = Tuple{Int,Float64,Float64,Float64}[]
prev = 1
for (k, y) in enumerate(years)
    i1 = lastidx[y]
    i0 = k == 1 ? 1 : lastidx[years[k - 1]]
    br = bh.eq[i1] / bh.eq[i0] - 1
    sr = fl.eq[i1] / fl.eq[i0] - 1
    inv = mean(@view fl.pos[i0 + 1:i1])
    push!(annual, (y, br, sr, inv))
    @printf("%-6d %9.1f%% %9.1f%% %7.0f%% %+7.1fpp\n", y, 100br, 100sr, 100inv, 100(sr - br))
    global prev = i1
end

# ---- 2. by decade ----
println("\nBy decade (annualized CAGR / max drawdown):")
@printf("%-12s | %-18s | %-18s\n", "decade", "buy & hold", "50/200 strategy")
println("-"^54)
decades = [(2000, 2009), (2010, 2019), (2020, 2026)]
function window_stats(i0, i1)
    es = fl.eq[i0:i1] ./ fl.eq[i0]; eb = bh.eq[i0:i1] ./ bh.eq[i0]
    yrs = max(Dates.value(d.date[i1] - d.date[i0]) / 365.25, 1e-9)
    return (sc=es[end]^(1 / yrs) - 1, bc=eb[end]^(1 / yrs) - 1,
            sdd=max_drawdown(es), bdd=max_drawdown(eb), st=es[end], bt=eb[end])
end
for (a, z) in decades
    i0, i1 = date_range(d, Date(a, 1, 1), Date(z, 12, 31))
    w = window_stats(i0, i1)
    @printf("%-12s | %6.1f%% / %6.1f%% | %6.1f%% / %6.1f%%\n",
            "$(a)s", 100w.bc, 100w.bdd, 100w.sc, 100w.sdd)
end

# ---- 3. by historical regime ----
periods = [
    ("Dot-com crash",     Date(2000,3,10),  Date(2002,10,9)),
    ("Mid-2000s recovery",Date(2002,10,9),  Date(2007,10,9)),
    ("Global financial cx",Date(2007,10,9), Date(2009,3,9)),
    ("2009–2020 bull",    Date(2009,3,9),   Date(2020,2,19)),
    ("COVID crash",       Date(2020,2,19),  Date(2020,3,23)),
    ("Post-COVID surge",  Date(2020,3,23),  Date(2021,11,19)),
    ("2022 bear",         Date(2021,11,19), Date(2022,12,28)),
    ("2023–2026 recovery",Date(2022,12,28), d.date[end]),
]
println("\nBy regime (total return over the span / max drawdown within it):")
@printf("%-20s %-12s | %-16s | %-16s\n", "regime", "span", "B&H ret/DD", "strat ret/DD")
println("-"^74)
open(joinpath(OUTDIR, "period_returns.csv"), "w") do io
    println(io, "regime,from,to,bh_total_return,strat_total_return,bh_maxdd,strat_maxdd")
    for (lbl, a, z) in periods
        i0, i1 = date_range(d, a, z)
        w = window_stats(i0, i1)
        @printf("%-20s %s | %+6.0f%% / %5.0f%% | %+6.0f%% / %5.0f%%\n",
                lbl, "$(year(a))–$(year(z))", 100(w.bt - 1), 100w.bdd, 100(w.st - 1), 100w.sdd)
        @printf(io, "%s,%s,%s,%.6f,%.6f,%.6f,%.6f\n", lbl, d.date[i0], d.date[i1],
                w.bt - 1, w.st - 1, w.bdd, w.sdd)
    end
end

# ---- 4. rolling CAGR distribution (return consistency by horizon) ----
println("\nRolling annualized-return distribution (worst / median / best across windows):")
@printf("%-6s | %-22s | %-22s\n", "horiz", "buy & hold", "50/200 strategy")
println("-"^54)
function roll_cagr(eq, win)
    out = Float64[]; a = 1
    while a + win <= length(eq)
        yrs = win / 252
        push!(out, (eq[a + win] / eq[a])^(1 / yrs) - 1)
        a += 21
    end
    return out
end
open(joinpath(OUTDIR, "rolling_cagr.csv"), "w") do io
    println(io, "horizon,bh_worst,bh_median,bh_best,strat_worst,strat_median,strat_best")
    for (win, lbl) in [(252, "1yr"), (756, "3yr"), (1260, "5yr"), (2520, "10yr")]
        win + 1 > length(d) && continue
        rb = roll_cagr(bh.eq, win); rs = roll_cagr(fl.eq, win)
        @printf("%-6s | %6.1f%% %6.1f%% %6.1f%% | %6.1f%% %6.1f%% %6.1f%%\n",
                lbl, 100minimum(rb), 100median(rb), 100maximum(rb),
                100minimum(rs), 100median(rs), 100maximum(rs))
        @printf(io, "%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n", lbl,
                minimum(rb), median(rb), maximum(rb), minimum(rs), median(rs), maximum(rs))
    end
end

open(joinpath(OUTDIR, "annual_returns.csv"), "w") do io
    println(io, "year,bh_return,strat_return,strat_pct_invested")
    for (y, br, sr, inv) in annual
        @printf(io, "%d,%.6f,%.6f,%.6f\n", y, br, sr, inv)
    end
end
println("\nWrote annual_returns.csv, period_returns.csv, rolling_cagr.csv to ", OUTDIR)
