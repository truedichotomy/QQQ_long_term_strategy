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
    range = n <= 55 ? "3mo" : n <= 115 ? "6mo" : n <= 230 ? "1y" : n <= 480 ? "2y" : n <= 1250 ? "5y" : "max"
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

# The accumulating local archive is one fixed-name file, `TICKER (local).csv`, in data/.
# It is NOT overwritten with only the latest fetch — fetched bars are MERGED into it, so over
# time it becomes a continuous, growing record (independent of how far back Yahoo currently
# reaches). `load_ticker` ranks it by the latest date it covers, so it wins date-overlap dedupe
# against the curated base. Committed, so the record is version-controlled and backed up.
_archive_path(ticker, dir) = joinpath(dir, "$ticker (local).csv")

"Write `rows` to the archive CSV for `ticker` (load_ticker format)."
function _write_archive(ticker::AbstractString, rows; dir::AbstractString)
    path = _archive_path(ticker, dir)
    open(path, "w") do io
        println(io, "\"Date\",\"Open\",\"High\",\"Low\",\"Close\",\"Volume\"")
        for r in rows
            @printf(io, "\"%sT00:00:00.000Z\",\"%.2f\",\"%.2f\",\"%.2f\",\"%.2f\",\"%d\"\n",
                    r.date, r.o, r.h, r.l, r.c, isnan(r.v) ? 0 : round(Int, r.v))
        end
    end
    return path
end

_read_archive_rows(path) = !isfile(path) ? NamedTuple[] :
    (m = load_market(path); [(date=m.date[i], o=m.open[i], h=m.high[i], l=m.low[i], c=m.close[i], v=m.volume[i]) for i in 1:length(m)])

function _merge_rows_by_date(existing, incoming)        # incoming wins on duplicate dates
    byd = Dict{Date,Any}()
    for r in existing;  byd[r.date] = r; end
    for r in incoming;  byd[r.date] = r; end
    return [byd[d] for d in sort(collect(keys(byd)))]
end

"Read the latest date present in any of `ticker`'s data files (to size a gap-bridging fetch)."
function _last_date_in_data(ticker, dir)
    files = try find_data_files(ticker; dir=dir) catch; String[] end
    last = nothing
    for f in files
        lines = readlines(f)
        for i in length(lines):-1:1
            mm = match(r"(\d{4}-\d{2}-\d{2})", lines[i])
            if mm !== nothing
                d = Date(mm.captures[1]); (last === nothing || d > last) && (last = d); break
            end
        end
    end
    return last
end

"""
    append_to_archive(ticker, rows; dir) -> (added, total, first, last)

Merge `rows` into the persistent local archive for `ticker` (accumulates across runs; dedup by
date, new rows win on overlap). Returns counts and the archive's date span.
"""
function append_to_archive(ticker::AbstractString, rows; dir::AbstractString)
    existing = _read_archive_rows(_archive_path(ticker, dir))
    merged = _merge_rows_by_date(existing, rows)
    _write_archive(ticker, merged; dir=dir)
    return (added = length(merged) - length(existing), total = length(merged),
            first = merged[1].date, last = merged[end].date)
end

"""
    update_data(ticker; dir, min_days=15) -> (added, total, first, last)

Fetch enough recent bars from Yahoo to bridge from the local data's last date to today (so the
record stays gap-free even if you run only occasionally), and merge them into the persistent
local archive. Returns the archive stats.
"""
function update_data(ticker::AbstractString; dir::AbstractString, min_days::Integer=15)
    last = _last_date_in_data(ticker, dir)
    n = last === nothing ? 1250 : max(min_days, Dates.value(today() - last) + 5)
    rows = fetch_ohlcv(ticker; n=n)
    return append_to_archive(ticker, rows; dir=dir)
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
