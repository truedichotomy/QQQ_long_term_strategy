# Sensitivity of the CCI(50) hysteresis rule to the SELL threshold.
#
#   Rule: sell to cash when CCI(50) < exit_lo; re-enter when CCI(50) > 0.
#   Sweep exit_lo from -50 (twitchy) to -150 (only the deepest washouts).
#   Re-entry held fixed at 0. Same assumptions as run_analysis.jl
#   (1-day lag, 5 bps cost, cash 4%/yr).
#
#   julia --startup-file=no analysis/cci_band_sweep.jl

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST = 5e-4
const RF   = 0.04
const DATADIR = joinpath(dirname(@__DIR__), "data")

bt(d, sig) = run_backtest(d, sig; cost=COST, rf_annual=RF)

function slice_md(d::MarketData, i0::Integer, i1::Integer)
    MarketData(d.ticker, d.date[i0:i1], d.open[i0:i1], d.high[i0:i1],
               d.low[i0:i1], d.close[i0:i1], d.volume[i0:i1])
end

d = load_ticker("QQQ"; dir=DATADIR)
cutoff = d.date[end] - Year(10)
i0 = findfirst(>=(cutoff), d.date); i1 = length(d)
dw = slice_md(d, i0, i1)

const EXITS = collect(-50:-10:-150)   # -50, -60, ... -150

function sweep(label, d_, slice_idx)
    println("\n", "="^78, "\n", label, "  (", d_.date[1], " … ", d_.date[end], ")")
    println("="^78)
    bh = compute_metrics(bt(d_, ones(length(d_))))
    @printf("  buy & hold:  CAGR %.2f%%   maxDD %.1f%%   Calmar %.2f\n\n", 100bh.cagr, 100bh.maxdd, bh.calmar)
    @printf("  %-8s %8s %8s %8s %7s %7s %7s %6s %7s %s\n",
            "sell@", "CAGR", "vs B&H", "maxDD", "Sharpe", "Sortino", "Calmar", "%inv", "trades", "")
    println("  ", "-"^76)
    for lo in EXITS
        # build signal on full history (warm CCI, real carried-in state), then slice
        sig = cci_band(d; n=50, exit_lo=lo, entry_hi=0)
        sig = slice_idx === nothing ? sig : sig[slice_idx]
        m = compute_metrics(bt(d_, sig))
        best = m.calmar >= bh.calmar ? "◄ Calmar≥B&H" : ""
        @printf("  %-8d %7.2f%% %+7.2f %7.1f%% %7.2f %7.2f %7.2f %5.0f%% %7d  %s\n",
                lo, 100m.cagr, 100*(m.cagr - bh.cagr), 100m.maxdd,
                m.sharpe, m.sortino, m.calmar, 100m.pct_invested,
                m.ntrades, best)
    end
end

sweep("LAST 10 YEARS", dw, i0:i1)
sweep("FULL HISTORY (context)", d, nothing)

println("\n  sell@ = CCI(50) level that triggers the exit; re-entry fixed at CCI(50) > 0.")
println("  vs B&H = CAGR difference in pp/yr.\n")
