# Print today's signal for QQQ (or any ticker in ../data) — the day-to-day tool.
# Shows BOTH variants: Standard (fast re-entry, the central strategy) and
# Conservative (classic 50/200 golden cross).
#
#   julia analysis/signal.jl          # QQQ
#   julia analysis/signal.jl SPY      # any ticker present in ../data

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Printf

function last_change(sig)
    lc = 1
    for i in 2:length(sig)
        sig[i] != sig[i - 1] && (lc = i)
    end
    return lc
end

function show_signal(ticker)
    d = load_ticker(ticker; dir=joinpath(dirname(@__DIR__), "data"))
    n = length(d)
    s50 = sma(d.close, 50); s200 = sma(d.close, 200)
    fast = fast_reentry(d; fast=50, slow=200, re=50, hold=10)   # Standard
    cons = sma_cross(d; fast=50, slow=200)                      # Conservative
    lf = last_change(fast); lc = last_change(cons)
    state(x) = x == 1 ? "▲ LONG" : "▼ CASH"

    println("="^60)
    @printf("%s  —  as of %s\n", ticker, d.date[n])
    println("="^60)
    @printf("  close   %10.2f\n", d.close[n])
    @printf("  SMA-50  %10.2f   %s   SMA-200 %.2f\n", s50[n], s50[n] > s200[n] ? ">" : "<", s200[n])
    println("-"^60)
    @printf("  STANDARD (fast re-entry):  %s   since %s\n", state(fast[n]), d.date[lf])
    @printf("  CONSERVATIVE (50/200):     %s   since %s\n", state(cons[n]), d.date[lc])
    println("-"^60)
    if fast[n] == cons[n]
        @printf("  Both variants agree: hold %s.\n", fast[n] == 1 ? "100% $ticker" : "cash")
    else
        println("  Variants disagree (Standard re-enters/exits sooner than Conservative).")
    end
    @printf("  Standard rule: exit when SMA-50<SMA-200; re-enter when close>SMA-50\n")
    @printf("                 (min ~10 trading days between switches).\n")
end

show_signal(isempty(ARGS) ? "QQQ" : uppercase(ARGS[1]))
