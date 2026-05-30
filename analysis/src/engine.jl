# Causal long/flat backtest engine.
#
# A strategy produces a raw exposure series `raw[i]` in [0,1] = the fraction of
# capital it WANTS in QQQ based on information available through the close of day i.
# Because that decision can only be acted on afterward, the engine lags it one day
# (`pos[i] = raw[i-1]`) before applying day i's return — this is what prevents
# look-ahead bias. Cash (the 1-p fraction) earns `rf_annual`. A proportional
# `cost` is charged on turnover whenever the position changes.

"Lag a raw signal by one trading day. pos[1] = 0 (start in cash)."
lag1(raw::AbstractVector) = [0.0; @view raw[1:end - 1]]

struct BacktestResult
    date::Vector{Date}
    eq::Vector{Float64}      # equity curve, normalized to 1.0 at the first day
    pos::Vector{Float64}     # realized daily exposure (already lagged)
    ret::Vector{Float64}     # underlying asset daily returns
    cost::Float64
    rf_annual::Float64
end

_clean(p) = isnan(p) ? 0.0 : clamp(p, 0.0, 1.0)

"""
    run_backtest(d, raw_signal; cost=5e-4, rf_annual=0.04, lag=true)

Run the long/flat backtest over `MarketData` `d` given a raw exposure series.
Returns a `BacktestResult`. Set `lag=false` only if the signal is already lagged.
"""
function run_backtest(d::MarketData, raw_signal::AbstractVector;
                      cost::Real=5e-4, rf_annual::Real=0.04, lag::Bool=true)
    close = d.close
    n = length(close)
    @assert length(raw_signal) == n "signal length must match data length"
    r = simple_returns(close)
    pos = lag ? lag1(raw_signal) : collect(float(raw_signal))
    rf = (1 + rf_annual)^(1 / 252) - 1
    eq = ones(n)
    for i in 2:n
        p = _clean(pos[i]); pprev = _clean(pos[i - 1])
        gross = p * r[i] + (1 - p) * rf
        tc = cost * abs(p - pprev)
        eq[i] = eq[i - 1] * (1 + gross) * (1 - tc)
        pos[i] = p
    end
    pos[1] = _clean(pos[1])
    return BacktestResult(d.date, eq, pos, r, float(cost), float(rf_annual))
end
