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
# Is the regular session in progress right now? Then today's daily bar is still forming
# (provisional). True iff regular.start ≤ regularMarketTime < regular.end — false on
# weekends/holidays/after-hours, when the last trade time isn't inside an open session.
function _market_open(json::AbstractString)
    m1 = match(r"\"regularMarketTime\":(\d+)", json)
    m2 = match(r"\"regular\":\{[^}]*?\"start\":(\d+),\"end\":(\d+)", json)
    (m1 === nothing || m2 === nothing) && return false
    t = parse(Int, m1.captures[1]); s = parse(Int, m2.captures[1]); e = parse(Int, m2.captures[2])
    return s <= t < e
end

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
                     o = _pf(op[i]), h = _pf(hi[i]), l = _pf(lo[i]), c = c, v = _pf(vo[i]), p = false))
    end
    isempty(rows) && error("no usable rows parsed from Yahoo for $ticker")
    out = length(rows) > n ? rows[end - n + 1:end] : rows
    _market_open(json) && (out[end] = merge(out[end], (p = true,)))   # mark today's in-progress bar provisional
    return out
end

# The accumulating local archive is one fixed-name file, `TICKER (local).csv`, in data/.
# It is NOT overwritten with only the latest fetch — fetched bars are MERGED into it, so over
# time it becomes a continuous, growing record (independent of how far back Yahoo currently
# reaches). `load_ticker` ranks it by the latest date it covers, so it wins date-overlap dedupe
# against the curated base. Committed, so the record is version-controlled and backed up.
_archive_path(ticker, dir) = joinpath(dir, "$ticker (local).csv")

# The archive carries a 7th "Provisional" column ("P" = collected mid-session, still forming).
# The loader trusts only the first 6 columns, so this flag never affects computed indicators —
# it just marks the bar so the next fetch knows to overwrite it with the final session values.
function _write_archive(ticker::AbstractString, rows; dir::AbstractString)
    path = _archive_path(ticker, dir)
    open(path, "w") do io
        println(io, "\"Date\",\"Open\",\"High\",\"Low\",\"Close\",\"Volume\",\"Provisional\"")
        for r in rows
            @printf(io, "\"%sT00:00:00.000Z\",\"%.2f\",\"%.2f\",\"%.2f\",\"%.2f\",\"%d\",\"%s\"\n",
                    r.date, r.o, r.h, r.l, r.c, isnan(r.v) ? 0 : round(Int, r.v), get(r, :p, false) ? "P" : "")
        end
    end
    return path
end

function _read_archive_rows(path)
    isfile(path) || return NamedTuple[]
    lines = readlines(path); rows = NamedTuple[]
    for k in 2:length(lines)                        # skip header
        f = _fields(lines[k]); length(f) < 6 && continue
        push!(rows, (date = Date(SubString(f[1], 1, 10)),
                     o = _parsefloat(f[2]), h = _parsefloat(f[3]), l = _parsefloat(f[4]),
                     c = _parsefloat(f[5]), v = _parsefloat(f[6]), p = (length(f) >= 7 && f[7] == "P")))
    end
    return rows
end

function _merge_rows_by_date(existing, incoming)        # incoming wins on duplicate dates
    byd = Dict{Date,Any}()
    for r in existing;  byd[r.date] = r; end
    for r in incoming;  byd[r.date] = r; end
    return [byd[d] for d in sort(collect(keys(byd)))]
end

# Latest date present in a single data file (reads the last dated line).
function _file_last_date(path)
    lines = readlines(path)
    for i in length(lines):-1:1
        mm = match(r"(\d{4}-\d{2}-\d{2})", lines[i])
        mm !== nothing && return Date(mm.captures[1])
    end
    return nothing
end

"Latest date present across `ticker`'s data files (optionally excluding one path)."
function _last_date_in_data(ticker, dir; exclude=nothing)
    files = try find_data_files(ticker; dir=dir) catch; String[] end
    last = nothing
    for f in files
        f == exclude && continue
        d = _file_last_date(f)
        d !== nothing && (last === nothing || d > last) && (last = d)
    end
    return last
end

"""
    append_to_archive(ticker, rows; dir) -> (added, total, first, last)

Merge `rows` into the persistent local archive (dedup by date, new wins), then keep only the
dates BEYOND what the committed/curated files already cover. So the archive is a clean
forward-extension: a fresh master file dropped into `data/` (ahead of the archive) always
supersedes it — the now-covered dates drop out of the archive automatically, with no gap (the
master file provides them, independent of how far Yahoo can reach). If no curated file exists,
nothing is pruned and the archive is self-contained. Returns counts and the archive's span.
"""
function append_to_archive(ticker::AbstractString, rows; dir::AbstractString)
    path = _archive_path(ticker, dir)
    before = Set(r.date for r in _read_archive_rows(path))
    merged = _merge_rows_by_date(_read_archive_rows(path), rows)
    cutoff = _last_date_in_data(ticker, dir; exclude=path)     # latest date the curated/master files cover
    cutoff !== nothing && (merged = filter(r -> r.date > cutoff, merged))
    _write_archive(ticker, merged; dir=dir)
    prov = (!isempty(merged) && get(merged[end], :p, false)) ? merged[end].date : nothing
    return (added = count(r -> !(r.date in before), merged), total = length(merged),
            first = isempty(merged) ? nothing : merged[1].date,
            last  = isempty(merged) ? nothing : merged[end].date, provisional = prov)
end

"The date of the archive's last bar if it is provisional (mid-session), else `nothing`."
function archive_provisional(ticker::AbstractString; dir::AbstractString)
    rows = _read_archive_rows(_archive_path(ticker, dir))
    (!isempty(rows) && get(rows[end], :p, false)) ? rows[end].date : nothing
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

# ---- market clock (US Eastern, DST-aware, no packages) + fetch-throttle helper ----
function _et_offset(u::DateTime)
    y = year(u)
    nth_sun(mn, k) = (d = Date(y, mn, 1); DateTime(d + Day(mod(7 - dayofweek(d), 7) + 7 * (k - 1))))
    dst_start = nth_sun(3, 2) + Hour(7)      # 2 AM EST = 07:00 UTC, 2nd Sunday of March
    dst_end   = nth_sun(11, 1) + Hour(6)     # 2 AM EDT = 06:00 UTC, 1st Sunday of November
    return (dst_start <= u < dst_end) ? -4 : -5
end

"Current wall-clock time in US Eastern (DST-aware), as a `DateTime`."
now_et() = (u = now(UTC); u + Hour(_et_offset(u)))

"Is the US regular equity session open right now? (weekday 09:30–16:00 ET; ignores holidays.)"
function market_open_et()
    et = now_et(); dayofweek(et) >= 6 && return false
    m = hour(et) * 60 + minute(et)
    return 570 <= m < 960
end

"Seconds since `ticker`'s local archive was last written (Inf if it doesn't exist)."
archive_age(ticker::AbstractString; dir::AbstractString) =
    (p = _archive_path(ticker, dir); isfile(p) ? time() - mtime(p) : Inf)

# Most recent date with a COMPLETED regular session as of `et` — the latest weekday whose
# 16:00 ET close has already passed. Ignores holidays (at worst it triggers one harmless extra
# fetch on a holiday). Used to decide whether local data has fallen behind, even when closed.
function _last_session(et::DateTime)
    d = Date(et)
    closed_today = dayofweek(d) <= 5 && hour(et) * 60 + minute(et) >= 960   # weekday, past 16:00 ET
    closed_today || (d -= Day(1))
    while dayofweek(d) > 5; d -= Day(1); end                                # back to a weekday
    return d
end

"Date of the most recent completed regular session as of now (ignores holidays)."
last_session_date() = _last_session(now_et())

"Regenerate the web app's bundled data file (`web/data.js`) from an already-loaded series; the
`provisional` date (if any) gets a 7th `,P` field so the page can flag it as a mid-session bar."
function write_web_bundle(d::MarketData; path::AbstractString, provisional=nothing)
    open(path, "w") do io
        println(io, _WEB_HEADER)
        print(io, "window.QQQ_DATA=\"")
        for i in 1:length(d)
            i > 1 && print(io, "\\n")
            @printf(io, "%s,%.2f,%.2f,%.2f,%.2f,%d%s",
                    d.date[i], d.open[i], d.high[i], d.low[i], d.close[i], round(Int, d.volume[i]),
                    (provisional !== nothing && d.date[i] == provisional) ? ",P" : "")
        end
        println(io, "\";")
    end
    return path
end
