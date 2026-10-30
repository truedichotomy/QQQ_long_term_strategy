# Data loading for the `data/` ETF CSVs.
#
# ONLY THE FIRST 6 COLUMNS ARE TRUSTED: Date, Open, High, Low, Close, Volume.
# Source files may carry extra technical-indicator columns after those, but their
# count and meaning are NOT guaranteed across pulls, so we ignore everything past
# column 6 and compute every indicator ourselves (see indicators.jl). Format: fields
# are individually double-quoted; Volume carries thousands separators ("5,232,202");
# dates are ISO timestamps. We regex out each quoted field so volume commas are safe.

using Dates

"Daily OHLCV series for one ticker. Only the six guaranteed columns are stored; all technical indicators are computed from these."
struct MarketData
    ticker::String
    date::Vector{Date}
    open::Vector{Float64}
    high::Vector{Float64}
    low::Vector{Float64}
    close::Vector{Float64}
    volume::Vector{Float64}
end

Base.length(m::MarketData) = length(m.date)

_parsefloat(s::AbstractString) = isempty(s) ? NaN : parse(Float64, replace(s, "," => ""))

# Extract the content of every "..."-quoted field on a line.
_fields(line::AbstractString) = [m.captures[1] for m in eachmatch(r"\"([^\"]*)\"", line)]

"All CSVs for `ticker` inside `dir` (filenames embed the date range), sorted."
function find_data_files(ticker::AbstractString; dir::AbstractString="data")
    files = filter(f -> startswith(f, ticker * " ") || startswith(f, ticker * "("), readdir(dir))
    isempty(files) && error("No data file for $ticker in $dir/")
    return sort([joinpath(dir, f) for f in files])
end

"The single (or longest-history) CSV for `ticker`."
find_data_file(ticker::AbstractString; dir::AbstractString="data") =
    first(find_data_files(ticker; dir=dir))

# The filename's leading number is the END timestamp of that pull; a larger value
# means a more recent export, used to break ties on overlapping dates.
_file_endts(path::AbstractString) = (m = match(r"\((\d+)", basename(path)); m === nothing ? "" : String(m.captures[1]))

"""
Merge several same-ticker `MarketData` into one continuous, date-sorted series.
The time overlap between pulls is handled **by date and can be any size**: when a
day appears in more than one file, the row from the most recent pull (larger
end-timestamp) wins, so dropping in a newer overlapping file just extends/refreshes
the series.
"""
function merge_markets(parts::Vector{Tuple{MarketData,String}})
    ord = sort(parts; by = p -> p[2])            # ascending end-ts ⇒ newest pull last ⇒ it wins
    px  = Dict{Date,NTuple{5,Float64}}()
    for (m, _) in ord, i in 1:length(m)
        px[m.date[i]] = (m.open[i], m.high[i], m.low[i], m.close[i], m.volume[i])
    end
    dates = sort!(collect(keys(px))); n = length(dates)
    o = Vector{Float64}(undef, n); h = similar(o); l = similar(o); c = similar(o); v = similar(o)
    for (i, dt) in enumerate(dates)
        o[i], h[i], l[i], c[i], v[i] = px[dt]
    end
    return MarketData(parts[1][1].ticker, dates, o, h, l, c, v)
end

"Load a `data/` CSV into a `MarketData`, keeping only the six trusted columns (Date,O,H,L,C,V)."
function load_market(path::AbstractString; ticker::AbstractString=first(split(basename(path))))
    lines = readlines(path)
    n = length(lines) - 1
    date = Vector{Date}(undef, n)
    o = Vector{Float64}(undef, n); h = similar(o); l = similar(o); c = similar(o); v = similar(o)
    for i in 1:n
        f = _fields(lines[i + 1])      # columns past 6 (provider indicators) are ignored
        date[i] = Date(SubString(f[1], 1, 10))
        o[i] = _parsefloat(f[2]); h[i] = _parsefloat(f[3]); l[i] = _parsefloat(f[4])
        c[i] = _parsefloat(f[5]); v[i] = _parsefloat(f[6])
    end
    return MarketData(String(ticker), date, o, h, l, c, v)
end

"Load every `dir` CSV for `ticker` and merge them into one continuous, deduped series."
function load_ticker(ticker::AbstractString; dir::AbstractString="data")
    files = find_data_files(ticker; dir=dir)
    length(files) == 1 && return load_market(files[1]; ticker=ticker)
    parts = map(files) do f
        m = load_market(f; ticker=ticker)
        ets = _file_endts(f)
        # A file whose name has no timestamp (e.g. the live archive `QQQ (local).csv`) is
        # ranked by the latest date it covers, with a high suffix so it wins same-date ties.
        isempty(ets) && !isempty(m.date) && (ets = Dates.format(maximum(m.date), "yyyymmdd") * "999999999")
        (m, ets)
    end
    return merge_markets(parts)
end

"Index range [i0, i1] covering dates in [from, to] (clamped to available data)."
function date_range(d::MarketData, from::Date, to::Date)
    i0 = findfirst(>=(from), d.date); i0 === nothing && (i0 = 1)
    i1 = findlast(<=(to), d.date);   i1 === nothing && (i1 = length(d))
    return i0, i1
end

"A `MarketData` restricted to rows [i0, i1] (for windowed backtests)."
subset(d::MarketData, i0::Integer, i1::Integer) =
    MarketData(d.ticker, d.date[i0:i1], d.open[i0:i1], d.high[i0:i1],
               d.low[i0:i1], d.close[i0:i1], d.volume[i0:i1])

# ---- short-term interest rates (the cash yield / risk-free rate) ----

"""
A time-varying annualized rate (decimal), e.g. the 3-month T-bill yield. Passed as `rf_annual`
to `run_backtest`, it is aligned to each backtest's own dates by as-of lookup, so the same
series works unchanged on any windowed `subset` of the data.
"""
struct RateSeries
    name::String
    date::Vector{Date}
    rate::Vector{Float64}
end

"""
Annualized rate in effect on each of the (ascending) `dates`: the last observation on or
before the date (the first observation, before the series starts), floored at 0 — cash
held in a money fund doesn't earn the brief negative bill yields of March 2020.
"""
function rate_on(rs::RateSeries, dates::AbstractVector{Date})
    out = Vector{Float64}(undef, length(dates)); j = 1; m = length(rs.date)
    for (k, t) in enumerate(dates)
        while j < m && rs.date[j + 1] <= t; j += 1; end
        out[k] = max(rs.rate[j], 0.0)
    end
    return out
end

const TBILL_FILE = joinpath("rates", "TBILL_3M.csv")
const TNX_FILE   = joinpath("rates", "TNX_10Y.csv")

"""
    load_tbill(; dir="data") -> RateSeries

The daily 13-week US Treasury-bill yield (CBOE `^IRX`, the same rate as FRED DTB3), 1960 →,
from `dir/rates/TBILL_3M.csv` (refresh with `update_tbill`). Use it as the cash yield and the
Sharpe hurdle: `run_backtest(d, sig; rf_annual=load_tbill(dir=DATADIR))`.
"""
load_tbill(; dir::AbstractString="data") = load_rate(TBILL_FILE, "3M T-bill"; dir=dir)

"A `Date,Yield` (percent) rate file under `dir` as a `RateSeries` (decimal) — e.g. `TNX_FILE`."
function load_rate(file::AbstractString, name::AbstractString; dir::AbstractString="data")
    path = joinpath(dir, file)
    isfile(path) || error("No rate file at $path — fetch it with update_rate/update_tbill(dir=\"$dir\").")
    date = Date[]; rate = Float64[]
    for line in Iterators.drop(eachline(path), 1)          # header: Date,Yield (percent)
        f = split(line, ','); length(f) < 2 && continue
        push!(date, Date(f[1])); push!(rate, parse(Float64, f[2]) / 100)
    end
    return RateSeries(name, date, rate)
end

const _REPO_DATA = normpath(joinpath(@__DIR__, "..", "..", "data"))
const _TBILL = Ref{Union{Nothing,RateSeries}}(nothing)

"The repo's 3-month T-bill series (`data/rates/TBILL_3M.csv`), loaded once and cached — the
default cash yield / risk-free rate of `run_backtest`."
function tbill()
    _TBILL[] === nothing && (_TBILL[] = load_tbill(dir=_REPO_DATA))
    return _TBILL[]
end
