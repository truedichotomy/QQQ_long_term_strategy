# Multi-timescale robustness evaluation.
#
# A single full-sample CAGR can be dominated by one lucky regime exit (e.g.
# dodging the 2000–2002 crash). To check whether outperformance is *consistent*,
# we slide windows of many lengths — ~1 month to ~10 years — across history and,
# for each window, compare the strategy's return and drawdown to buy-and-hold.

using Statistics

# (trading days, label) — 21 trading days ≈ 1 calendar month
const HORIZONS = [(21, "1mo"), (63, "3mo"), (126, "6mo"), (252, "1yr"),
                  (504, "2yr"), (756, "3yr"), (1260, "5yr"), (2520, "10yr")]

_win_return(eq, a, b) = eq[b] / eq[a] - 1

function _win_maxdd(eq, a, b)
    peak = -Inf; mdd = 0.0
    @inbounds for i in a:b
        peak = max(peak, eq[i])
        mdd = min(mdd, eq[i] / peak - 1)
    end
    return mdd
end

"""
Slide a `win`-day window (stride `step`) over two equity curves and summarize
how often, and by how much, `eq_s` (strategy) beats `eq_b` (buy & hold) — on
return and on shallower drawdown ("downside no worse").
"""
function rolling_compare(eq_s::AbstractVector, eq_b::AbstractVector, win::Integer; step::Integer=21)
    n = length(eq_s)
    rs = Float64[]; rb = Float64[]; ds = Float64[]; db = Float64[]
    a = 1
    while a + win <= n
        b = a + win
        push!(rs, _win_return(eq_s, a, b)); push!(rb, _win_return(eq_b, a, b))
        push!(ds, _win_maxdd(eq_s, a, b)); push!(db, _win_maxdd(eq_b, a, b))
        a += step
    end
    nwin = length(rs)
    nwin == 0 && return (; nwin=0)
    excess = rs .- rb
    return (;
        nwin,
        return_win_rate = mean(excess .> 0),       # fraction of windows beating B&H return
        median_excess   = median(excess),
        mean_excess     = mean(excess),
        dd_win_rate     = mean(ds .>= db),         # fraction with shallower-or-equal drawdown
        median_dd_s     = median(ds),
        median_dd_b     = median(db),
        worst_dd_s      = minimum(ds),
        worst_dd_b      = minimum(db),
    )
end

"Run `rolling_compare` across all `HORIZONS` and return label => summary."
function multiscale(eq_s::AbstractVector, eq_b::AbstractVector; step::Integer=21)
    out = Pair{String,NamedTuple}[]
    for (win, label) in HORIZONS
        win + 1 > length(eq_s) && continue
        push!(out, label => rolling_compare(eq_s, eq_b, win; step=step))
    end
    return out
end

# ---- objective functions on a candidate equity curve over a window [a, b] ----
win_cagr(eq, a, b) = (eq[b] / eq[a])^(252 / (b - a)) - 1
function win_calmar(eq, a, b)
    dd = _win_maxdd(eq, a, b)
    dd == 0 ? 0.0 : win_cagr(eq, a, b) / abs(dd)
end
function win_sharpe(sr, a, b)
    v = @view sr[a + 1:b]
    σ = std(v)
    σ == 0 ? 0.0 : mean(v) / σ * sqrt(252)
end

"""
    walk_forward(n, cand_eq, cand_sr, score; min_train, step, lookback=0)

Out-of-sample parameter selection. `cand_eq`/`cand_sr` are vectors of candidate
equity curves and daily-return series (all length `n`). Starting at `min_train`,
every `step` days the candidate maximizing `score(eq, sr, train_start, t)` over the
training window is chosen and traded over the next `step` days (genuinely OOS — the
choice uses only data up to `t`). `lookback=0` ⇒ anchored (expanding) window;
`lookback>0` ⇒ rolling window of that many days.

Returns `(sr_oos, chosen, decisions)`: the stitched OOS daily-return series (NaN
before OOS begins), the active candidate index per day, and the `(t, chosen)` picks.
"""
function walk_forward(n::Integer, cand_eq, cand_sr, score; min_train::Integer, step::Integer, lookback::Integer=0)
    chosen = zeros(Int, n)
    decisions = Tuple{Int,Int}[]
    t = min_train
    while t < n
        train_start = lookback > 0 ? max(1, t - lookback + 1) : 1
        best = 0; best_s = -Inf
        for k in eachindex(cand_eq)
            s = score(cand_eq[k], cand_sr[k], train_start, t)
            if isfinite(s) && s > best_s
                best_s = s; best = k
            end
        end
        push!(decisions, (t, best))
        tend = min(t + step, n)
        for i in (t + 1):tend
            chosen[i] = best
        end
        t = tend
    end
    sr = fill(NaN, n)
    for i in 1:n
        chosen[i] != 0 && (sr[i] = cand_sr[chosen[i]][i])
    end
    return sr, chosen, decisions
end

"Equity curve (start 1.0) from a daily-return series over [a,b], skipping leading NaN."
function equity_from_sr(sr, a, b)
    eq = ones(b - a + 1); e = 1.0
    for (j, i) in enumerate(a:b)
        r = isnan(sr[i]) ? 0.0 : sr[i]
        e *= (1 + r); eq[j] = e
    end
    return eq
end
