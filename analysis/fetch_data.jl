# Fetch recent daily OHLCV for a ticker from a FREE public source — no API key,
# no specialized data-service website, no signup. Uses the Yahoo Finance chart
# API over Julia's stdlib `Downloads` (libcurl), so it stays zero-dependency.
#
# Prints the last N trading days, and (unless --no-save) writes a CSV into ../data
# in the format `load_ticker` understands, so it merges with the existing history
# by date (newest pull wins on overlap). Refresh-and-signal in two commands:
#
#   julia analysis/fetch_data.jl            # QQQ, last 10 trading days → print + save to data/
#   julia analysis/fetch_data.jl SPY 20     # any ticker, last 20 days
#   julia analysis/fetch_data.jl --no-save  # just print, don't touch data/
#   julia analysis/signal.jl                # then re-run the signal on the refreshed data

using Downloads, Dates, Printf

# ---- args: optional TICKER (word), N (number), --no-save / --save ----
ticker = "QQQ"; n = 10; save = true
for a in ARGS
    if a == "--no-save"; global save = false
    elseif a == "--save"; global save = true
    elseif all(isdigit, a); global n = parse(Int, a)
    elseif !startswith(a, "--"); global ticker = uppercase(a)
    end
end
n < 1 && error("N must be ≥ 1")

# range must comfortably cover N trading days (~21 trading days/month)
range = n <= 55 ? "3mo" : n <= 115 ? "6mo" : n <= 230 ? "1y" : "2y"
url = "https://query1.finance.yahoo.com/v8/finance/chart/$ticker?range=$range&interval=1d"

@printf("Fetching %s daily OHLCV from Yahoo Finance (range=%s)…\n", ticker, range)
buf = IOBuffer()
Downloads.download(url, buf;
    headers = ["User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"], timeout = 30)
json = String(take!(buf))

occursin("\"error\":{", json) && error("Yahoo returned an error for $ticker (unknown symbol?). Response: $(first(json, 300))")

# ---- parse the fixed Yahoo chart structure (no JSON lib needed) ----
# Each indicator is a flat numeric array; pull the contents between `"key":[` and `]`.
function jarr(j, key)
    m = match(Regex("\"" * key * "\":\\[([^\\]]*)\\]"), j)
    m === nothing && error("field \"$key\" not found in Yahoo response")
    return String.(split(m.captures[1], ","))
end
pf(s) = (s == "null" || isempty(s)) ? NaN : parse(Float64, s)

ts  = jarr(json, "timestamp")
op  = jarr(json, "open");  hi = jarr(json, "high"); lo = jarr(json, "low")
cl  = jarr(json, "close"); vo = jarr(json, "volume")

rows = NamedTuple[]
for i in eachindex(ts)
    c = pf(cl[i]); isnan(c) && continue                      # skip holidays / null bars
    push!(rows, (date = Date(unix2datetime(parse(Int, ts[i]))),
                 o = pf(op[i]), h = pf(hi[i]), l = pf(lo[i]), c = c, v = pf(vo[i])))
end
isempty(rows) && error("no usable rows parsed from Yahoo response")
rows = rows[max(1, end - n + 1):end]                          # last N trading days

# ---- print ----
@printf("\n%s — last %d trading days (%s … %s)\n", ticker, length(rows), rows[1].date, rows[end].date)
@printf("%-12s %10s %10s %10s %10s %14s\n", "Date", "Open", "High", "Low", "Close", "Volume")
println("-"^72)
for r in rows
    @printf("%-12s %10.2f %10.2f %10.2f %10.2f %14d\n",
            r.date, r.o, r.h, r.l, r.c, isnan(r.v) ? 0 : round(Int, r.v))
end
if rows[end].date == today()
    println("\nNote: the last row is today — it may be a partial/intraday bar if the market is still")
    println("      open. Run after the close to capture the official daily OHLCV.")
end

# ---- save a load_ticker-compatible CSV (fields double-quoted; only the 6 OHLCV
#      columns matter; date's first 10 chars are parsed; volume commas are stripped) ----
if save
    datadir = joinpath(dirname(@__DIR__), "data")
    # ENDts uses the fetch time so this pull always wins overlap dedupe (newest-wins);
    # STARTts is the first fetched date. Both are the 17-digit yyyymmdd+time form.
    endts   = Dates.format(now(), "yyyymmddHHMMSSsss")
    startts = Dates.format(rows[1].date, "yyyymmdd") * "000000000"
    path = joinpath(datadir, "$ticker ($endts _ $startts).csv")
    open(path, "w") do io
        println(io, "\"Date\",\"Open\",\"High\",\"Low\",\"Close\",\"Volume\"")
        for r in rows
            @printf(io, "\"%sT00:00:00.000Z\",\"%.2f\",\"%.2f\",\"%.2f\",\"%.2f\",\"%d\"\n",
                    r.date, r.o, r.h, r.l, r.c, isnan(r.v) ? 0 : round(Int, r.v))
        end
    end
    @printf("\nSaved %d rows → %s\n", length(rows), path)
    println("`load_ticker` will merge it by date (newest pull wins). Re-run: julia analysis/signal.jl")
else
    println("\n(--no-save: nothing written to data/)")
end
