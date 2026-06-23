# Test the regime-switching CCI overlay: trade the wide CCI(50) -120/-40 band
# normally, but switch to the tighter CCI(40)>0 when BOTH the 50- and 200-day
# SMAs are sloping down (a confirmed sustained downtrend — the dot-com-grind
# signature the plain band fails against). Does it plug the 2000-2002 hole
# without degrading the modern-era numbers?
#
# Same assumptions: 1-day lag, 5 bps cost, cash 4%/yr. Signals built on full
# history then sliced (CCI/SMA warm, real carried-in state).
#
#   julia --startup-file=no analysis/cci_regime_switch_test.jl

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST, RF = 5e-4, 0.04
const DATADIR = joinpath(dirname(@__DIR__), "data")
bt(d, sig) = run_backtest(d, sig; cost=COST, rf_annual=RF)

function slice_md(d::MarketData, i0::Integer, i1::Integer)
    MarketData(d.ticker, d.date[i0:i1], d.open[i0:i1], d.high[i0:i1],
               d.low[i0:i1], d.close[i0:i1], d.volume[i0:i1])
end

d = load_ticker("QQQ"; dir=DATADIR)

strategies = [
    ("buy & hold",              buyhold(d)),
    ("CCI(50) band -120/-40",   cci_band(d; n=50, exit_lo=-120, entry_hi=-40)),
    ("CCI(40)>0",               cci_trend(d; lo=0)),
    ("CCI regime-switch",       cci_regime_switch(d; n=50, exit_lo=-120, entry_hi=-40, n40=40, lb=20)),
    ("Standard fast-reentry",   fast_reentry(d; fast=50, slow=200, re=50, hold=10)),
]

# how often is the bear-slope regime (→ CCI40>0) active, full history?
sf = sma(d.close, 50); ss = sma(d.close, 200); lb = 20
bear = [i > lb && !isnan(sf[i]) && !isnan(sf[i-lb]) && sf[i] < sf[i-lb] &&
        !isnan(ss[i]) && !isnan(ss[i-lb]) && ss[i] < ss[i-lb] for i in 1:length(d)]
@printf("Bear-slope regime (both SMAs falling) active %.0f%% of days, full history.\n", 100mean(bear))

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

println("\n  Switch rule: use CCI(40)>0 while both the 50- & 200-day SMAs are falling (20d lookback);")
println("  otherwise use the CCI(50) -120/-40 band.")
