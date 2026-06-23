# (b) lb / tma_n sensitivity and (c) asymmetric confirmation test for the
# CCI(40) -120/0 + TMA(200)-slope switch. Confirms the round 20/200 defaults
# aren't a lucky spike, and settles whether confirming only re-entries (keeping
# fast protective exits) beats confirming both or neither.
#
#   julia --startup-file=no analysis/cci_tma_robustness.jl

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST, RF = 5e-4, 0.04
const DATADIR = joinpath(dirname(@__DIR__), "data")
bt(d, sig) = run_backtest(d, sig; cost=COST, rf_annual=RF)
function slice_md(d::MarketData, i0::Integer, i1::Integer)
    ind = Dict(k => v[i0:i1] for (k, v) in d.ind)
    MarketData(d.ticker, d.date[i0:i1], d.open[i0:i1], d.high[i0:i1],
               d.low[i0:i1], d.close[i0:i1], d.volume[i0:i1], ind)
end
d = load_ticker("QQQ"; dir=DATADIR)

W(from, to) = date_range(d, from, to)
const FH = W(Date(1999,3,10),  Date(2026,5,29))   # full history
const RD = W(Date(2016,5,31),  Date(2026,5,29))   # recent decade
const DC = W(Date(2000,3,10),  Date(2002,10,9))   # dot-com bear
const GFC= W(Date(2007,10,31), Date(2009,3,9))    # GFC bear
ev(sig, w) = compute_metrics(bt(slice_md(d, w[1], w[2]), sig[w[1]:w[2]]))

# ============================================================================
# (b) lb (TMA-slope lookback) x tma_n (TMA period) sweep — switch-only, no confirm
# ============================================================================
println("="^86)
println("(b) PARAMETER SWEEP — CCI(40) -120/0 + TMA switch (no confirm). Round 20/200 lucky?")
println("="^86)
@printf("%-6s %-5s | %8s %8s %8s | %9s %9s %9s\n",
        "tma_n","lb","fullCAGR","fullDD","fullCalm","recCAGR","recDD","recCalm")
println("-"^86)
for tma_n in (100, 150, 200, 250), lb in (5, 10, 20, 40, 60)
    sig = cci_band_tma_switch(d; exit_lo=-120, entry_hi=0, bear_exit=0, tma_n=tma_n, lb=lb, confirm=1)
    mf = ev(sig, FH); mr = ev(sig, RD)
    star = (tma_n == 200 && lb == 20) ? " ◄ default" : ""
    @printf("%-6d %-5d | %7.2f%% %7.1f%% %8.2f | %8.2f%% %8.1f%% %8.2f%s\n",
            tma_n, lb, 100mf.cagr, 100mf.maxdd, mf.calmar, 100mr.cagr, 100mr.maxdd, mr.calmar, star)
end

# ============================================================================
# (c) asymmetric confirmation: (confirm_exit, confirm_entry)
# ============================================================================
println("\n", "="^96)
println("(c) CONFIRMATION — does confirming only RE-ENTRIES (fast exits kept) win? tma=200, lb=20")
println("="^96)
configs = [
    ("none (exit1/entry1)",          1, 1),
    ("fast exit / conf entry (1/2)", 1, 2),
    ("conf exit / fast entry (2/1)", 2, 1),
    ("both confirmed (2/2)",         2, 2),
]
@printf("%-30s | %8s %7s %7s | %7s %7s | %7s %7s\n",
        "config","fullCAGR","fullDD","fCalm","dotcomDD","gfcDD","recDD","recCalm")
println("-"^96)
for (name, ce, cn) in configs
    sig = cci_band_tma_switch(d; exit_lo=-120, entry_hi=0, bear_exit=0, tma_n=200, lb=20,
                              confirm_exit=ce, confirm_entry=cn)
    mf = ev(sig, FH); md = ev(sig, DC); mg = ev(sig, GFC); mr = ev(sig, RD)
    @printf("%-30s | %7.2f%% %6.1f%% %7.2f | %7.1f%% %6.1f%% | %6.1f%% %7.2f\n",
            name, 100mf.cagr, 100mf.maxdd, mf.calmar, 100md.maxdd, 100mg.maxdd, 100mr.maxdd, mr.calmar)
end
println("\n  DD columns are max drawdown within each window; fCalm/recCalm are Calmar.")
