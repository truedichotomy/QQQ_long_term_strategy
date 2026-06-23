# Walk-forward / out-of-sample validation.
#
# Question 1: if you had to PICK the trend parameters in real time (not with
#   hindsight), would you still beat buy & hold — and would you beat the fixed
#   50/200 rule? We re-select the best candidate each year on a training window
#   and trade it the next year (genuinely OOS), then stitch the OOS segments.
# Question 2: how stable is the chosen parameter over time?
# Question 3: chronological train/test splits — does an in-sample-optimal
#   parameter generalize to the held-out future?
#
# Deliberately hard: the first OOS year is ~2004, so the dot-com crash (the
# strategy's signature win) lands in TRAINING. OOS tests whether the edge
# persists in the modern era without that tailwind.
#
#   julia analysis/walkforward.jl

include(joinpath(dirname(@__DIR__), "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST, RF = 5e-4, 0.04
const DATADIR = joinpath(dirname(dirname(@__DIR__)), "data")
const OUTDIR  = joinpath(dirname(@__DIR__), "results", "sma_study")
bt(d, sig) = run_backtest(d, sig; cost=COST, rf_annual=RF)

const TK = isempty(ARGS) ? "QQQ" : uppercase(ARGS[1])
d = load_ticker(TK; dir=DATADIR)
n = length(d)
dates = d.date
@printf("=== Walk-forward / OOS validation: %s (%s … %s) ===\n", TK, dates[1], dates[end])

# ---- candidate grid (what the walk-forward is allowed to choose from) ----
grid = Tuple{String,Vector{Float64}}[
    ("B&H",         buyhold(d)),
    ("x10/50",      sma_cross(d; fast=10, slow=50)),
    ("x20/50",      sma_cross(d; fast=20, slow=50)),
    ("x20/100",     sma_cross(d; fast=20, slow=100)),
    ("x50/100",     sma_cross(d; fast=50, slow=100)),
    ("x50/150",     sma_cross(d; fast=50, slow=150)),
    ("x50/200",     sma_cross(d; fast=50, slow=200)),
    ("x100/200",    sma_cross(d; fast=100, slow=200)),
    ("f50",         sma_filter(d; n=50)),
    ("f100",        sma_filter(d; n=100)),
    ("f150",        sma_filter(d; n=150)),
    ("f200",        sma_filter(d; n=200)),
    ("f250",        sma_filter(d; n=250)),
    ("regime-stay200", regime_stay(d; n=200)),
    ("sma200-slope",   sma_slope(d; n=200)),
    ("di-trend",    di_trend(d)),
    ("macd",        macd_cross(d)),
    ("adx20",       adx_trend(d; thr=20)),
    ("cci0",        cci_trend(d; lo=0)),
    ("fast-reentry",   fast_reentry(d; fast=50, slow=200, re=50)),
    ("regime-macd",    regime_macd(d; long_n=200, mid_n=100)),
    ("dual-speed",     dual_speed(d)),
]
labels  = first.(grid)
cand_eq = [bt(d, s).eq for (_, s) in grid]
cand_sr = [[i == 1 ? 0.0 : e[i] / e[i - 1] - 1 for i in eachindex(e)] for e in cand_eq]
FIXED   = findfirst(==("x50/200"), labels)   # the rule we shipped
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
prow(name, m) = @printf("%-22s %7.2f%% %8.1fx %8.1f%% %8.2f %8.2f %8.2f\n",
                        name, 100m.cagr, m.total, 100m.maxdd, m.sharpe, m.sortino, m.calmar)

# ============================================================================
# 1. Walk-forward: annual re-selection, anchored vs rolling, Calmar vs CAGR objective
# ============================================================================
const MIN_TRAIN = 1260   # 5 yr — first OOS ~2004 (dot-com is in training)
const STEP      = 252    # re-select yearly
oos_a = MIN_TRAIN + 1

score_calmar(eq, sr, a, b) = win_calmar(eq, a, b)
score_cagr(eq, sr, a, b)   = win_cagr(eq, a, b)

wf_anc_cal, ch_anc_cal, _ = walk_forward(n, cand_eq, cand_sr, score_calmar; min_train=MIN_TRAIN, step=STEP, lookback=0)
wf_rol_cal, ch_rol_cal, _ = walk_forward(n, cand_eq, cand_sr, score_calmar; min_train=MIN_TRAIN, step=STEP, lookback=1260)
wf_anc_cag, ch_anc_cag, _ = walk_forward(n, cand_eq, cand_sr, score_cagr;   min_train=MIN_TRAIN, step=STEP, lookback=0)

@printf("Out-of-sample window: %s … %s  (%.1f yrs; the first ~5 yrs are training/in-sample)\n\n",
        dates[oos_a], dates[n], Dates.value(dates[n] - dates[oos_a]) / 365.25)
@printf("%-22s %7s %9s %9s %8s %8s %8s\n", "OOS strategy", "CAGR", "total", "maxDD", "Sharpe", "Sortino", "Calmar")
println("-"^78)
prow("buy & hold",            eqm(cand_sr[BH], oos_a, n))
prow("fixed 50/200",          eqm(cand_sr[FIXED], oos_a, n))
prow("WF anchored (Calmar)",  eqm(wf_anc_cal, oos_a, n))
prow("WF rolling-5y (Calmar)",eqm(wf_rol_cal, oos_a, n))
prow("WF anchored (CAGR obj)",eqm(wf_anc_cag, oos_a, n))

# ============================================================================
# 2. Parameter stability — what did the anchored/Calmar walk-forward pick?
# ============================================================================
println("\nWhat WF-anchored-Calmar chose each year (parameter stability):")
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
println("  picks by share of OOS days:")
for (k, v) in sort(collect(counts); by=x -> -x[2])
    @printf("    %-16s %4.0f%%\n", labels[k], 100v / (n - oos_a + 1))
end

# ============================================================================
# 3. Chronological train/test splits — does an in-sample-optimal param generalize?
# ============================================================================
function best_by_calmar(a, b)
    best = 0; bs = -Inf
    for k in eachindex(cand_eq)
        s = win_calmar(cand_eq[k], a, b)
        isfinite(s) && s > bs && (bs = s; best = k)
    end
    return best
end
println("\nChronological splits (optimize Calmar in-sample, apply held-out; vs fixed 50/200 & B&H):")
for (tr_from, tr_to, te_from, te_to) in [
        (Date(1999,1,1), Date(2009,12,31), Date(2010,1,1), dates[n]),
        (Date(1999,1,1), Date(2016,12,31), Date(2017,1,1), dates[n])]
    ia, ib = date_range(d, tr_from, tr_to)
    ja, jb = date_range(d, te_from, te_to)
    pick = best_by_calmar(ia, ib)
    @printf("  train %d–%d → in-sample best = %s ; test %d–%d:\n",
            year(tr_from), year(tr_to), labels[pick], year(te_from), year(te_to))
    prow("    chosen ("*labels[pick]*")", eqm(cand_sr[pick], ja, jb))
    prow("    fixed 50/200",              eqm(cand_sr[FIXED], ja, jb))
    prow("    buy & hold",                eqm(cand_sr[BH], ja, jb))
end

# ============================================================================
# 4. Hybrids on SHORT horizons — do they fix the 50/200's weak short-term edge?
#    (full sample; rolling return/drawdown win-rate vs B&H at short scales)
# ============================================================================
println("\nShort-horizon behavior — rolling win-rate vs B&H (return% / drawdown%):")
@printf("%-16s %10s %10s %10s %10s  | %7s %7s\n", "strategy", "1mo", "3mo", "6mo", "1yr", "CAGR", "maxDD")
println("-"^84)
bh_eq = cand_eq[BH]
function shortrow(name, eq)
    fm = eqm([i == 1 ? 0.0 : eq[i] / eq[i - 1] - 1 for i in eachindex(eq)], 2, n)
    cells = map((21, 63, 126, 252)) do w
        s = rolling_compare(eq, bh_eq, w; step=21)
        @sprintf("%3.0f%%/%2.0f%%", 100s.return_win_rate, 100s.dd_win_rate)
    end
    @printf("%-16s %10s %10s %10s %10s  | %6.2f%% %6.1f%%\n",
            name, cells[1], cells[2], cells[3], cells[4], 100fm.cagr, 100fm.maxdd)
end
shortrow("fixed 50/200",  cand_eq[FIXED])
shortrow("fast-reentry",  cand_eq[findfirst(==("fast-reentry"), labels)])
shortrow("regime-macd",   cand_eq[findfirst(==("regime-macd"), labels)])
shortrow("dual-speed",    cand_eq[findfirst(==("dual-speed"), labels)])

# ============================================================================
# 5. Promote with discipline: is fast-reentry's edge real OOS and robust to its
#    re-entry parameter? (full sample vs OOS-2004+; the fixed rule for reference)
# ============================================================================
@printf("\nfast-reentry (Standard) validation — FULL %d–%d vs OOS %d+ , and re-param robustness:\n", year(dates[1]), year(dates[n]), year(dates[oos_a]))
@printf("%-22s | %8s %8s | %8s %8s\n", "strategy", "fullCAGR", "fullDD", "oosCAGR", "oosDD")
println("-"^66)
function bothrow(name, sr)
    f = eqm(sr, 2, n); o = eqm(sr, oos_a, n)
    @printf("%-22s | %7.2f%% %7.1f%% | %7.2f%% %7.1f%%\n", name, 100f.cagr, 100f.maxdd, 100o.cagr, 100o.maxdd)
end
bothrow("buy & hold",   cand_sr[BH])
bothrow("fixed 50/200", cand_sr[FIXED])
for re in (20, 30, 50, 75, 100)
    s = fast_reentry(d; fast=50, slow=200, re=re)
    e = bt(d, s).eq
    sr = [i == 1 ? 0.0 : e[i] / e[i - 1] - 1 for i in eachindex(e)]
    bothrow("fast-reentry re=$re", sr)
end

# ---- save OOS equity curves + a summary (ticker-suffixed except QQQ) ----
mkpath(OUTDIR)
sfx = TK == "QQQ" ? "" : "_$(TK)"
open(joinpath(OUTDIR, "walkforward$(sfx).csv"), "w") do io
    println(io, "method,oos_cagr,oos_total,oos_maxdd,oos_sharpe,oos_sortino,oos_calmar")
    for (nm, sr) in [("buy_and_hold", cand_sr[BH]), ("fixed_50_200", cand_sr[FIXED]),
                     ("wf_anchored_calmar", wf_anc_cal), ("wf_rolling5y_calmar", wf_rol_cal),
                     ("wf_anchored_cagr", wf_anc_cag)]
        m = eqm(sr, oos_a, n)
        @printf(io, "%s,%.6f,%.6f,%.6f,%.4f,%.4f,%.4f\n",
                nm, m.cagr, m.total, m.maxdd, m.sharpe, m.sortino, m.calmar)
    end
end
open(joinpath(OUTDIR, "walkforward_equity$(sfx).csv"), "w") do io
    println(io, "date,bh,fixed_50_200,wf_anchored_calmar,wf_rolling5y_calmar")
    eb = equity_from_sr(cand_sr[BH], oos_a, n); ef = equity_from_sr(cand_sr[FIXED], oos_a, n)
    ea = equity_from_sr(wf_anc_cal, oos_a, n);  er = equity_from_sr(wf_rol_cal, oos_a, n)
    for (j, i) in enumerate(oos_a:n)
        @printf(io, "%s,%.6f,%.6f,%.6f,%.6f\n", dates[i], eb[j], ef[j], ea[j], er[j])
    end
end
println("\nWrote walkforward.csv, walkforward_equity.csv to ", OUTDIR)
