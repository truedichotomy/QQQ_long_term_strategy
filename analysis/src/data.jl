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
    return merge_markets([(load_market(f; ticker=ticker), _file_endts(f)) for f in files])
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
