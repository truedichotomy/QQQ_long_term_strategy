# Indicators computed from scratch (those the source file does not already carry,
# e.g. long-horizon moving averages used for regime filters). All are *causal*:
# the value at index i depends only on data up to and including i, and is NaN
# until its look-back window is full.

using Statistics

"Simple moving average over the trailing `n` points."
function sma(x::AbstractVector, n::Integer)
    m = length(x); out = fill(NaN, m)
    n <= 0 && return out
    acc = 0.0
    for i in 1:m
        acc += x[i]
        i > n && (acc -= x[i - n])
        i >= n && (out[i] = acc / n)
    end
    return out
end

"""
Triangular moving average of period `n` — an SMA of an SMA, which gives roughly
triangular weights (rising to the middle of the window, then falling) spanning
`n` points. Implemented as two SMAs whose windows sum to `n+1` (`w1 = n÷2`,
`w2 = n − w1 + 1`). Causal; NaN until `n` points are available. Smoother and more
lagged than a plain SMA of the same length.
"""
function tma(x::AbstractVector, n::Integer)
    n <= 1 && return sma(x, max(n, 1))
    w1 = n ÷ 2
    w2 = n - w1 + 1
    inner = sma(x, w1)
    m = length(x); out = fill(NaN, m)
    f = findfirst(!isnan, inner)          # skip inner's NaN warm-up so it can't
    f === nothing && return out           # poison the outer SMA's running sum
    sub = sma(@view(inner[f:end]), w2)
    @inbounds for (j, i) in enumerate(f:m)
        out[i] = sub[j]
    end
    return out
end

"Exponential moving average (seeded at x[1])."
function ema(x::AbstractVector, n::Integer)
    m = length(x); out = fill(NaN, m)
    m == 0 && return out
    α = 2 / (n + 1)
    prev = x[1]; out[1] = prev
    for i in 2:m
        prev = α * x[i] + (1 - α) * prev
        out[i] = prev
    end
    return out
end

"""
Commodity Channel Index over `n` periods from the typical price
TP = (high+low+close)/3:  CCI = (TP − SMA(TP,n)) / (0.015 · meanADdev), where the
mean absolute deviation is taken over the same trailing `n`-day window. Causal;
NaN until the window fills. (The source CSVs carry only CCI(40) as `:cci40`.)
"""
function cci(high::AbstractVector, low::AbstractVector, close::AbstractVector, n::Integer)
    m = length(close); out = fill(NaN, m)
    n <= 0 && return out
    tp = (high .+ low .+ close) ./ 3
    s = sma(tp, n)
    for i in n:m
        md = 0.0
        for j in (i - n + 1):i
            md += abs(tp[j] - s[i])
        end
        md /= n
        out[i] = md == 0 ? 0.0 : (tp[i] - s[i]) / (0.015 * md)
    end
    return out
end

"Wilder's RSI over `n` periods (0–100)."
function rsi(close::AbstractVector, n::Integer=14)
    m = length(close); out = fill(NaN, m)
    m < n + 1 && return out
    ag = 0.0; al = 0.0
    for i in 2:(n + 1)
        ch = close[i] - close[i - 1]
        ag += max(ch, 0.0); al += max(-ch, 0.0)
    end
    ag /= n; al /= n
    out[n + 1] = al == 0 ? 100.0 : 100 - 100 / (1 + ag / al)
    for i in (n + 2):m
        ch = close[i] - close[i - 1]
        ag = (ag * (n - 1) + max(ch, 0.0)) / n
        al = (al * (n - 1) + max(-ch, 0.0)) / n
        out[i] = al == 0 ? 100.0 : 100 - 100 / (1 + ag / al)
    end
    return out
end

"Trailing rolling standard deviation over `n` points (sample std)."
function rolling_std(x::AbstractVector, n::Integer)
    m = length(x); out = fill(NaN, m)
    for i in n:m
        out[i] = std(@view x[i - n + 1:i])
    end
    return out
end

"Trailing rolling maximum over `n` points."
function rolling_max(x::AbstractVector, n::Integer)
    m = length(x); out = fill(NaN, m)
    for i in n:m
        out[i] = maximum(@view x[i - n + 1:i])
    end
    return out
end

"Trailing rolling minimum over `n` points."
function rolling_min(x::AbstractVector, n::Integer)
    m = length(x); out = fill(NaN, m)
    for i in n:m
        out[i] = minimum(@view x[i - n + 1:i])
    end
    return out
end

"Close-to-close simple returns; r[1] = 0."
function simple_returns(close::AbstractVector)
    m = length(close); r = zeros(m)
    for i in 2:m
        r[i] = close[i] / close[i - 1] - 1
    end
    return r
end

"Running drawdown series (0 at new highs, negative below peak)."
function drawdown_series(eq::AbstractVector)
    out = similar(eq, Float64); peak = -Inf
    for i in eachindex(eq)
        peak = max(peak, eq[i])
        out[i] = eq[i] / peak - 1
    end
    return out
end

"Maximum drawdown of an equity curve (a negative number)."
function max_drawdown(eq::AbstractVector)
    peak = -Inf; mdd = 0.0
    for x in eq
        peak = max(peak, x)
        mdd = min(mdd, x / peak - 1)
    end
    return mdd
end
