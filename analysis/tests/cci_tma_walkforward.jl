# (a) Walk-forward / OOS validation of the CCI(40) -120/0 + TMA(200)-switch rule
# (switch on, no confirmation). Every year, re-select the best (exit_lo, entry_hi)
# band from a grid on past-only data, trade it the next year, stitch the OOS
# segments. First OOS year ~2004 (dot-com in training). Does the fixed -120/0
# beat adaptive re-optimization OOS, and is the chosen band stable?
#
#   julia --startup-file=no analysis/cci_tma_walkforward.jl  [TICKER]

include(joinpath(dirname(@__DIR__), "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST, RF = 5e-4, 0.04
const DATADIR = joinpath(dirname(dirname(@__DIR__)), "data")
const OUTDIR  = joinpath(dirname(@__DIR__), "results")
bt(d, sig) = run_backtest(d, sig; cost=COST, rf_annual=RF)

const TK = isempty(ARGS) ? "QQQ" : uppercase(ARGS[1])
d = load_ticker(TK; dir=DATADIR); n = length(d); dates = d.date
@printf("=== CCI(40)+TMA-switch walk-forward / OOS: %s (%s … %s) ===\n", TK, dates[1], dates[end])

# grid: switch-on band variants the walk-forward may choose from (lb=20, tma=200, no confirm)
const EXITS = (-100, -110, -120, -130, -140)
const ENTRIES = (-20, 0, 20)
grid = Tuple{String,Vector{Float64}}[("B&H", buyhold(d))]
for lo in EXITS, hi in ENTRIES
    push!(grid, (@sprintf("%d/%d", lo, hi),
                 cci_band_tma_switch(d; exit_lo=lo, entry_hi=hi, bear_exit=0, tma_n=200, lb=20, confirm=1)))
end
labels  = first.(grid)
cand_eq = [bt(d, s).eq for (_, s) in grid]
cand_sr = [[i == 1 ? 0.0 : e[i] / e[i - 1] - 1 for i in eachindex(e)] for e in cand_eq]
FIXED   = findfirst(==("-120/0"), labels)
BH      = findfirst(==("B&H"), labels)

function eqm(sr, a, b)
    eq = equity_from_sr(sr, a, b)
    yrs = max(Dates.value(dates[b] - dates[a]) / 365.25, 1e-9)
    er = [eq[i] / eq[i - 1] - 1 for i in 2:length(eq)]
    σ = std(er); dn = sqrt(mean(x -> min(x, 0.0)^2, er))
    mdd = max_drawdown(eq); cagr = eq[end]^(1 / yrs) - 1
    return (cagr=cagr, maxdd=mdd, total=eq[end],
            sharpe=σ == 0 ? 0.0 : mean(er) / σ * sqrt(252),
            sortino=dn == 0 ? 0.0 : mean(er) / dn * sqrt(252),
            calmar=mdd == 0 ? 0.0 : cagr / abs(mdd))
end
prow(name, m) = @printf("%-26s %7.2f%% %8.1fx %8.1f%% %8.2f %8.2f %8.2f\n",
                        name, 100m.cagr, m.total, 100m.maxdd, m.sharpe, m.sortino, m.calmar)

const MIN_TRAIN, STEP = 1260, 252
oos_a = MIN_TRAIN + 1
wf, ch, _ = walk_forward(n, cand_eq, cand_sr, (eq,sr,a,b)->win_calmar(eq,a,b); min_train=MIN_TRAIN, step=STEP)
wfg, chg, _ = walk_forward(n, cand_eq, cand_sr, (eq,sr,a,b)->win_cagr(eq,a,b); min_train=MIN_TRAIN, step=STEP)

@printf("\nOOS window: %s … %s  (%.1f yrs)\n\n", dates[oos_a], dates[n], Dates.value(dates[n]-dates[oos_a])/365.25)
@printf("%-26s %7s %9s %9s %8s %8s %8s\n", "OOS strategy","CAGR","total","maxDD","Sharpe","Sortino","Calmar")
println("-"^80)
prow("buy & hold",                eqm(cand_sr[BH], oos_a, n))
prow("fixed -120/0 (switch-only)",eqm(cand_sr[FIXED], oos_a, n))
prow("WF anchored (Calmar)",      eqm(wf, oos_a, n))
prow("WF anchored (CAGR obj)",    eqm(wfg, oos_a, n))

println("\nWhat WF-Calmar chose each year:")
let prev = 0
    for i in oos_a:n
        ch[i] != prev && ch[i] != 0 && (@printf("  %s → %s\n", dates[i], labels[ch[i]]); prev = ch[i])
    end
end
counts = Dict{Int,Int}()
for i in oos_a:n; ch[i] != 0 && (counts[ch[i]] = get(counts, ch[i], 0) + 1); end
println("  bands by share of OOS days:")
for (k, v) in sort(collect(counts); by=x->-x[2]); @printf("    %-10s %4.0f%%\n", labels[k], 100v/(n-oos_a+1)); end

function best_by_calmar(a, b)
    best = 0; bs = -Inf
    for k in eachindex(cand_eq); s = win_calmar(cand_eq[k], a, b); isfinite(s) && s > bs && (bs = s; best = k); end
    return best
end
println("\nChronological splits (optimize Calmar in-sample, apply held-out; vs fixed -120/0 & B&H):")
for (tr_from, tr_to, te_from, te_to) in [
        (Date(1999,1,1), Date(2009,12,31), Date(2010,1,1), dates[n]),
        (Date(1999,1,1), Date(2016,12,31), Date(2017,1,1), dates[n])]
    ia, ib = date_range(d, tr_from, tr_to); ja, jb = date_range(d, te_from, te_to)
    pick = best_by_calmar(ia, ib)
    @printf("  train %d–%d → best band = %s ; test %d–%d:\n", year(tr_from), year(tr_to), labels[pick], year(te_from), year(te_to))
    prow("    chosen ("*labels[pick]*")", eqm(cand_sr[pick], ja, jb))
    prow("    fixed -120/0",             eqm(cand_sr[FIXED], ja, jb))
    prow("    buy & hold",               eqm(cand_sr[BH], ja, jb))
end

mkpath(OUTDIR); sfx = TK == "QQQ" ? "" : "_$(TK)"
open(joinpath(OUTDIR, "cci_tma_walkforward$(sfx).csv"), "w") do io
    println(io, "method,oos_cagr,oos_total,oos_maxdd,oos_sharpe,oos_sortino,oos_calmar")
    for (nm, sr) in [("buy_and_hold",cand_sr[BH]),("fixed_120_0_switch",cand_sr[FIXED]),
                     ("wf_anchored_calmar",wf),("wf_anchored_cagr",wfg)]
        m = eqm(sr, oos_a, n)
        @printf(io, "%s,%.6f,%.6f,%.6f,%.4f,%.4f,%.4f\n", nm, m.cagr, m.total, m.maxdd, m.sharpe, m.sortino, m.calmar)
    end
end
println("\nWrote cci_tma_walkforward.csv to ", OUTDIR)
