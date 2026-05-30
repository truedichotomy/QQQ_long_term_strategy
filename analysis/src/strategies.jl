# Strategy library. Each function takes `MarketData` and returns a raw exposure
# series in {0,1} (the engine lags it). Comparisons against NaN are false in
# Julia, so every strategy is automatically flat (in cash) during indicator
# warm-up — no special-casing needed. Composites are built from these in the
# runner via elementwise AND (`s1 .* s2`) / OR (`max.(s1, s2)`).

# ---- baseline ----
buyhold(d::MarketData) = ones(length(d))

# ---- single-signal trend / regime filters ----

"Long while close is above its `n`-day SMA (classic regime filter)."
sma_filter(d::MarketData; n::Integer=200) =
    Float64.(d.close .> sma(d.close, n))

"Long while the fast SMA is above the slow SMA (golden/death cross)."
sma_cross(d::MarketData; fast::Integer=50, slow::Integer=200) =
    Float64.(sma(d.close, fast) .> sma(d.close, slow))

"Long while close is above its `n`-day EMA."
ema_filter(d::MarketData; n::Integer=200) =
    Float64.(d.close .> ema(d.close, n))

# ---- precomputed-indicator strategies ----

"Long while the MACD line is above its signal line."
macd_cross(d::MarketData) =
    Float64.(d.ind[:macd] .> d.ind[:macd_signal])

"Long while the MACD histogram is positive."
macd_hist(d::MarketData) =
    Float64.(d.ind[:macd_hist] .> 0)

"Long while +DI is above -DI (directional-movement trend)."
di_trend(d::MarketData) =
    Float64.(d.ind[:di_plus] .> d.ind[:di_minus])

"Long while +DI > -DI AND ADX confirms a trend of at least `thr`."
adx_trend(d::MarketData; thr::Real=20) =
    Float64.((d.ind[:di_plus] .> d.ind[:di_minus]) .& (d.ind[:adx] .> thr))

"Long while CCI(40) is above `lo` (momentum/trend variant)."
cci_trend(d::MarketData; lo::Real=0) =
    Float64.(d.ind[:cci40] .> lo)

"Long while the Awesome-oscillator histogram is positive."
awesome_trend(d::MarketData) =
    Float64.(d.ind[:awesome] .> 0)

"Long while RSI(`n`) is above `lo` (trend-following use of RSI)."
rsi_trend(d::MarketData; n::Integer=14, lo::Real=50) =
    Float64.(rsi(d.close, n) .> lo)

# ---- "stay invested unless clearly bad" filters ----
# These aim to capture more of QQQ's upside (higher rolling win-rate vs B&H)
# while still side-stepping the deep, grinding bear markets that drive drawdown.

"Long while the `n`-day SMA is rising (higher than `lb` days ago) — a slope/regime filter."
function sma_slope(d::MarketData; n::Integer=200, lb::Integer=20)
    s = sma(d.close, n); m = length(s); out = zeros(m)
    for i in (lb + 1):m
        (!isnan(s[i]) && !isnan(s[i - lb])) && (out[i] = s[i] > s[i - lb] ? 1.0 : 0.0)
    end
    return out
end

"""
Stay fully invested EXCEPT when price is both below its `n`-day SMA and that SMA
is falling (a confirmed downtrend). Defaults to invested before the SMA warms up.
"""
function regime_stay(d::MarketData; n::Integer=200, lb::Integer=20)
    s = sma(d.close, n); m = length(s); out = ones(m)
    for i in 1:m
        isnan(s[i]) && continue
        falling = i > lb && !isnan(s[i - lb]) && s[i] < s[i - lb]
        below = d.close[i] < s[i]
        out[i] = (below && falling) ? 0.0 : 1.0
    end
    return out
end

"""
Trailing-stop crash filter (stateful): start invested; exit when price falls
`dd` below its running peak; re-enter once close climbs back above its
`n_re`-day SMA, resetting the peak. Stays invested most of the time, only
cutting the deep tails.
"""
function trailing_stop(d::MarketData; dd::Real=0.18, n_re::Integer=50)
    close = d.close; m = length(close); out = zeros(m)
    ma = sma(close, n_re)
    peak = close[1]; invested = true
    for i in 1:m
        peak = max(peak, close[i])
        if invested
            close[i] < (1 - dd) * peak && (invested = false)
        else
            if !isnan(ma[i]) && close[i] > ma[i]
                invested = true; peak = close[i]
            end
        end
        out[i] = invested ? 1.0 : 0.0
    end
    return out
end

# ---- hybrids tuned for shorter time scales ----
# The plain 50/200 cross protects against deep drawdowns but re-enters slowly, so
# it underperforms over short (1mo–1yr) horizons. These hybrids keep the slow
# regime for crash protection but add a faster entry/exit to capture shorter moves.

"""
Golden-cross regime with *fast re-entry* and a minimum holding period. Exit on a
death cross (SMA`fast` < SMA`slow`); after an exit, re-enter as soon as price
reclaims its `re`-day SMA instead of waiting for the next golden cross. The
`hold`-day minimum between position changes is essential — without it the fast
re-entry whipsaws ~33×/yr in choppy downtrends; with `hold=10` it trades ~5×/yr
while keeping (and slightly improving) the return and drawdown. `re=50, hold=10`
is the default sweet spot (robust across re 40–50, hold 5–21 out-of-sample).
"""
function fast_reentry(d::MarketData; fast::Integer=50, slow::Integer=200, re::Integer=50, hold::Integer=10)
    sf = sma(d.close, fast); ss = sma(d.close, slow); sr = sma(d.close, re)
    m = length(d.close); out = zeros(m); invested = false; last_change = -(10^6)
    for i in 1:m
        can_change = (i - last_change) >= hold
        if invested
            if can_change && !isnan(sf[i]) && !isnan(ss[i]) && sf[i] < ss[i]
                invested = false; last_change = i
            end
        else
            golden  = !isnan(sf[i]) && !isnan(ss[i]) && sf[i] > ss[i]
            recover = !isnan(sr[i]) && d.close[i] > sr[i]
            if can_change && (golden || recover)
                invested = true; last_change = i
            end
        end
        out[i] = invested ? 1.0 : 0.0
    end
    return out
end

"""
Regime with tactical MACD re-entry (binary): long whenever price is above its
`long_n`-day SMA (broad uptrend), OR when it is above its `mid_n`-day SMA and MACD is
positive (a shorter-term rally worth riding). Flat only in confirmed weakness.
"""
function regime_macd(d::MarketData; long_n::Integer=200, mid_n::Integer=100)
    sl = sma(d.close, long_n); sm = sma(d.close, mid_n)
    macd_up = d.ind[:macd] .> d.ind[:macd_signal]
    [(d.close[i] > sl[i]) || (d.close[i] > sm[i] && macd_up[i]) ? 1.0 : 0.0 for i in eachindex(d.close)]
end

"""
Dual-speed vote (fractional 0/⅓/⅔/1 exposure): average of three trend gauges —
long-term regime (close > SMA`long_n`), medium cross (SMA`mid_fast` > SMA`mid_slow`),
and MACD. Scales exposure to how many time scales agree; reacts faster than a single
slow cross. NOTE: this is the one strategy that is not strictly long/flat binary.
"""
function dual_speed(d::MarketData; long_n::Integer=200, mid_fast::Integer=20, mid_slow::Integer=50)
    sl = sma(d.close, long_n); sf = sma(d.close, mid_fast); ss = sma(d.close, mid_slow)
    macd_up = d.ind[:macd] .> d.ind[:macd_signal]
    [(Float64(d.close[i] > sl[i]) + Float64(sf[i] > ss[i]) + Float64(macd_up[i])) / 3 for i in eachindex(d.close)]
end

# ---- elementwise combinators ----
sig_and(a, b) = a .* b
sig_or(a, b)  = max.(a, b)
