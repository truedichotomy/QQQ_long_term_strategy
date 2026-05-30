# Main study: find a long/flat technical strategy on daily QQQ that beats
# buy-and-hold on CAGR while taking no more downside (max drawdown) than B&H,
# and check that the edge holds across time scales from ~1 month to ~10 years.
#
#   julia analysis/run_analysis.jl
#
# Assumptions (see project README / earlier design decisions):
#   * exposure is long/flat only (fully in QQQ or fully in cash)
#   * cash earns ~4%/yr
#   * 5 bps proportional cost charged on turnover (whipsaw penalty)

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST = 5e-4
const RF   = 0.04
const DATADIR = joinpath(dirname(@__DIR__), "data")
const OUTDIR  = joinpath(@__DIR__, "results")

bt(d, sig) = run_backtest(d, sig; cost=COST, rf_annual=RF)

# ----------------------------------------------------------------------------
# 1. Load data and build the candidate strategy set (with parameter sweeps).
# ----------------------------------------------------------------------------
d = load_ticker("QQQ"; dir=DATADIR)
@printf("Loaded QQQ: %d days, %s … %s\n\n", length(d), d.date[1], d.date[end])

candidates = Tuple{String,Vector{Float64}}[]
push!(candidates, ("buy & hold", buyhold(d)))

for n in (50, 100, 125, 150, 175, 200, 250)
    push!(candidates, ("SMA filter $n", sma_filter(d; n=n)))
end
for (f, s) in ((20, 100), (50, 150), (50, 200), (20, 200), (100, 200))
    push!(candidates, ("SMA cross $f/$s", sma_cross(d; fast=f, slow=s)))
end
for n in (100, 150, 200)
    push!(candidates, ("EMA filter $n", ema_filter(d; n=n)))
end
push!(candidates, ("MACD cross", macd_cross(d)))
push!(candidates, ("MACD hist>0", macd_hist(d)))
push!(candidates, ("DI trend (+DI>-DI)", di_trend(d)))
for thr in (15, 20, 25)
    push!(candidates, ("ADX trend thr=$thr", adx_trend(d; thr=thr)))
end
push!(candidates, ("CCI(40)>0", cci_trend(d; lo=0)))
push!(candidates, ("Awesome>0", awesome_trend(d)))
push!(candidates, ("RSI(14)>50", rsi_trend(d; n=14, lo=50)))

# composites: regime filter AND a faster confirmation
sma200 = sma_filter(d; n=200)
sma150 = sma_filter(d; n=150)
push!(candidates, ("SMA200 & MACD",  sig_and(sma200, macd_cross(d))))
push!(candidates, ("SMA200 & DI",    sig_and(sma200, di_trend(d))))
push!(candidates, ("SMA200 & ADX20", sig_and(sma200, adx_trend(d; thr=20))))
push!(candidates, ("SMA150 & MACD",  sig_and(sma150, macd_cross(d))))
push!(candidates, ("SMA200 | MACD",  sig_or(sma200, macd_cross(d))))
push!(candidates, ("MACD & RSI>50",  sig_and(macd_cross(d), rsi_trend(d; lo=50))))

# "stay invested unless clearly bad" family + trailing-stop crash filters:
# designed to capture more upside (higher rolling win-rate) yet still dodge tails.
push!(candidates, ("SMA200 slope",     sma_slope(d; n=200, lb=20)))
push!(candidates, ("SMA150 slope",     sma_slope(d; n=150, lb=20)))
push!(candidates, ("regime-stay 200",  regime_stay(d; n=200, lb=20)))
push!(candidates, ("regime-stay 150",  regime_stay(d; n=150, lb=20)))
for dd in (0.15, 0.18, 0.22, 0.25)
    push!(candidates, (@sprintf("trail-stop %.0f%%", 100dd), trailing_stop(d; dd=dd, n_re=50)))
end
push!(candidates, ("regime-stay200 & cross", sig_and(regime_stay(d; n=200), sma_cross(d; fast=50, slow=200))))
push!(candidates, ("trail18 & SMA200slope",  sig_or(trailing_stop(d; dd=0.18), sma_slope(d; n=200))))

# ----------------------------------------------------------------------------
# 2. Backtest everything; rank against the bar.
# ----------------------------------------------------------------------------
results = [(name, bt(d, sig)) for (name, sig) in candidates]
metrics = [(name, compute_metrics(b), b) for (name, b) in results]

bh_m = metrics[1][2]
bh_b = metrics[1][3]
@printf("Buy & hold benchmark:  CAGR %.2f%%   maxDD %.1f%%   (cash=%.0f%%/yr, cost=%.0f bps)\n\n",
        100bh_m.cagr, 100bh_m.maxdd, 100RF, 1e4COST)

# bar: beat B&H CAGR AND drawdown no worse (maxdd is negative, so >= means shallower)
passes(m) = m.cagr > bh_m.cagr && m.maxdd >= bh_m.maxdd

# rolling 1-year robustness vs B&H, shown per strategy
function win1y(b)
    s = rolling_compare(b.eq, bh_b.eq, 252; step=21)
    return (s.return_win_rate, s.dd_win_rate)
end

println(METRIC_HEADER, @sprintf("  %6s %6s", "1yRet", "1yDD"))
println("-"^118)
for (name, m, b) in sort(metrics; by = x -> -x[2].cagr)
    rw, dw = name == "buy & hold" ? (0.5, 1.0) : win1y(b)
    mark = name == "buy & hold" ? " ◄ B&H" : (passes(m) ? " ✓" : "")
    println(metric_row(name, m), @sprintf("  %5.0f%% %5.0f%%", 100rw, 100dw), mark)
end
println("\n✓ = beats B&H on CAGR with max drawdown no worse than B&H")
println("1yRet/1yDD = share of rolling 1-yr windows where the strategy beats B&H on return / drawdown\n")

# ----------------------------------------------------------------------------
# 3. Frontier + flagship pick.
#
# "Beats CAGR with no worse drawdown" leaves a trade-off frontier: pure max-CAGR
# picks accept deep drawdowns; pure min-drawdown picks give up the return edge.
# The flagship balances both: best return-per-unit-drawdown (Calmar) among
# strategies that *significantly* beat B&H on CAGR (margin ≥ 1 pp/yr) with
# drawdown no worse than B&H.
# ----------------------------------------------------------------------------
const SIG = 0.01  # "significant" CAGR margin over B&H
beaters = [(name, m, b) for (name, m, b) in metrics if name != "buy & hold" && passes(m)]

println("Trade-off frontier (all clear the bar; pick by what you weight):")
let by_cagr = sort(beaters; by = x -> -x[2].cagr)[1],
    by_calmar = sort(beaters; by = x -> -x[2].calmar)[1],
    by_dd = sort(beaters; by = x -> x[2].maxdd)[1]
    @printf("  max CAGR       : %-22s  CAGR %.2f%%  maxDD %.1f%%  Calmar %.2f\n", by_cagr[1], 100by_cagr[2].cagr, 100by_cagr[2].maxdd, by_cagr[2].calmar)
    @printf("  best Calmar    : %-22s  CAGR %.2f%%  maxDD %.1f%%  Calmar %.2f\n", by_calmar[1], 100by_calmar[2].cagr, 100by_calmar[2].maxdd, by_calmar[2].calmar)
    @printf("  lowest drawdown: %-22s  CAGR %.2f%%  maxDD %.1f%%  Calmar %.2f\n\n", by_dd[1], 100by_dd[2].cagr, 100by_dd[2].maxdd, by_dd[2].calmar)
end

significant = [(name, m, b) for (name, m, b) in beaters if m.cagr >= bh_m.cagr + SIG]
eligible = isempty(significant) ? beaters : significant
isempty(eligible) && (eligible = [(name, m, b) for (name, m, b) in metrics if name != "buy & hold"])
sort!(eligible; by = x -> -x[2].calmar)   # best return-per-drawdown among significant beaters
flag_name, flag_m, flag_b = eligible[1]

println("="^72)
@printf("FLAGSHIP: %s\n", flag_name)
println("="^72)
@printf("  CAGR        %.2f%%   vs B&H %.2f%%    (+%.2f pp/yr)\n", 100flag_m.cagr, 100bh_m.cagr, 100*(flag_m.cagr - bh_m.cagr))
@printf("  Total       %.1fx    vs B&H %.1fx\n", flag_m.total_return + 1, bh_m.total_return + 1)
@printf("  Max DD      %.1f%%   vs B&H %.1f%%    (%.1f pp shallower)\n", 100flag_m.maxdd, 100bh_m.maxdd, 100*(flag_m.maxdd - bh_m.maxdd))
@printf("  Sharpe      %.2f     vs B&H %.2f\n", flag_m.sharpe, bh_m.sharpe)
@printf("  Sortino     %.2f     vs B&H %.2f\n", flag_m.sortino, bh_m.sortino)
@printf("  Calmar      %.2f     vs B&H %.2f\n", flag_m.calmar, bh_m.calmar)
@printf("  %% invested  %.0f%%      trades: %d (≈%.1f/yr)\n\n", 100flag_m.pct_invested, flag_m.ntrades, flag_m.ntrades / flag_m.years)

# ----------------------------------------------------------------------------
# 4. Multi-timescale robustness: flagship vs B&H across rolling windows.
# ----------------------------------------------------------------------------
println("Multi-timescale robustness (rolling windows, stride 21d):")
@printf("%-6s %7s %12s %12s %12s %12s\n", "scale", "#win", "beat-B&H%", "med excess", "DD≤B&H%", "med DD s/b")
println("-"^66)
ms = multiscale(flag_b.eq, bh_b.eq; step=21)
for (label, s) in ms
    @printf("%-6s %7d %11.0f%% %11.1f%% %11.0f%% %6.0f%%/%.0f%%\n",
        label, s.nwin, 100s.return_win_rate, 100s.median_excess,
        100s.dd_win_rate, 100s.median_dd_s, 100s.median_dd_b)
end
println("\n  beat-B&H%  = share of windows where flagship return > B&H")
println("  DD≤B&H%    = share of windows where flagship drawdown is shallower-or-equal")
println("  med DD s/b = median in-window max drawdown, flagship / B&H\n")

# ----------------------------------------------------------------------------
# 5. Robustness of the flagship to cost and cash-rate assumptions.
# ----------------------------------------------------------------------------
flag_sig = candidates[findfirst(c -> c[1] == flag_name, candidates)][2]
println("Sensitivity of flagship CAGR / maxDD:")
@printf("  %-14s", "cost \\ cash")
for rf in (0.0, 0.04, 0.05); @printf("%14s", @sprintf("%.0f%%/yr", 100rf)); end
println()
for c in (0.0, 5e-4, 1e-3)
    @printf("  %-14s", @sprintf("%.0f bps", 1e4c))
    for rf in (0.0, 0.04, 0.05)
        bb = run_backtest(d, flag_sig; cost=c, rf_annual=rf)
        mm = compute_metrics(bb)
        @printf("%14s", @sprintf("%.1f%%/%.0f%%", 100mm.cagr, 100mm.maxdd))
    end
    println()
end
println()

# ----------------------------------------------------------------------------
# 6. Write result artifacts.
# ----------------------------------------------------------------------------
mkpath(OUTDIR)

open(joinpath(OUTDIR, "strategy_metrics.csv"), "w") do io
    println(io, "strategy,cagr,total_return,max_drawdown,vol,sharpe,sortino,calmar,pct_invested,trades,beats_bar")
    for (name, m, _) in sort(metrics; by = x -> -x[2].cagr)
        @printf(io, "%s,%.6f,%.6f,%.6f,%.6f,%.4f,%.4f,%.4f,%.4f,%d,%s\n",
            name, m.cagr, m.total_return, m.maxdd, m.vol, m.sharpe, m.sortino,
            m.calmar, m.pct_invested, m.ntrades, name != "buy & hold" && passes(m))
    end
end

open(joinpath(OUTDIR, "multiscale_flagship.csv"), "w") do io
    println(io, "scale,n_windows,return_win_rate,median_excess,mean_excess,dd_win_rate,median_dd_strat,median_dd_bh,worst_dd_strat,worst_dd_bh")
    for (label, s) in ms
        @printf(io, "%s,%d,%.4f,%.6f,%.6f,%.4f,%.6f,%.6f,%.6f,%.6f\n",
            label, s.nwin, s.return_win_rate, s.median_excess, s.mean_excess,
            s.dd_win_rate, s.median_dd_s, s.median_dd_b, s.worst_dd_s, s.worst_dd_b)
    end
end

open(joinpath(OUTDIR, "flagship_summary.csv"), "w") do io
    println(io, "field,strategy,bh")
    @printf(io, "name,%s,buy & hold\n", flag_name)
    @printf(io, "cagr,%.4f,%.4f\n", flag_m.cagr, bh_m.cagr)
    @printf(io, "maxdd,%.4f,%.4f\n", flag_m.maxdd, bh_m.maxdd)
    @printf(io, "total,%.4f,%.4f\n", flag_m.total_return + 1, bh_m.total_return + 1)
end

let dd_s = drawdown_series(flag_b.eq), dd_b = drawdown_series(bh_b.eq)
    open(joinpath(OUTDIR, "equity_curves.csv"), "w") do io
        println(io, "date,close,bh_equity,flagship_equity,flagship_position,bh_drawdown,flagship_drawdown")
        for i in 1:length(d)
            @printf(io, "%s,%.4f,%.6f,%.6f,%.0f,%.6f,%.6f\n",
                d.date[i], d.close[i], bh_b.eq[i], flag_b.eq[i], flag_b.pos[i], dd_b[i], dd_s[i])
        end
    end
end

@printf("Wrote results to %s/ (strategy_metrics, multiscale_flagship, equity_curves)\n", OUTDIR)
