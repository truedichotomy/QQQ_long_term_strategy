# Do the two finalists combine into something better than either alone? Their
# failure modes are complementary (SMA fast-reentry is blind to fast crashes;
# CCI40 TMA-trigger is weak in slow grinds), so a blend should diversify the
# drawdowns. Test three combinations against the two standalones.
#
#   avg     : exposure = (CCI + FR)/2  ∈ {0, ½, 1}  — half-size when they disagree
#   both-on : long only if BOTH are long (defensive; most cash)
#   either  : long if EITHER is long  (aggressive; most invested)
#
#   julia --startup-file=no analysis/finalists_blend_test.jl

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST, RF = 5e-4, 0.04
const DATADIR = joinpath(dirname(@__DIR__), "data")
bt(d, sig) = run_backtest(d, sig; cost=COST, rf_annual=RF)
function slice_md(d::MarketData, i0, i1)
    MarketData(d.ticker, d.date[i0:i1], d.open[i0:i1], d.high[i0:i1],
               d.low[i0:i1], d.close[i0:i1], d.volume[i0:i1])
end
d = load_ticker("QQQ"; dir=DATADIR)

CCI = cci_band_tma_switch(d; exit_lo=-100, entry_hi=0, bear_exit=0, tma_n=200, lb=20, confirm=1)
FR  = fast_reentry(d; fast=50, slow=200, re=50, hold=10)
strategies = [
    ("CCI40 TMA-trigger",  CCI),
    ("SMA fast-reentry",   FR),
    ("blend: avg (½ size)",(CCI .+ FR) ./ 2),
    ("blend: both-on",     sig_and(CCI, FR)),
    ("blend: either-on",   sig_or(CCI, FR)),
]
ev(sig, a, b) = compute_metrics(bt(slice_md(d, a, b), sig[a:b]))
win(f, t) = date_range(d, f, t)

function tbl(label, f, t)
    a, b = win(f, t)
    println("\n", "═"^96, "\n", label, "  ", d.date[a], " … ", d.date[b], "\n", "═"^96)
    println(METRIC_HEADER); println("-"^96)
    for (nm, s) in strategies; println(metric_row(nm, ev(s, a, b))); end
end

tbl("FULL HISTORY",  Date(1999,3,10),  Date(2026,5,29))
tbl("dot-com bear",  Date(2000,3,10),  Date(2002,10,9))
tbl("GFC bear",      Date(2007,10,31), Date(2009,3,9))
tbl("COVID crash",   Date(2020,2,19),  Date(2020,3,23))
tbl("2022 bear",     Date(2021,11,19), Date(2022,12,28))
tbl("RECENT DECADE", Date(2016,5,31),  Date(2026,5,29))
