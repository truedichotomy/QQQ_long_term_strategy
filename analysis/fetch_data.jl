# Pull recent daily OHLCV for a ticker from a FREE public source (Yahoo Finance) — no API
# key, no specialized data-service website. Prints the last N trading days and (unless
# --no-save) merges them into data/ as the live overlay, then refreshes the web bundle for
# QQQ. `signal.jl` already does this automatically on each run; use this to fetch/inspect
# explicitly or for other tickers.
#
#   julia analysis/fetch_data.jl            # QQQ, last 10 trading days → print + merge into data/
#   julia analysis/fetch_data.jl SPY 20     # any ticker, last 20 days
#   julia analysis/fetch_data.jl --no-save  # just print, don't touch data/

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Dates

const DATADIR = joinpath(dirname(@__DIR__), "data")
const WEBDIR  = joinpath(dirname(@__DIR__), "web")

ticker = "QQQ"; n = 10; save = true
for a in ARGS
    if a == "--no-save"; global save = false
    elseif a == "--save"; global save = true
    elseif all(isdigit, a); global n = parse(Int, a)
    elseif !startswith(a, "--"); global ticker = uppercase(a)
    end
end
n < 1 && error("N must be ≥ 1")

@printf("Fetching %s daily OHLCV from Yahoo Finance…\n", ticker)
rows = fetch_ohlcv(ticker; n=n)

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

if save
    path = write_live_overlay(ticker, rows; dir=DATADIR)
    @printf("\nMerged into data/ as the live overlay → %s\n", basename(path))
    if ticker == "QQQ" && isdir(WEBDIR)
        write_web_bundle(load_ticker("QQQ"; dir=DATADIR); path=joinpath(WEBDIR, "data.js"))
        println("Refreshed web/data.js.")
    end
    println("Re-run the signal: julia analysis/signal.jl --no-fetch")
else
    println("\n(--no-save: nothing written to data/)")
end
