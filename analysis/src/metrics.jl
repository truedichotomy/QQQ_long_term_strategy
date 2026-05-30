# Performance metrics for an equity curve. CAGR and max drawdown are the two
# the project cares about most (beat B&H on CAGR, no worse on drawdown); the
# rest contextualize risk-adjusted quality.

using Statistics, Printf

struct Metrics
    total_return::Float64
    cagr::Float64
    vol::Float64          # annualized stdev of daily returns
    sharpe::Float64       # excess-over-cash, annualized
    sortino::Float64      # downside-only, annualized
    maxdd::Float64        # most negative drawdown (e.g. -0.55)
    calmar::Float64       # cagr / |maxdd|
    pct_invested::Float64 # average exposure
    ntrades::Int          # number of days exposure changed
    years::Float64
end

"Compute headline metrics from a `BacktestResult`."
function compute_metrics(b::BacktestResult)
    eq = b.eq; n = length(eq)
    years = Dates.value(b.date[end] - b.date[1]) / 365.25
    tot = eq[end] / eq[1] - 1
    cagr = (eq[end] / eq[1])^(1 / years) - 1
    er = [eq[i] / eq[i - 1] - 1 for i in 2:n]               # equity daily returns
    rf = (1 + b.rf_annual)^(1 / 252) - 1
    μ = mean(er); σ = std(er)
    sharpe = σ == 0 ? 0.0 : (μ - rf) / σ * sqrt(252)
    downside = sqrt(mean(x -> min(x - rf, 0.0)^2, er))
    sortino = downside == 0 ? 0.0 : (μ - rf) / downside * sqrt(252)
    mdd = max_drawdown(eq)
    calmar = mdd == 0 ? Inf : cagr / abs(mdd)
    pinv = mean(b.pos)
    nt = count(i -> b.pos[i] != b.pos[i - 1], 2:n)
    return Metrics(tot, cagr, σ * sqrt(252), sharpe, sortino, mdd, calmar, pinv, nt, years)
end

const METRIC_HEADER = @sprintf("%-26s %8s %8s %8s %7s %7s %8s %7s %6s %6s",
    "strategy", "CAGR", "total", "maxDD", "vol", "Sharpe", "Sortino", "Calmar", "%inv", "trades")

function metric_row(name::AbstractString, m::Metrics)
    @sprintf("%-26s %7.2f%% %7.1fx %7.1f%% %6.1f%% %7.2f %8.2f %7.2f %5.0f%% %6d",
        name, 100m.cagr, m.total_return + 1, 100m.maxdd, 100m.vol,
        m.sharpe, m.sortino, m.calmar, 100m.pct_invested, m.ntrades)
end
