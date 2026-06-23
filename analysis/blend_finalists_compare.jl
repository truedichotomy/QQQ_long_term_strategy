# Side-by-side decision analysis of the two FINAL candidates — both blends of
# the CCI40 TMA-trigger (momentum) and SMA fast-reentry (trend) signals:
#   A) blend avg (½)   : exposure = (CCI + FR)/2 ∈ {0,½,1} — half-size on disagreement
#   B) blend either-on : long if EITHER rule is long (max exposure)
# Buy & hold is the common baseline. Same accounting as the rest of the study
# (long/flat-or-fractional, 1-day lag, 5 bps turnover, cash 4%/yr, close-to-close).
#
#   julia --startup-file=no analysis/blend_finalists_compare.jl

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
AVG = (CCI .+ FR) ./ 2
EIT = sig_or(CCI, FR)
NAMES = ["buy & hold", "blend avg (½)", "blend either-on"]
SIGS  = [buyhold(d), AVG, EIT]
eqs   = [bt(d, s).eq for s in SIGS]
ev(sig, a, b) = compute_metrics(bt(slice_md(d, a, b), sig[a:b]))
win(f, t) = date_range(d, f, t)

println("QQQ ", d.date[1], " … ", d.date[end], "   (cash 4%/yr, 5 bps/trade, 1-day lag)\n")

println("═"^96, "\n1. HEADLINE — full history\n", "═"^96)
println(METRIC_HEADER); println("-"^96)
for (nm, s) in zip(NAMES, SIGS); println(metric_row(nm, compute_metrics(bt(d, s)))); end

println("\n", "═"^96, "\n2. ACROSS ERAS — CAGR / maxDD / Calmar\n", "═"^96)
eras = [("Prior decade 06-16", win(Date(2006,5,30), Date(2016,5,27))),
        ("Recent decade 16-26", win(Date(2016,5,31), Date(2026,5,29))),
        ("Modern era 04-26 (ex dot-com)", win(Date(2004,3,15), Date(2026,5,29))),
        ("Full 20yr 06-26", win(Date(2006,5,30), Date(2026,5,29)))]
@printf("%-32s", "era"); for nm in NAMES; @printf("%24s", nm); end; println(); println("-"^(32+24*3))
for (lbl, w) in eras
    @printf("%-32s", lbl)
    for s in SIGS; m = ev(s, w[1], w[2]); @printf("%24s", @sprintf("%.1f%% / %.0f%% / %.2f", 100m.cagr, 100m.maxdd, m.calmar)); end
    println()
end

println("\n", "═"^96, "\n3. BY CALENDAR DECADE — CAGR / maxDD\n", "═"^96)
decs = [("2000s", win(Date(2000,1,1), Date(2009,12,31))),
        ("2010s", win(Date(2010,1,1), Date(2019,12,31))),
        ("2020s", win(Date(2020,1,1), Date(2026,5,29)))]
@printf("%-10s", "decade"); for nm in NAMES; @printf("%24s", nm); end; println(); println("-"^(10+24*3))
for (lbl, w) in decs
    @printf("%-10s", lbl)
    for s in SIGS; m = ev(s, w[1], w[2]); @printf("%24s", @sprintf("%+.1f%% / %.0f%%", 100m.cagr, 100m.maxdd)); end
    println()
end

println("\n", "═"^96, "\n4. BY REGIME — total return / max drawdown within the span\n", "═"^96)
regs = [("Dot-com crash 00-02", win(Date(2000,3,10), Date(2002,10,9))),
        ("Mid-2000s recovery",  win(Date(2002,10,9), Date(2007,10,31))),
        ("GFC 07-09",           win(Date(2007,10,31), Date(2009,3,9))),
        ("2009-2020 bull",      win(Date(2009,3,9),  Date(2020,2,19))),
        ("COVID crash 2020",    win(Date(2020,2,19), Date(2020,3,23))),
        ("Post-COVID surge",    win(Date(2020,3,23), Date(2021,11,19))),
        ("2022 bear",           win(Date(2021,11,19),Date(2022,12,28))),
        ("2023-26 recovery",    win(Date(2022,12,28),Date(2026,5,29)))]
@printf("%-22s", "regime"); for nm in NAMES; @printf("%22s", nm); end; println(); println("-"^(22+22*3))
for (lbl, w) in regs
    @printf("%-22s", lbl)
    for s in SIGS; m = ev(s, w[1], w[2]); @printf("%22s", @sprintf("%+.0f%% / %.0f%%", 100m.total_return, 100m.maxdd)); end
    println()
end

println("\n", "═"^96, "\n5. HOLDING-PERIOD CONSISTENCY — annualized worst / median / best (rolling, stride 21d)\n", "═"^96)
function hp(eq, w)
    rs = Float64[]; a = 1
    while a + w <= length(eq); push!(rs, (eq[a+w]/eq[a])^(252/w) - 1); a += 21; end
    isempty(rs) ? (NaN,NaN,NaN) : (minimum(rs), median(rs), maximum(rs))
end
@printf("%-10s", "horizon"); for nm in NAMES; @printf("%26s", nm); end; println(); println("-"^(10+26*3))
for (lbl, w) in [("1 year",252),("3 years",756),("5 years",1260),("10 years",2520)]
    @printf("%-10s", lbl)
    for eq in eqs; lo,md,hi = hp(eq, w); @printf("%26s", @sprintf("%+.0f / %+.0f / %+.0f%%", 100lo,100md,100hi)); end
    println()
end

println("\n", "═"^96, "\n6. ROLLING WIN-RATE vs BUY & HOLD — return-beat% / shallower-DD%\n", "═"^96)
@printf("%-20s", "strategy"); for h in ("1mo","3mo","6mo","1yr","3yr","5yr"); @printf("%12s", h); end; println(); println("-"^(20+12*6))
for (nm, eq) in [(NAMES[2],eqs[2]), (NAMES[3],eqs[3])]
    @printf("%-20s", nm)
    for w in (21,63,126,252,756,1260)
        s = rolling_compare(eq, eqs[1], w; step=21)
        @printf("%12s", @sprintf("%.0f%%/%.0f%%", 100s.return_win_rate, 100s.dd_win_rate))
    end
    println()
end

println("\n", "═"^96, "\n7. HEAD-TO-HEAD — share of rolling windows  blend-avg  beats  blend-either-on\n", "═"^96)
@printf("%-26s", ""); for h in ("1mo","3mo","6mo","1yr","3yr","5yr"); @printf("%10s", h); end; println(); println("-"^(26+10*6))
@printf("%-26s", "avg higher return %")
for w in (21,63,126,252,756,1260); s = rolling_compare(eqs[2], eqs[3], w; step=21); @printf("%10s", @sprintf("%.0f%%", 100s.return_win_rate)); end; println()
@printf("%-26s", "avg shallower drawdown %")
for w in (21,63,126,252,756,1260); s = rolling_compare(eqs[2], eqs[3], w; step=21); @printf("%10s", @sprintf("%.0f%%", 100s.dd_win_rate)); end; println()

function last_change(sig); lc = 1; for i in 2:length(sig); sig[i] != sig[i-1] && (lc = i); end; lc; end
println("\n", "═"^96, "\n8. CURRENT SIGNAL & POSITION — as of ", d.date[end], "\n", "═"^96)
@printf("  CCI40 TMA-trigger: %s   SMA fast-reentry: %s\n", CCI[end]==1 ? "LONG" : "CASH", FR[end]==1 ? "LONG" : "CASH")
for (nm, s) in [(NAMES[2],AVG), (NAMES[3],EIT)]
    @printf("  %-18s exposure now = %3.0f%%   (last change %s)\n", nm, 100*s[end], d.date[last_change(s)])
end
