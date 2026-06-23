# Close-up on the 1999-2009 "lost decade" — the dataset's hardest stretch, with
# BOTH the dot-com crash (2000-2002) and the global financial crisis (2007-2009).
# Buy-and-hold lost money over these ~11 years; this is where timing rules earn
# (or fail to earn) their keep. We compare the headline strategies over the full
# window, then break it into sub-regimes, then year by year.
#
# Signals are built on FULL history then sliced, but this window starts at data
# inception (1999-03-10), so the 50/200-day filters are necessarily in cash for
# their first ~200 days (warm-up) — they miss the final late-1999 melt-up, which
# also means they enter the dot-com crash already defensive. Noted, not hidden.
#
#   julia --startup-file=no analysis/period_1999_2009.jl

include(joinpath(dirname(@__DIR__), "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST, RF = 5e-4, 0.04
const DATADIR = joinpath(dirname(dirname(@__DIR__)), "data")
bt(d, sig) = run_backtest(d, sig; cost=COST, rf_annual=RF)

function slice_md(d::MarketData, i0::Integer, i1::Integer)
    MarketData(d.ticker, d.date[i0:i1], d.open[i0:i1], d.high[i0:i1],
               d.low[i0:i1], d.close[i0:i1], d.volume[i0:i1])
end

d = load_ticker("QQQ"; dir=DATADIR)

# headline strategy set (name => full-history signal)
strategies = [
    ("buy & hold",            buyhold(d)),
    ("SMA filter 200",        sma_filter(d; n=200)),
    ("Conservative 50/200",   sma_cross(d; fast=50, slow=200)),
    ("Standard fast-reentry", fast_reentry(d; fast=50, slow=200, re=50, hold=10)),
    ("CCI(50) band -120/-40", cci_band(d; n=50, exit_lo=-120, entry_hi=-40)),
    ("CCI(40)>0",             cci_trend(d; lo=0)),
]

# ---- full-window metrics table ----
i0, i1 = date_range(d, Date(1999,3,10), Date(2009,12,31))
dw = slice_md(d, i0, i1)
println("="^100)
@printf("FULL WINDOW  %s … %s  (%d trading days, %.1f yrs)\n", dw.date[1], dw.date[end], length(dw),
        Dates.value(dw.date[end]-dw.date[1])/365.25)
println("="^100)
println(METRIC_HEADER)
println("-"^96)
for (name, sig) in strategies
    println(metric_row(name, compute_metrics(bt(dw, sig[i0:i1]))))
end

# ---- sub-regime breakdown: total return over the span / deepest drawdown within it ----
regimes = [
    ("Late-'99 run-up",   Date(1999,3,10),  Date(2000,3,10)),
    ("Dot-com crash",     Date(2000,3,10),  Date(2002,10,9)),
    ("Mid-2000s recovery",Date(2002,10,9),  Date(2007,10,31)),
    ("GFC bear",          Date(2007,10,31), Date(2009,3,9)),
    ("Post-GFC rebound",  Date(2009,3,9),   Date(2009,12,31)),
]
println("\n", "="^100)
println("SUB-REGIME BREAKDOWN — total return over span (top) / deepest drawdown within span (bottom)")
println("="^100)
@printf("%-24s", "strategy")
for (lbl, _, _) in regimes; @printf("%14s", lbl[1:min(end,13)]); end
println()
println("-"^(24 + 14*length(regimes)))
for (name, sig) in strategies
    @printf("%-24s", name)
    for (_, from, to) in regimes
        a, b = date_range(d, from, to)
        m = compute_metrics(bt(slice_md(d, a, b), sig[a:b]))
        @printf("%14s", @sprintf("%+.0f%%/%.0f%%", 100m.total_return, 100m.maxdd))
    end
    println()
end

# ---- year-by-year total return ----
println("\n", "="^100)
println("ANNUAL TOTAL RETURN (%)")
println("="^100)
years = 1999:2009
@printf("%-24s", "strategy")
for y in years; @printf("%7d", y); end
@printf("%9s\n", "1999-09")
println("-"^(24 + 7*length(years) + 9))
for (name, sig) in strategies
    b = bt(dw, sig[i0:i1])
    @printf("%-24s", name)
    for y in years
        ja, jb = date_range(dw, Date(y,1,1), Date(y,12,31))
        r = b.eq[jb]/b.eq[ja] - 1
        @printf("%6.0f%%", 100r)
    end
    @printf("%8.0f%%\n", 100*(b.eq[end]/b.eq[1] - 1))
end
println("\n  Cells in sub-regime table: total return / max drawdown within that span.")
println("  Trend filters are in cash during their first ~200d (indicator warm-up at data inception).")
