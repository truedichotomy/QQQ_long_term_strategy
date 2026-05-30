# Cross-asset signals: let the broad market (SPY/DIA), bonds (TLT), small caps
# (IWM) etc. inform QQQ timing. Everything is aligned onto QQQ's date axis.
#
# The other ETFs share the NYSE calendar with QQQ, so for any QQQ date on/after
# an ETF's inception the value exists; the only missing values are a *leading*
# block before inception, which we carry as NaN. Cross signals therefore return
# NaN before their data exists, and the gate_* combinators fall back to the base
# (QQQ-only) signal there — so full QQQ history is always preserved and a cross
# filter only acts once its informer actually exists.

"Align `other`'s close onto `base.date`; pre-inception dates -> NaN."
function align_close(base::MarketData, other::MarketData)
    idx = Dict(other.date[i] => i for i in eachindex(other.date))
    out = fill(NaN, length(base))
    for i in eachindex(base.date)
        j = get(idx, base.date[i], 0)
        j != 0 && (out[i] = other.close[j])
    end
    return out
end

"SMA tolerant of a leading NaN block (computes from the first valid point)."
function sma_aligned(x::AbstractVector, n::Integer)
    out = fill(NaN, length(x))
    fv = findfirst(!isnan, x); fv === nothing && return out
    out[fv:end] = sma(x[fv:end], n)
    return out
end

"Trailing `n`-day momentum (simple return); NaN where inputs are missing."
function momentum(x::AbstractVector, n::Integer)
    m = length(x); out = fill(NaN, m)
    for i in (n + 1):m
        (!isnan(x[i]) && !isnan(x[i - n]) && x[i - n] != 0) && (out[i] = x[i] / x[i - n] - 1)
    end
    return out
end

# ---- cross-asset signal builders (return 0 / 1 / NaN on the base axis) ----

"1 while `series` is above its own `n`-day SMA."
above_own_sma(series::AbstractVector, n::Integer) =
    (s = sma_aligned(series, n);
     [(isnan(series[i]) || isnan(s[i])) ? NaN : Float64(series[i] > s[i]) for i in eachindex(series)])

"1 while the fast SMA of `series` is above its slow SMA (informer's golden cross)."
cross_own(series::AbstractVector, fast::Integer, slow::Integer) =
    (f = sma_aligned(series, fast); s = sma_aligned(series, slow);
     [(isnan(f[i]) || isnan(s[i])) ? NaN : Float64(f[i] > s[i]) for i in eachindex(series)])

"1 while the base/other price ratio is above its own `n`-day SMA (base leadership)."
rel_strength(base_close::AbstractVector, other_close::AbstractVector, n::Integer) =
    (ratio = base_close ./ other_close; s = sma_aligned(ratio, n);
     [(isnan(ratio[i]) || isnan(s[i])) ? NaN : Float64(ratio[i] > s[i]) for i in eachindex(ratio)])

"1 while base `n`-day momentum exceeds the other asset's `n`-day momentum (risk-on)."
risk_on(base_close::AbstractVector, other_close::AbstractVector, n::Integer) =
    (mb = momentum(base_close, n); mo = momentum(other_close, n);
     [(isnan(mb[i]) || isnan(mo[i])) ? NaN : Float64(mb[i] > mo[i]) for i in eachindex(mb)])

# ---- combine a cross signal with the base QQQ signal (NaN cross -> use base) ----
gate_and(base_sig, cross_sig) =
    [isnan(cross_sig[i]) ? base_sig[i] : base_sig[i] * cross_sig[i] for i in eachindex(base_sig)]
gate_or(base_sig, cross_sig) =
    [isnan(cross_sig[i]) ? base_sig[i] : max(base_sig[i], cross_sig[i]) for i in eachindex(base_sig)]
