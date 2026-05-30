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

"Locate the single CSV for `ticker` inside `dir` (filenames embed the date range)."
function find_data_file(ticker::AbstractString; dir::AbstractString="data")
    files = filter(f -> startswith(f, ticker * " ") || startswith(f, ticker * "("), readdir(dir))
    isempty(files) && error("No data file for $ticker in $dir/")
    return joinpath(dir, first(sort(files)))
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

load_ticker(ticker::AbstractString; dir::AbstractString="data") =
    load_market(find_data_file(ticker; dir=dir); ticker=ticker)

"Index range [i0, i1] covering dates in [from, to] (clamped to available data)."
function date_range(d::MarketData, from::Date, to::Date)
    i0 = findfirst(>=(from), d.date); i0 === nothing && (i0 = 1)
    i1 = findlast(<=(to), d.date);   i1 === nothing && (i1 = length(d))
    return i0, i1
end
