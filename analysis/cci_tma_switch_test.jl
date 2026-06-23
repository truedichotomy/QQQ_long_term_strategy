# Test the CCI(40) -120/0 band with a 200-day TRIANGULAR-MA-slope switch to
# CCI(40)>0, plus 2-day confirmation on buy/sell signals. Ablations isolate what
# the TMA switch and the confirmation each add. Compared against the prior pick
# (CCI(50) -120/-40) and Standard fast-reentry across the key windows.
#
# Same assumptions: 1-day lag, 5 bps cost, cash 4%/yr. Signals built on full
# history then sliced. The switch fires when TMA(200) is below its value `lb`
# days ago; entry/exit each need `confirm` consecutive days.
#
#   julia --startup-file=no analysis/cci_tma_switch_test.jl

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

S(; bear_exit, confirm) = cci_band_tma_switch(d; exit_lo=-120, entry_hi=0,
                                              bear_exit=bear_exit, tma_n=200, lb=20, confirm=confirm)

strategies = [
    ("buy & hold",                buyhold(d)),
    ("CCI40 -120/0 plain",        S(bear_exit=-120, confirm=1)),
    ("  + 2d confirm only",       S(bear_exit=-120, confirm=2)),
    ("  + TMA switch only",       S(bear_exit=0,    confirm=1)),
    ("FULL: TMA switch + 2d",     S(bear_exit=0,    confirm=2)),
    ("ref CCI(50) -120/-40",      cci_band(d; n=50, exit_lo=-120, entry_hi=-40)),
    ("ref Standard fast-reentry", fast_reentry(d; fast=50, slow=200, re=50, hold=10)),
]

# how often is the TMA(200)-slope bear gate active?
t = tma(d.close, 200); lb = 20
bear = [i > lb && !isnan(t[i]) && !isnan(t[i-lb]) && t[i] < t[i-lb] for i in 1:length(d)]
@printf("TMA(200)-slope bear gate active %.0f%% of days, full history (vs 16%% for the dual-SMA gate).\n",
        100mean(bear))

function table(label, i0, i1)
    dw = slice_md(d, i0, i1)
    println("\n", "="^96)
    @printf("%s  %s … %s\n", label, dw.date[1], dw.date[end]); println("="^96)
    println(METRIC_HEADER); println("-"^96)
    for (name, sig) in strategies
        println(metric_row(name, compute_metrics(bt(dw, sig[i0:i1]))))
    end
end

for (label, from, to) in [
        ("LOST DECADE",   Date(1999,3,10),  Date(2009,12,31)),
        ("  dot-com bear",Date(2000,3,10),  Date(2002,10,9)),
        ("  GFC bear",    Date(2007,10,31), Date(2009,3,9)),
        ("RECENT DECADE", Date(2016,5,31),  Date(2026,5,29)),
        ("FULL 20YR",     Date(2006,5,30),  Date(2026,5,29)),
        ("FULL HISTORY",  Date(1999,3,10),  Date(2026,5,29))]
    a, b = date_range(d, from, to)
    table(label, a, b)
end

println("\n  Rule: CCI(40) band -120/0; when TMA(200) slope<0, exit threshold tightens to 0 (= CCI40>0).")
println("  Entry (CCI40>0) and exit each require 2 consecutive days. Rows 2-5 ablate the two additions.")
