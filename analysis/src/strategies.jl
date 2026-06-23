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
function macd_cross(d::MarketData)
    line, signal, _ = macd(d.close)
    return Float64.(line .> signal)
end

"Long while the MACD histogram is positive."
function macd_hist(d::MarketData)
    _, _, hist = macd(d.close)
    return Float64.(hist .> 0)
end

"Long while +DI is above -DI (directional-movement trend)."
function di_trend(d::MarketData)
    pdi, mdi, _ = adx(d.high, d.low, d.close)
    return Float64.(pdi .> mdi)
end

"Long while +DI > -DI AND ADX confirms a trend of at least `thr`."
function adx_trend(d::MarketData; thr::Real=20)
    pdi, mdi, a = adx(d.high, d.low, d.close)
    return Float64.((pdi .> mdi) .& (a .> thr))
end

"Long while CCI(`n`) is above `lo` (momentum/trend variant)."
cci_trend(d::MarketData; n::Integer=40, lo::Real=0) =
    Float64.(cci(d.high, d.low, d.close, n) .> lo)

"""
CCI hysteresis-band crash filter (stateful): start invested; exit to cash when
CCI(`n`) falls below `exit_lo` (a deep washout), then stay flat until CCI climbs
back above `entry_hi`. The wide band (`exit_lo` ≪ `entry_hi`) keeps it from
re-entering into continued weakness. Default −120 / 0 on CCI(50). CCI(50) is
computed here (the source file only carries CCI(40)).
"""
function cci_band(d::MarketData; n::Integer=50, exit_lo::Real=-120, entry_hi::Real=0)
    c = cci(d.high, d.low, d.close, n)
    m = length(d.close); out = zeros(m); invested = true
    for i in 1:m
        if invested
            (!isnan(c[i]) && c[i] < exit_lo) && (invested = false)
        else
            (!isnan(c[i]) && c[i] > entry_hi) && (invested = true)
        end
        out[i] = invested ? 1.0 : 0.0
    end
    return out
end

"""
CCI(40) band with a triangular-MA-gated exit and N-day signal confirmation.

Normally trades the CCI(40) `exit_lo`/`entry_hi` band (default −120/0): enter when
CCI(40) > `entry_hi`, exit when CCI(40) < `exit_lo`. But whenever the `tma_n`-day
TRIANGULAR moving average is sloping down (`TMA[i] < TMA[i−lb]` — a sustained
downtrend) the exit threshold tightens to `bear_exit` (default 0), i.e. it falls
back to the reactive CCI(40)>0 rule that survives long saw-toothed bears.

Signal confirmation is asymmetric: an exit needs the trigger to hold `confirm_exit`
consecutive days, a re-entry needs `confirm_entry` consecutive days (both default to
`confirm`). `confirm=1` ⇒ act immediately (best for drawdown — never delays a
protective exit); `confirm_exit=1, confirm_entry=2` ⇒ fast exits but confirmed
re-entries. CCI(40) is computed from OHLC. Ablations fall out of the parameters:
`bear_exit=exit_lo` disables the switch.
"""
function cci_band_tma_switch(d::MarketData; exit_lo::Real=-120, entry_hi::Real=0,
                             bear_exit::Real=0, tma_n::Integer=200, lb::Integer=20,
                             confirm::Integer=1, confirm_exit::Integer=confirm,
                             confirm_entry::Integer=confirm)
    c = cci(d.high, d.low, d.close, 40); t = tma(d.close, tma_n)
    m = length(d.close); out = zeros(m); invested = true; run = 0
    for i in 1:m
        bear = i > lb && !isnan(t[i]) && !isnan(t[i - lb]) && t[i] < t[i - lb]
        xlo  = bear ? bear_exit : exit_lo
        cond = invested ? (!isnan(c[i]) && c[i] < xlo) : (!isnan(c[i]) && c[i] > entry_hi)
        need = invested ? confirm_exit : confirm_entry
        run  = cond ? run + 1 : 0
        if run >= need
            invested = !invested; run = 0
        end
        out[i] = invested ? 1.0 : 0.0
    end
    return out
end

"""
Regime-switching CCI overlay: normally trade the wide CCI(`n`) hysteresis band
(`exit_lo`/`entry_hi`), but when BOTH the `fast`- and `slow`-day SMAs are sloping
down (price `lb` days ago higher than now — a confirmed sustained downtrend, the
dot-com-grind signature) switch to the tighter, more reactive CCI(`n40`)>0 rule.
The wide band excels against fast clean crashes but rides multi-year saw-toothed
bears down (its relief-rally re-entries get chopped up); CCI(`n40`)>0 flips out
faster in exactly that regime. CCI(40) is computed from OHLC.
"""
function cci_regime_switch(d::MarketData; n::Integer=50, exit_lo::Real=-120, entry_hi::Real=-40,
                           n40::Integer=40, fast::Integer=50, slow::Integer=200, lb::Integer=20)
    band  = cci_band(d; n=n, exit_lo=exit_lo, entry_hi=entry_hi)
    cci40 = Float64.(cci(d.high, d.low, d.close, 40) .> 0)   # tighter fast rule (CCI(40)>0)
    sf = sma(d.close, fast); ss = sma(d.close, slow)
    m = length(d.close); out = similar(band)
    for i in 1:m
        bear = i > lb &&
               !isnan(sf[i]) && !isnan(sf[i - lb]) && sf[i] < sf[i - lb] &&
               !isnan(ss[i]) && !isnan(ss[i - lb]) && ss[i] < ss[i - lb]
        out[i] = bear ? cci40[i] : band[i]
    end
    return out
end

"Long while the Awesome oscillator is positive."
awesome_trend(d::MarketData) =
    Float64.(awesome(d.high, d.low) .> 0)

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
    macd_up = (mline = macd(d.close); mline[1] .> mline[2])
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
    macd_up = (mline = macd(d.close); mline[1] .> mline[2])
    [(Float64(d.close[i] > sl[i]) + Float64(sf[i] > ss[i]) + Float64(macd_up[i])) / 3 for i in eachindex(d.close)]
end

# ---- the chosen overlay: a blend of the two finalist signals ----
# Their failure modes are complementary — the SMA trend filter is blind to fast
# crashes, the CCI momentum filter is weak in long grinding bears — so combining
# them covers both. `blend_components` returns (momentum, trend); the blends below
# are built from that pair so signal tooling can show the breakdown.

"The two finalist signals as `(momentum, trend)`: CCI(40) −100/0 band with a 200-day triangular-MA regime switch, and the 50/200 SMA fast-reentry filter."
blend_components(d::MarketData) =
    (cci_band_tma_switch(d; exit_lo=-100, entry_hi=0, bear_exit=0, tma_n=200, lb=20, confirm=1),
     fast_reentry(d; fast=50, slow=200, re=50, hold=10))

"Long if EITHER finalist is long (max return, ~3 trades/yr; no fast-crash cushion)."
blend_either_on(d::MarketData) = (m = blend_components(d); sig_or(m[1], m[2]))

"Average exposure of the two finalists ∈ {0, ½, 1} (smoothest ride; cushions every crash)."
blend_avg(d::MarketData) = (m = blend_components(d); (m[1] .+ m[2]) ./ 2)

# ---- elementwise combinators ----
sig_and(a, b) = a .* b
sig_or(a, b)  = max.(a, b)
