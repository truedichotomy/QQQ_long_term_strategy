# Pull recent daily OHLCV from a free public source (Yahoo Finance chart API) over stdlib
# Downloads — no API key, no data-service site. Used by signal.jl (auto-refresh on run) and
# fetch_data.jl. Server-side, so there are no browser CORS limits.

using Downloads, Dates, Printf

const _YAHOO_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"

_pf(s) = (s == "null" || isempty(s)) ? NaN : parse(Float64, s)

# Pull the contents of a flat numeric array `"key":[...]` out of the (fixed-shape) JSON.
function _yarr(json::AbstractString, key::AbstractString)
    m = match(Regex("\"" * key * "\":\\[([^\\]]*)\\]"), json)
    m === nothing && error("field \"$key\" not found in Yahoo response")
    return String.(split(m.captures[1], ","))
end

"""
    fetch_ohlcv(ticker; n=10) -> Vector{NamedTuple}

Fetch up to the last `n` trading days of daily OHLCV for `ticker` from Yahoo Finance.
Returns rows `(date, o, h, l, c, v)`. Throws on network/parse failure (caller can fall back).
"""
function fetch_ohlcv(ticker::AbstractString; n::Integer=10)
    range = n <= 55 ? "3mo" : n <= 115 ? "6mo" : n <= 230 ? "1y" : "2y"
    url = "https://query1.finance.yahoo.com/v8/finance/chart/$ticker?range=$range&interval=1d"
    io = IOBuffer()
    Downloads.download(url, io; headers = ["User-Agent" => _YAHOO_UA], timeout = 30)
    json = String(take!(io))
    occursin("\"error\":{", json) && error("Yahoo returned an error for $ticker (unknown symbol?)")
    ts = _yarr(json, "timestamp")
    op = _yarr(json, "open"); hi = _yarr(json, "high"); lo = _yarr(json, "low")
    cl = _yarr(json, "close"); vo = _yarr(json, "volume")
    rows = NamedTuple[]
    for i in eachindex(ts)
        c = _pf(cl[i]); isnan(c) && continue                       # skip holiday / null bars
        push!(rows, (date = Date(unix2datetime(parse(Int, ts[i]))),
                     o = _pf(op[i]), h = _pf(hi[i]), l = _pf(lo[i]), c = c, v = _pf(vo[i])))
    end
    isempty(rows) && error("no usable rows parsed from Yahoo for $ticker")
    return length(rows) > n ? rows[end - n + 1:end] : rows
end

# The auto-pulled "live overlay" uses one FIXED filename whose end-timestamp is the maximal
# sentinel (all 9s), so in load_ticker it always wins date-overlap dedupe and never
# proliferates — it is overwritten in place on each run. The curated history files are the base.
_live_path(ticker, dir) = joinpath(dir, "$ticker (99999999999999999 _ 00000000000000000).csv")

"Write fetched `rows` as the canonical live-overlay CSV (load_ticker format) for `ticker`."
function write_live_overlay(ticker::AbstractString, rows; dir::AbstractString)
    path = _live_path(ticker, dir)
    open(path, "w") do io
        println(io, "\"Date\",\"Open\",\"High\",\"Low\",\"Close\",\"Volume\"")
        for r in rows
            @printf(io, "\"%sT00:00:00.000Z\",\"%.2f\",\"%.2f\",\"%.2f\",\"%.2f\",\"%d\"\n",
                    r.date, r.o, r.h, r.l, r.c, isnan(r.v) ? 0 : round(Int, r.v))
        end
    end
    return path
end

"""
    update_data(ticker; dir, n=10) -> rows

Fetch the latest `n` bars for `ticker` and write them as the live overlay in `dir`, so the next
`load_ticker(ticker)` merges them in (dedup by date, this pull wins). Returns the fetched rows.
"""
function update_data(ticker::AbstractString; dir::AbstractString, n::Integer=10)
    rows = fetch_ohlcv(ticker; n = n)
    write_live_overlay(ticker, rows; dir = dir)
    return rows
end

const _WEB_HEADER = "/* Bundled QQQ daily OHLCV (merged from data/) so the page shows a signal on open.\n" *
                    "   Generated — refresh with: julia analysis/fetch_data.jl (or node web/build_data.js). Do not hand-edit. */"

"Regenerate the web app's bundled data file (`web/data.js`) from an already-loaded series."
function write_web_bundle(d::MarketData; path::AbstractString)
    open(path, "w") do io
        println(io, _WEB_HEADER)
        print(io, "window.QQQ_DATA=\"")
        for i in 1:length(d)
            i > 1 && print(io, "\\n")
            @printf(io, "%s,%.2f,%.2f,%.2f,%.2f,%d",
                    d.date[i], d.open[i], d.high[i], d.low[i], d.close[i], round(Int, d.volume[i]))
        end
        println(io, "\";")
    end
    return path
end
