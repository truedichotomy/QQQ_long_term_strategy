# Print today's QQQ signal for the chosen overlay — the EITHER-ON blend of a
# trend filter (50/200 SMA fast-reentry) and a momentum filter (CCI(40) -100/0
# with a 200-day triangular-MA regime switch). Shows the breakdown of both
# component filters and the resulting action (BUY/HOLD vs SELL/WAIT). The avg
# (½-size) blend exposure is shown as the lower-risk alternative.
#
#   julia analysis/signal.jl          # QQQ
#   julia analysis/signal.jl SPY      # any ticker present in ../data

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Printf

last_change(s) = (lc = 1; for i in 2:length(s); s[i] != s[i-1] && (lc = i); end; lc)

function show_signal(ticker)
    d = load_ticker(ticker; dir=joinpath(dirname(@__DIR__), "data"))
    n = length(d)
    s50 = sma(d.close, 50); s200 = sma(d.close, 200)
    c40 = cci(d.high, d.low, d.close, 40); t200 = tma(d.close, 200)
    mom, trend = blend_components(d)            # (CCI40 TMA-trigger, SMA fast-reentry)
    either = blend_either_on(d); avg = blend_avg(d)
    instate(x) = x == 1 ? "IN " : "OUT"
    bear = n > 20 && !isnan(t200[n]) && !isnan(t200[n-20]) && t200[n] < t200[n-20]
    mom_exit = bear ? 0 : -100

    println("="^64)
    @printf("%s  blend signal  —  as of %s\n", ticker, d.date[n])
    println("="^64)
    @printf("  close %.2f      SMA-50 %.0f %s SMA-200 %.0f      CCI(40) %.0f\n",
            d.close[n], s50[n], s50[n] > s200[n] ? ">" : "<", s200[n], c40[n])
    println("-"^64)
    println("  COMPONENT FILTERS")
    @printf("   • Trend  (SMA 50/200 fast-reentry): %s  since %s\n", instate(trend[n]), d.date[last_change(trend)])
    @printf("       SMA-50 is %s SMA-200\n", s50[n] > s200[n] ? "ABOVE (uptrend)" : "BELOW (downtrend)")
    @printf("   • Moment (CCI40 -100/0 + TMA switch): %s  since %s\n", instate(mom[n]), d.date[last_change(mom)])
    @printf("       CCI(40) %.0f vs exit %d   (TMA-200 slope %s ⇒ exit at %d)\n",
            c40[n], mom_exit, bear ? "DOWN" : "UP", mom_exit)
    println("-"^64)

    long = either[n] == 1
    if long
        @printf("  ► EITHER-ON  ▲ BUY / HOLD  —  100%% %s\n", ticker)
        why = trend[n] == 1 && mom[n] == 1 ? "both filters IN" : "at least one filter IN"
        @printf("     long because %s.  (in QQQ since %s)\n", why, d.date[last_change(either)])
    else
        @printf("  ► EITHER-ON  ▼ SELL / WAIT  —  hold cash\n")
        @printf("     flat because BOTH filters are OUT.  (in cash since %s)\n", d.date[last_change(either)])
    end
    @printf("  ► AVG (½-size alt.)  exposure now = %d%% %s\n", round(Int, 100avg[n]), ticker)
    println("-"^64)
    println("  Rule: in QQQ unless BOTH the trend and momentum filters are OUT;")
    println("        re-enter as soon as EITHER turns back IN. ~3 trades/yr.")
end

show_signal(isempty(ARGS) ? "QQQ" : uppercase(ARGS[1]))
