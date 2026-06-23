# Walk-forward / out-of-sample validation of the CCI(50) hysteresis-band rule.
#
# The full-sample -120/-40 pick was chosen with hindsight. Here we test it the
# way you'd actually trade it: every year, re-select the best (exit_lo, entry_hi)
# band from a grid using ONLY past data, trade it the next year, and stitch the
# out-of-sample segments. The first OOS year is ~2004, so the dot-com crash lands
# in training — a deliberately hard test of whether the edge persists.
#
# Questions:
#   1. Does adaptively choosing the band each year beat (a) buy & hold and
#      (b) the fixed -120/-40 rule, out-of-sample?
#   2. How stable is the chosen band over time (is -120/-40 what it lands on)?
#   3. Do chronological train/test splits pick a band that generalizes forward?
#
#   julia --startup-file=no analysis/cci_walkforward.jl  [TICKER]

include(joinpath(dirname(@__DIR__), "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST, RF = 5e-4, 0.04
const DATADIR = joinpath(dirname(dirname(@__DIR__)), "data")
const OUTDIR  = joinpath(dirname(@__DIR__), "results", "tests")
bt(d, sig) = run_backtest(d, sig; cost=COST, rf_annual=RF)

const TK = isempty(ARGS) ? "QQQ" : uppercase(ARGS[1])
d = load_ticker(TK; dir=DATADIR)
n = length(d); dates = d.date
@printf("=== CCI(50)-band walk-forward / OOS validation: %s (%s … %s) ===\n", TK, dates[1], dates[end])

# ---- candidate grid: the bands the walk-forward may choose from ----
const EXITS = (-100, -110, -120, -130, -140)
const ENTRIES = (-60, -40, -20, 0, 20)
grid = Tuple{String,Vector{Float64}}[("B&H", buyhold(d))]
for lo in EXITS, hi in ENTRIES
    push!(grid, (@sprintf("%d/%d", lo, hi), cci_band(d; n=50, exit_lo=lo, entry_hi=hi)))
end
labels  = first.(grid)
cand_eq = [bt(d, s).eq for (_, s) in grid]
cand_sr = [[i == 1 ? 0.0 : e[i] / e[i - 1] - 1 for i in eachindex(e)] for e in cand_eq]
FIXED   = findfirst(==("-120/-40"), labels)   # the rule we adopted
BH      = findfirst(==("B&H"), labels)

# ---- metrics from an OOS daily-return series over [a,b] ----
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
prow(name, m) = @printf("%-24s %7.2f%% %8.1fx %8.1f%% %8.2f %8.2f %8.2f\n",
                        name, 100m.cagr, m.total, 100m.maxdd, m.sharpe, m.sortino, m.calmar)

# ============================================================================
# 1. Walk-forward: annual band re-selection, anchored vs rolling, Calmar vs CAGR
# ============================================================================
const MIN_TRAIN = 1260   # 5 yr — first OOS ~2004 (dot-com is in training)
const STEP      = 252    # re-select yearly
oos_a = MIN_TRAIN + 1

score_calmar(eq, sr, a, b) = win_calmar(eq, a, b)
score_cagr(eq, sr, a, b)   = win_cagr(eq, a, b)

wf_anc_cal, ch_anc_cal, _ = walk_forward(n, cand_eq, cand_sr, score_calmar; min_train=MIN_TRAIN, step=STEP, lookback=0)
wf_rol_cal, ch_rol_cal, _ = walk_forward(n, cand_eq, cand_sr, score_calmar; min_train=MIN_TRAIN, step=STEP, lookback=1260)
wf_anc_cag, ch_anc_cag, _ = walk_forward(n, cand_eq, cand_sr, score_cagr;   min_train=MIN_TRAIN, step=STEP, lookback=0)

@printf("\nOOS window: %s … %s  (%.1f yrs; first ~5 yrs are training/in-sample)\n\n",
        dates[oos_a], dates[n], Dates.value(dates[n] - dates[oos_a]) / 365.25)
@printf("%-24s %7s %9s %9s %8s %8s %8s\n", "OOS strategy", "CAGR", "total", "maxDD", "Sharpe", "Sortino", "Calmar")
println("-"^80)
prow("buy & hold",              eqm(cand_sr[BH], oos_a, n))
prow("fixed CCI -120/-40",      eqm(cand_sr[FIXED], oos_a, n))
prow("WF anchored (Calmar)",    eqm(wf_anc_cal, oos_a, n))
prow("WF rolling-5y (Calmar)",  eqm(wf_rol_cal, oos_a, n))
prow("WF anchored (CAGR obj)",  eqm(wf_anc_cag, oos_a, n))

# ============================================================================
# 2. Band stability — what did the anchored/Calmar walk-forward pick each year?
# ============================================================================
println("\nWhat WF-anchored-Calmar chose each year (band stability):")
let prev = 0
    for i in oos_a:n
        if ch_anc_cal[i] != prev && ch_anc_cal[i] != 0
            @printf("  %s → %s\n", dates[i], labels[ch_anc_cal[i]])
            prev = ch_anc_cal[i]
        end
    end
end
counts = Dict{Int,Int}()
for i in oos_a:n
    ch_anc_cal[i] != 0 && (counts[ch_anc_cal[i]] = get(counts, ch_anc_cal[i], 0) + 1)
end
println("  bands by share of OOS days:")
for (k, v) in sort(collect(counts); by=x -> -x[2])
    @printf("    %-12s %4.0f%%\n", labels[k], 100v / (n - oos_a + 1))
end

# ============================================================================
# 3. Chronological train/test splits — does an in-sample-best band generalize?
# ============================================================================
function best_by_calmar(a, b)
    best = 0; bs = -Inf
    for k in eachindex(cand_eq)
        s = win_calmar(cand_eq[k], a, b)
        isfinite(s) && s > bs && (bs = s; best = k)
    end
    return best
end
println("\nChronological splits (optimize Calmar in-sample, apply held-out; vs fixed -120/-40 & B&H):")
for (tr_from, tr_to, te_from, te_to) in [
        (Date(1999,1,1), Date(2009,12,31), Date(2010,1,1), dates[n]),
        (Date(1999,1,1), Date(2016,12,31), Date(2017,1,1), dates[n])]
    ia, ib = date_range(d, tr_from, tr_to)
    ja, jb = date_range(d, te_from, te_to)
    pick = best_by_calmar(ia, ib)
    @printf("  train %d–%d → in-sample best band = %s ; test %d–%d:\n",
            year(tr_from), year(tr_to), labels[pick], year(te_from), year(te_to))
    prow("    chosen ("*labels[pick]*")", eqm(cand_sr[pick], ja, jb))
    prow("    fixed -120/-40",            eqm(cand_sr[FIXED], ja, jb))
    prow("    buy & hold",                eqm(cand_sr[BH], ja, jb))
end

# ---- save OOS summary + equity curves (ticker-suffixed except QQQ) ----
mkpath(OUTDIR)
sfx = TK == "QQQ" ? "" : "_$(TK)"
open(joinpath(OUTDIR, "cci_walkforward$(sfx).csv"), "w") do io
    println(io, "method,oos_cagr,oos_total,oos_maxdd,oos_sharpe,oos_sortino,oos_calmar")
    for (nm, sr) in [("buy_and_hold", cand_sr[BH]), ("fixed_cci_120_40", cand_sr[FIXED]),
                     ("wf_anchored_calmar", wf_anc_cal), ("wf_rolling5y_calmar", wf_rol_cal),
                     ("wf_anchored_cagr", wf_anc_cag)]
        m = eqm(sr, oos_a, n)
        @printf(io, "%s,%.6f,%.6f,%.6f,%.4f,%.4f,%.4f\n",
                nm, m.cagr, m.total, m.maxdd, m.sharpe, m.sortino, m.calmar)
    end
end
open(joinpath(OUTDIR, "cci_walkforward_equity$(sfx).csv"), "w") do io
    println(io, "date,bh,fixed_cci_120_40,wf_anchored_calmar,wf_rolling5y_calmar")
    eb = equity_from_sr(cand_sr[BH], oos_a, n); ef = equity_from_sr(cand_sr[FIXED], oos_a, n)
    ea = equity_from_sr(wf_anc_cal, oos_a, n);  er = equity_from_sr(wf_rol_cal, oos_a, n)
    for (j, i) in enumerate(oos_a:n)
        @printf(io, "%s,%.6f,%.6f,%.6f,%.6f\n", dates[i], eb[j], ef[j], ea[j], er[j])
    end
end
println("\nWrote cci_walkforward.csv, cci_walkforward_equity.csv to ", OUTDIR)
