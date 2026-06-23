# Does the CCI(50) -120/-40 hysteresis rule hold over 20 years, and how does
# its sensitivity differ between the prior decade (2006-2016) and the recent
# one (2016-2026)? For each window we show the -120/-40 pick vs B&H, then the
# SELL sweep (buy fixed @ -40) and the BUY sweep (sell fixed @ -120).
#
# Same assumptions as run_analysis.jl: 1-day lag, 5 bps cost, cash 4%/yr.
# Signals are built on FULL history then sliced, so CCI(50) is warm and the
# position state carried into each window reflects real prior history.
#
#   julia --startup-file=no analysis/cci_band_20yr.jl

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST = 5e-4
const RF   = 0.04
const DATADIR = joinpath(dirname(@__DIR__), "data")
const SELL = -120     # fixed exit for the buy sweep
const BUY  = -40      # fixed re-entry for the sell sweep

bt(d, sig) = run_backtest(d, sig; cost=COST, rf_annual=RF)

function slice_md(d::MarketData, i0::Integer, i1::Integer)
    ind = Dict(k => v[i0:i1] for (k, v) in d.ind)
    MarketData(d.ticker, d.date[i0:i1], d.open[i0:i1], d.high[i0:i1],
               d.low[i0:i1], d.close[i0:i1], d.volume[i0:i1], ind)
end

d = load_ticker("QQQ"; dir=DATADIR)
iyr(y) = (i = findfirst(>=(d.date[end] - Year(y)), d.date); i === nothing ? 1 : i)
i20, i10, iend = iyr(20), iyr(10), length(d)

const WINDOWS = [
    ("PRIOR DECADE",  i20, i10 - 1),
    ("RECENT DECADE", i10, iend),
    ("FULL 20 YEARS", i20, iend),
]

const SELLS = collect(-50:-10:-150)
const BUYS  = collect(-100:20:100)

row(tag, m, bh) = @sprintf("  %-10s %7.2f%% %+7.2f %7.1f%% %7.2f %7.2f %7.2f %5.0f%% %7d  %s",
    tag, 100m.cagr, 100*(m.cagr - bh.cagr), 100m.maxdd, m.sharpe, m.sortino,
    m.calmar, 100m.pct_invested, m.ntrades, m.calmar >= bh.calmar ? "◄ Calmar≥B&H" : "")

hdr() = (@printf("  %-10s %8s %8s %8s %7s %7s %7s %6s %7s\n",
                 "param", "CAGR", "vs B&H", "maxDD", "Sharpe", "Sortino", "Calmar", "%inv", "trades");
         println("  ", "-"^80))

for (label, i0, i1) in WINDOWS
    dw = slice_md(d, i0, i1); n = length(dw)
    bh = compute_metrics(bt(dw, ones(n)))
    println("\n", "#"^82)
    @printf("# %s   %s … %s   (%d days)\n", label, dw.date[1], dw.date[end], n)
    @printf("# buy & hold:  CAGR %.2f%%   maxDD %.1f%%   Calmar %.2f\n", 100bh.cagr, 100bh.maxdd, bh.calmar)
    println("#"^82)

    pick = compute_metrics(bt(dw, cci_band(d; n=50, exit_lo=SELL, entry_hi=BUY)[i0:i1]))
    println("\n  -- headline pick (-120/-40) --"); hdr()
    println(row("-120/-40", pick, bh))

    println("\n  -- SELL sweep  (re-entry fixed @ CCI>", BUY, ") --"); hdr()
    for lo in SELLS
        m = compute_metrics(bt(dw, cci_band(d; n=50, exit_lo=lo, entry_hi=BUY)[i0:i1]))
        println(row(@sprintf("sell %d", lo), m, bh))
    end

    println("\n  -- BUY sweep  (exit fixed @ CCI<", SELL, ") --"); hdr()
    for hi in BUYS
        m = compute_metrics(bt(dw, cci_band(d; n=50, exit_lo=SELL, entry_hi=hi)[i0:i1]))
        println(row(@sprintf("buy %+d", hi), m, bh))
    end
end

println("\n  vs B&H = CAGR difference in pp/yr.  Signals built on full history, then sliced.\n")
