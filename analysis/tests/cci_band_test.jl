# One-off study: the CCI(50) hysteresis-band rule on QQQ.
#
#   Rule: sell to cash when CCI(50) falls below -120; do not buy back until
#   CCI(50) climbs back above 0. Long/flat, signals lagged one day, 5 bps
#   turnover cost, cash earns 4%/yr (same assumptions as run_analysis.jl).
#
#   julia --startup-file=no analysis/cci_band_test.jl
#
# Scoped to the last 10 years of data, with full-history shown for context.

include(joinpath(dirname(@__DIR__), "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST = 5e-4
const RF   = 0.04
const DATADIR = joinpath(dirname(dirname(@__DIR__)), "data")

bt(d, sig) = run_backtest(d, sig; cost=COST, rf_annual=RF)

# Slice a MarketData to [i0, i1] (keeps precomputed indicators aligned).
function slice_md(d::MarketData, i0::Integer, i1::Integer)
    MarketData(d.ticker, d.date[i0:i1], d.open[i0:i1], d.high[i0:i1],
               d.low[i0:i1], d.close[i0:i1], d.volume[i0:i1])
end

d = load_ticker("QQQ"; dir=DATADIR)
@printf("Loaded QQQ: %d days, %s … %s\n", length(d), d.date[1], d.date[end])

# --- build the signal on FULL history (so CCI(50) is warm well before 2016) ----
# The position state carried into the 10-yr window reflects real prior history.
sig_full = cci_band(d; n=50, exit_lo=-120, entry_hi=0)
bh_full  = ones(length(d))

# --- scope to the last ~10 years ------------------------------------------------
cutoff = d.date[end] - Year(10)
i0 = findfirst(>=(cutoff), d.date)
i1 = length(d)
dw = slice_md(d, i0, i1)
@printf("10-year window: %s … %s  (%d trading days)\n", dw.date[1], dw.date[end], length(dw))

function report(label, d_, sig, bh)
    bs = bt(d_, sig); bb = bt(d_, bh)
    ms = compute_metrics(bs); mb = compute_metrics(bb)
    println("\n", "="^72, "\n", label, "  (", d_.date[1], " … ", d_.date[end], ")")
    println("="^72)
    println(METRIC_HEADER)
    println("-"^96)
    println(metric_row("CCI(50) band -120/0", ms))
    println(metric_row("buy & hold", mb))
    @printf("\n  CAGR     %+.2f pp/yr vs B&H   (%.2f%% vs %.2f%%)\n",
            100*(ms.cagr - mb.cagr), 100ms.cagr, 100mb.cagr)
    @printf("  Max DD   %.1f%% vs %.1f%% B&H  (%+.1f pp)\n", 100ms.maxdd, 100mb.maxdd, 100*(ms.maxdd - mb.maxdd))
    @printf("  Calmar   %.2f vs %.2f B&H        invested %.0f%% of the time, %d trades (≈%.1f/yr)\n",
            ms.calmar, mb.calmar, 100ms.pct_invested, ms.ntrades, ms.ntrades / ms.years)
    return bs
end

bs10 = report("LAST 10 YEARS", dw, sig_full[i0:i1], bh_full[i0:i1])
report("FULL HISTORY (context)", d, sig_full, bh_full)

# --- trade log over the 10-yr window -------------------------------------------
pos = bs10.pos
println("\nTrade log (last 10 years) — CCI(50) crossings acted on (1-day lag):")
@printf("  %-12s %-8s %s\n", "date", "action", "QQQ close")
for i in 2:length(dw)
    if pos[i] != pos[i-1]
        act = pos[i] > pos[i-1] ? "BUY" : "SELL"
        @printf("  %-12s %-8s %.2f\n", dw.date[i], act, dw.close[i])
    end
end
@printf("\nCurrent state (as of %s): %s\n", dw.date[end], pos[end] > 0 ? "INVESTED" : "CASH")
