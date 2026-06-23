# Print today's signal for QQQ (or any ticker in ../data) — the day-to-day tool.
# Shows the two SMA trend-filter variants — Standard (fast re-entry, the central
# strategy) and Conservative (classic 50/200 golden cross) — plus the CCI(50)
# -120/-40 momentum-band overlay.
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
    c50 = cci(d.high, d.low, d.close, 50)                       # CCI(50) reading
    fast = fast_reentry(d; fast=50, slow=200, re=50, hold=10)   # Standard
    cons = sma_cross(d; fast=50, slow=200)                      # Conservative
    band = cci_band(d; n=50, exit_lo=-120, entry_hi=-40)        # CCI(50) -120/-40 overlay
    lf = last_change(fast); lc = last_change(cons); lb = last_change(band)
    state(x) = x == 1 ? "▲ LONG" : "▼ CASH"

    println("="^60)
    @printf("%s  —  as of %s\n", ticker, d.date[n])
    println("="^60)
    @printf("  close   %10.2f\n", d.close[n])
    @printf("  SMA-50  %10.2f   %s   SMA-200 %.2f\n", s50[n], s50[n] > s200[n] ? ">" : "<", s200[n])
    @printf("  CCI-50  %10.2f   (sell<-120, re-enter>-40)\n", c50[n])
    println("-"^60)
    @printf("  STANDARD (fast re-entry):  %s   since %s\n", state(fast[n]), d.date[lf])
    @printf("  CONSERVATIVE (50/200):     %s   since %s\n", state(cons[n]), d.date[lc])
    @printf("  CCI(50) band -120/-40:     %s   since %s\n", state(band[n]), d.date[lb])
    println("-"^60)
    if fast[n] == cons[n] == band[n]
        @printf("  All three agree: hold %s.\n", fast[n] == 1 ? "100% $ticker" : "cash")
    else
        println("  Signals disagree — see each rule's state above.")
    end
    @printf("  Standard rule:  exit when SMA-50<SMA-200; re-enter when close>SMA-50\n")
    @printf("                  (min ~10 trading days between switches).\n")
    @printf("  CCI(50) band:   exit when CCI(50)<-120; re-enter when CCI(50)>-40.\n")
end

show_signal(isempty(ARGS) ? "QQQ" : uppercase(ARGS[1]))
