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

"""
MACD from `close`: returns `(line, signal, hist)` where line = EMA`fast` − EMA`slow`,
signal = EMA`sig` of the line, hist = line − signal. The first `slow+sig` points are
NaN'd (warm-up) so strategies stay flat until the EMAs stabilize.
"""
function macd(close::AbstractVector; fast::Integer=12, slow::Integer=26, sig::Integer=9)
    line = ema(close, fast) .- ema(close, slow)
    signal = ema(line, sig)
    hist = line .- signal
    w = min(slow + sig, length(line))
    @inbounds for i in 1:w; line[i] = signal[i] = hist[i] = NaN; end
    return (line, signal, hist)
end

"Awesome oscillator: SMA`fast` − SMA`slow` of the median price (high+low)/2. NaN until warm."
function awesome(high::AbstractVector, low::AbstractVector; fast::Integer=5, slow::Integer=34)
    mp = (high .+ low) ./ 2
    return sma(mp, fast) .- sma(mp, slow)
end

"""
Wilder's directional system over `n` periods from high/low/close: returns
`(plus_di, minus_di, adx)`. +DI/−DI become valid at index `n+1`, ADX at `2n`; all
NaN before that. Standard Wilder smoothing (no look-ahead).
"""
function adx(high::AbstractVector, low::AbstractVector, close::AbstractVector; n::Integer=14)
    m = length(close)
    pdi = fill(NaN, m); mdi = fill(NaN, m); adxv = fill(NaN, m)
    m < 2n && return (pdi, mdi, adxv)
    tr = zeros(m); pdm = zeros(m); mdm = zeros(m)
    for i in 2:m
        up = high[i] - high[i-1]; dn = low[i-1] - low[i]
        pdm[i] = (up > dn && up > 0) ? up : 0.0
        mdm[i] = (dn > up && dn > 0) ? dn : 0.0
        tr[i]  = max(high[i] - low[i], abs(high[i] - close[i-1]), abs(low[i] - close[i-1]))
    end
    atr = 0.0; sp = 0.0; sm = 0.0
    for i in 2:n+1; atr += tr[i]; sp += pdm[i]; sm += mdm[i]; end
    dx = fill(NaN, m)
    di!(i) = (p = atr == 0 ? 0.0 : 100sp/atr; q = atr == 0 ? 0.0 : 100sm/atr;
              pdi[i] = p; mdi[i] = q; d = p + q; dx[i] = d == 0 ? 0.0 : 100abs(p - q)/d)
    di!(n+1)
    for i in n+2:m
        atr += tr[i] - atr/n; sp += pdm[i] - sp/n; sm += mdm[i] - sm/n
        di!(i)
    end
    s = 0.0; for i in n+1:2n; s += dx[i]; end
    adxv[2n] = s/n
    for i in 2n+1:m; adxv[i] = (adxv[i-1]*(n-1) + dx[i])/n; end
    return (pdi, mdi, adxv)
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
