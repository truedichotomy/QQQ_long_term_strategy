# Sensitivity of the CCI(50) hysteresis rule to the BUY (re-entry) threshold.
#
#   Rule: sell to cash when CCI(50) < -120 (held fixed); re-enter when
#   CCI(50) > entry_hi. Sweep entry_hi from -100 (snap back in on any bounce
#   off the washout) to +100 (wait for strong positive momentum first).
#   Same assumptions as run_analysis.jl (1-day lag, 5 bps cost, cash 4%/yr).
#
#   julia --startup-file=no analysis/cci_band_buy_sweep.jl

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST = 5e-4
const RF   = 0.04
const DATADIR = joinpath(dirname(@__DIR__), "data")
const SELL = -120   # exit threshold held fixed

bt(d, sig) = run_backtest(d, sig; cost=COST, rf_annual=RF)

function slice_md(d::MarketData, i0::Integer, i1::Integer)
    MarketData(d.ticker, d.date[i0:i1], d.open[i0:i1], d.high[i0:i1],
               d.low[i0:i1], d.close[i0:i1], d.volume[i0:i1])
end

d = load_ticker("QQQ"; dir=DATADIR)
cutoff = d.date[end] - Year(10)
i0 = findfirst(>=(cutoff), d.date); i1 = length(d)
dw = slice_md(d, i0, i1)

const BUYS = collect(-100:20:100)   # -100, -80, ... 100

function sweep(label, d_, slice_idx)
    println("\n", "="^80, "\n", label, "  (", d_.date[1], " … ", d_.date[end], ")   sell fixed @ CCI<", SELL)
    println("="^80)
    bh = compute_metrics(bt(d_, ones(length(d_))))
    @printf("  buy & hold:  CAGR %.2f%%   maxDD %.1f%%   Calmar %.2f\n\n", 100bh.cagr, 100bh.maxdd, bh.calmar)
    @printf("  %-8s %8s %8s %8s %7s %7s %7s %6s %7s %s\n",
            "buy@", "CAGR", "vs B&H", "maxDD", "Sharpe", "Sortino", "Calmar", "%inv", "trades", "")
    println("  ", "-"^78)
    for hi in BUYS
        sig = cci_band(d; n=50, exit_lo=SELL, entry_hi=hi)
        sig = slice_idx === nothing ? sig : sig[slice_idx]
        m = compute_metrics(bt(d_, sig))
        best = m.calmar >= bh.calmar ? "◄ Calmar≥B&H" : ""
        @printf("  %-+8d %7.2f%% %+7.2f %7.1f%% %7.2f %7.2f %7.2f %5.0f%% %7d  %s\n",
                hi, 100m.cagr, 100*(m.cagr - bh.cagr), 100m.maxdd,
                m.sharpe, m.sortino, m.calmar, 100m.pct_invested,
                m.ntrades, best)
    end
end

sweep("LAST 10 YEARS", dw, i0:i1)
sweep("FULL HISTORY (context)", d, nothing)

println("\n  buy@ = CCI(50) level required to re-enter; sell fixed at CCI(50) < ", SELL, ".")
println("  vs B&H = CAGR difference in pp/yr.  Lower buy@ = re-enter sooner (less cash).\n")
