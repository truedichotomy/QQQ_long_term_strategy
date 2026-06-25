# "If I enter QQQ mid-cycle (signal already IN, price near highs) — like mid-2026 —
# what happened next, running the overlay vs naked buy & hold?" For every historical
# day matching that condition, measure the worst drawdown you'd subsequently suffer
# from your entry, and the forward 1-yr return. The overlay's exit rule is what caps
# the entry-timing risk that buy & hold can't.
using Dates, Printf, Statistics
include(joinpath(@__DIR__, "QQQBacktest.jl")); using .QQQBacktest

q(x,p) = quantile(x,p)
function study(tk)
    d = load_ticker(tk; dir=joinpath(dirname(@__DIR__), "data")); n = length(d)
    eo = run_backtest(d, blend_either_on(d); cost=5e-4, rf_annual=0.04)
    av = run_backtest(d, blend_avg(d);       cost=5e-4, rf_annual=0.04)
    bh = run_backtest(d, buyhold(d);         cost=5e-4, rf_annual=0.04)
    cmax = accumulate(max, d.close)                      # trailing all-time high
    # your situation: overlay says invested AND price within 5% of its high
    entries = [i for i in 1:n if eo.pos[i]==1 && d.close[i] >= 0.95*cmax[i]]
    fdd(eq,i) = max_drawdown(@view eq[i:end])            # worst dd from entry, ever
    f1(eq,i)  = i+252<=n ? eq[i+252]/eq[i]-1 : NaN       # forward 1-yr
    ddo=[fdd(eo.eq,i) for i in entries]; dda=[fdd(av.eq,i) for i in entries]; ddb=[fdd(bh.eq,i) for i in entries]
    r1o=filter(!isnan,[f1(eo.eq,i) for i in entries]); r1b=filter(!isnan,[f1(bh.eq,i) for i in entries])
    @printf("\n%s — %d near-high, signal-IN entry days (%s..%s)\n", tk, length(entries), d.date[1], d.date[end])
    @printf("  WORST drawdown you'd later suffer from that entry:\n")
    @printf("      either-on : median %4.0f%%   worst(p05) %4.0f%%   absolute worst %4.0f%%\n",
            100median(ddo),100q(ddo,0.05),100minimum(ddo))
    @printf("      avg (½)   : median %4.0f%%   worst(p05) %4.0f%%   absolute worst %4.0f%%\n",
            100median(dda),100q(dda,0.05),100minimum(dda))
    @printf("      buy & hold: median %4.0f%%   worst(p05) %4.0f%%   absolute worst %4.0f%%\n",
            100median(ddb),100q(ddb,0.05),100minimum(ddb))
    @printf("  forward 1-yr return from such an entry:  either-on median %+4.0f%%   B&H median %+4.0f%%\n",
            100median(r1o),100median(r1b))
end
study("QQQ"); study("NDX")
