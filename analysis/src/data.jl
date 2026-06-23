# Data loading for the `data/` ETF CSVs.
#
# Format notes (see ../../CLAUDE.md): fields are individually double-quoted,
# Volume carries thousands separators ("5,232,202"), dates are ISO timestamps,
# and indicator columns are empty until each indicator's look-back window fills.
# We extract every quoted field with a regex so internal volume commas and
# trailing empty cells are handled correctly, then map empty -> NaN.

using Dates

"All daily series for one ticker. Indicators precomputed in the source file live in `ind`."
struct MarketData
    ticker::String
    date::Vector{Date}
    open::Vector{Float64}
    high::Vector{Float64}
    low::Vector{Float64}
    close::Vector{Float64}
    volume::Vector{Float64}
    ind::Dict{Symbol,Vector{Float64}}
end

Base.length(m::MarketData) = length(m.date)

# source column index (1-based) => clean field name
const INDICATOR_COLUMNS = (
    7  => :cci40,        # Commodity Channel Index, 40
    8  => :ma30,         # SMA(30, close)
    9  => :ma2,          # SMA(2, close)
    10 => :ma40,         # SMA(40, close)
    11 => :awesome,      # Awesome oscillator histogram
    12 => :ma60,         # SMA(60, close)
    13 => :macd,         # MACD(12,26,9) line
    14 => :macd_signal,  # MACD signal line
    15 => :macd_hist,    # MACD histogram
    16 => :ma13_open,    # SMA(13, open)
    17 => :di_plus,      # +DI(14)
    18 => :di_minus,     # -DI(14)
    19 => :adx,          # ADX(14)
)

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
the series. Indicator columns come from whichever pull supplies each date.
"""
function merge_markets(parts::Vector{Tuple{MarketData,String}})
    syms = collect(keys(parts[1][1].ind))
    ord  = sort(parts; by = p -> p[2])           # ascending end-ts ⇒ newest pull last ⇒ it wins
    px   = Dict{Date,NTuple{5,Float64}}()
    ind  = Dict{Date,Dict{Symbol,Float64}}()
    for (m, _) in ord, i in 1:length(m)
        px[m.date[i]]  = (m.open[i], m.high[i], m.low[i], m.close[i], m.volume[i])
        ind[m.date[i]] = Dict(s => m.ind[s][i] for s in syms)
    end
    dates = sort!(collect(keys(px))); n = length(dates)
    o = Vector{Float64}(undef, n); h = similar(o); l = similar(o); c = similar(o); v = similar(o)
    id = Dict(s => Vector{Float64}(undef, n) for s in syms)
    for (i, dt) in enumerate(dates)
        o[i], h[i], l[i], c[i], v[i] = px[dt]
        for s in syms; id[s][i] = ind[dt][s]; end
    end
    return MarketData(parts[1][1].ticker, dates, o, h, l, c, v, id)
end

"Load and parse a `data/` CSV into a `MarketData`."
function load_market(path::AbstractString; ticker::AbstractString=first(split(basename(path))))
    lines = readlines(path)
    n = length(lines) - 1
    date = Vector{Date}(undef, n)
    o = Vector{Float64}(undef, n); h = similar(o); l = similar(o); c = similar(o); v = similar(o)
    ind = Dict{Symbol,Vector{Float64}}(sym => Vector{Float64}(undef, n) for (_, sym) in INDICATOR_COLUMNS)
    for i in 1:n
        f = _fields(lines[i + 1])
        date[i] = Date(SubString(f[1], 1, 10))
        o[i] = _parsefloat(f[2]); h[i] = _parsefloat(f[3]); l[i] = _parsefloat(f[4])
        c[i] = _parsefloat(f[5]); v[i] = _parsefloat(f[6])
        for (col, sym) in INDICATOR_COLUMNS
            ind[sym][i] = _parsefloat(f[col])
        end
    end
    return MarketData(String(ticker), date, o, h, l, c, v, ind)
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
