# QQQBacktest — a small, dependency-free (base Julia + stdlib) toolkit for
# backtesting long/flat technical strategies on the daily ETF data in ../data.
#
# Usage:
#   include("analysis/QQQBacktest.jl"); using .QQQBacktest
#   d = load_ticker("QQQ"; dir="data")
#   b = run_backtest(d, sma_filter(d; n=200))
#   compute_metrics(b)
#
# Run the full study with:  julia analysis/run_analysis.jl

module QQQBacktest

using Dates, Statistics, Printf

include("src/data.jl")
include("src/indicators.jl")
include("src/engine.jl")
include("src/metrics.jl")
include("src/strategies.jl")
include("src/crossasset.jl")
include("src/evaluate.jl")
include("src/fetch.jl")

# data
export MarketData, load_market, load_ticker, find_data_file, find_data_files, merge_markets, date_range, subset
# indicators
export sma, ema, rsi, cci, tma, macd, awesome, adx, rolling_std, rolling_max, simple_returns, drawdown_series, max_drawdown
# engine + metrics
export BacktestResult, run_backtest, lag1, Metrics, compute_metrics, metric_row, METRIC_HEADER
# strategies
export buyhold, sma_filter, sma_cross, ema_filter, macd_cross, macd_hist,
       di_trend, adx_trend, cci_trend, cci_band, cci_regime_switch, cci_band_tma_switch,
       awesome_trend, rsi_trend,
       sma_slope, regime_stay, trailing_stop,
       fast_reentry, regime_macd, dual_speed, sig_and, sig_or,
       blend_components, blend_either_on, blend_avg
# cross-asset
export align_close, sma_aligned, momentum, above_own_sma, cross_own,
       rel_strength, risk_on, gate_and, gate_or
# evaluation
export HORIZONS, rolling_compare, multiscale,
       win_cagr, win_calmar, win_sharpe, walk_forward, equity_from_sr
# data fetch / web bundle
export fetch_ohlcv, append_to_archive, update_data, write_web_bundle

end # module
