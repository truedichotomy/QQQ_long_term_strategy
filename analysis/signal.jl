# Print today's QQQ signal for the chosen overlay — the EITHER-ON blend (trend filter ∪
# momentum filter) and the AVG ½-size blend — with the breakdown of both component filters.
#
# Data pulls are throttled to spare the free Yahoo API:
#   • default: fetch only if the market is OPEN and the local data is >1h old; otherwise use
#     the local stored data (when the market is closed the last close is already final).
#   • --fetch    force a fresh pull   ·   --no-fetch   never pull (offline)
# Actionable bar: before noon ET the signal reports the last COMPLETED session (today's bar is
# barely formed); after noon it uses today's in-progress (provisional) bar to plan tomorrow.
#
#   julia analysis/signal.jl            # QQQ
#   julia analysis/signal.jl SPY        # any ticker present in ../data
#   julia analysis/signal.jl --fetch    # force a pull   ·   --no-fetch to stay offline

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Dates

const DATADIR = joinpath(dirname(@__DIR__), "data")
const WEBDIR  = joinpath(dirname(@__DIR__), "web")

function show_signal(ticker; mode::Symbol=:auto)
    # ---- fetch decision ----
    # Pull from Yahoo only when worth it: throttle to ≤1×/hour, and (in :auto) fetch when the
    # market is OPEN *or* the local data is behind the most recent completed session — so a run
    # after the close still catches up if we've missed a day or more. One exception bypasses the
    # hour throttle: right after the close, finalize a still-provisional bar (its real session
    # close is now known) — a 60s floor just avoids hammering on rapid re-runs. --fetch forces,
    # --no-fetch skips.
    age = archive_age(ticker; dir=DATADIR)
    d = load_ticker(ticker; dir=DATADIR)
    mkt_open = market_open_et()
    stale = d.date[end] < last_session_date()
    finalize = archive_provisional(ticker; dir=DATADIR) !== nothing && !mkt_open
    do_fetch = mode == :force ||
               (mode == :auto && ((age >= 3600 && (mkt_open || stale)) || (finalize && age >= 60)))
    if do_fetch
        try
            st = update_data(ticker; dir=DATADIR)
            if st.gap !== nothing
                @printf("⚠ DATA GAP — local data ends %s, but the free Yahoo window only reaches back to %s\n",
                        st.gap.local_last, st.gap.fetch_first)
                @printf("   (~%d days unbridged). The database is too stale to update automatically; the\n",
                        Dates.value(st.gap.fetch_first - st.gap.local_last))
                println("   disconnected bars were NOT appended. Drop a fresh full-history QQQ CSV into data/ to repair.")
            else
                @printf("↻ fetched latest from Yahoo — local archive: %s\n",
                        st.total == 0 ? "empty (committed data already current)" :
                        @sprintf("%d bar(s) beyond committed data (%s … %s), +%d new", st.total, st.first, st.last, st.added))
            end
            d = load_ticker(ticker; dir=DATADIR)        # reload to include the freshly fetched bars
        catch e
            @printf("⚠ could not fetch latest data (%s) — using existing local data\n", sprint(showerror, e))
        end
    else
        why = mode == :never ? "--no-fetch" :
              age < 3600     ? "pulled <1h ago" :
                               "market closed, data already current"
        agestr = isfinite(age) ? @sprintf(", last pull %dm ago", round(Int, age / 60)) : ""
        @printf("• not fetching (%s%s) — using local data; pass --fetch to force a refresh\n", why, agestr)
    end
    n = length(d)

    # ---- warn on any unbridged hole in the recent history (would distort the long-window
    #      indicators that feed the signal); the fetch path above refuses to create one, so this
    #      catches holes in curated files dropped into data/. ----
    let lo = max(2, n - 220)
        holes = [(d.date[i-1], d.date[i]) for i in lo:n if Dates.value(d.date[i] - d.date[i-1]) > 6]
        isempty(holes) || begin
            @printf("⚠ DATA GAP in recent history (%d hole%s, e.g. %s → %s) — indicators spanning it may be\n",
                    length(holes), length(holes) == 1 ? "" : "s", holes[end][1], holes[end][2])
            println("   off; drop a continuous QQQ file into data/ to repair.")
        end
    end

    # ---- actionable bar: before noon ET, act on the last completed session rather than
    #      today's still-forming (provisional) bar ----
    prov = archive_provisional(ticker; dir=DATADIR)
    et = now_et()
    si = n
    if prov !== nothing && prov == d.date[n] && d.date[n] == Date(et) && hour(et) < 12
        si = max(1, n - 1)
    end

    s50 = sma(d.close, 50); s200 = sma(d.close, 200)
    c40 = cci(d.high, d.low, d.close, 40); t200 = tma(d.close, 200)
    mom, trend = blend_components(d); either = blend_either_on(d); avg = blend_avg(d)
    bear = si > 20 && !isnan(t200[si]) && !isnan(t200[si-20]) && t200[si] < t200[si-20]
    mom_exit = bear ? 0 : -100
    instate(x) = x == 1 ? "IN " : "OUT"
    lc(s) = (x = 1; for i in 2:si; s[i] != s[i-1] && (x = i); end; x)    # last change at/through si

    asnote = si < n ?
        @sprintf("   (today's forming bar %s held — before noon; re-run after noon to use it)", d.date[n]) :
        (prov !== nothing && prov == d.date[si]) ? "   ⚠ PROVISIONAL (today's mid-session bar — not yet final)" : ""

    println("="^64)
    @printf("%s  blend signal  —  as of %s   (%s ET · market %s)\n",
            ticker, d.date[si], Dates.format(et, "HH:MM"), mkt_open ? "OPEN" : "closed")
    isempty(asnote) || println(asnote)
    println("="^64)
    @printf("  close %.2f      SMA-50 %.0f %s SMA-200 %.0f      CCI(40) %.0f\n",
            d.close[si], s50[si], s50[si] > s200[si] ? ">" : "<", s200[si], c40[si])
    println("-"^64)
    println("  COMPONENT FILTERS")
    @printf("   • Trend  (SMA 50/200 fast-reentry): %s  since %s\n", instate(trend[si]), d.date[lc(trend)])
    @printf("       SMA-50 is %s SMA-200\n", s50[si] > s200[si] ? "ABOVE (uptrend)" : "BELOW (downtrend)")
    @printf("   • Moment (CCI40 -100/0 + TMA switch): %s  since %s\n", instate(mom[si]), d.date[lc(mom)])
    @printf("       CCI(40) %.0f vs exit %d   (TMA-200 slope %s ⇒ exit at %d)\n",
            c40[si], mom_exit, bear ? "DOWN" : "UP", mom_exit)
    println("-"^64)
    println("  RECOMMENDATIONS  (the same two filters, combined two ways)")
    if either[si] == 1
        @printf("   ► Either-on   ▲ BUY / HOLD — 100%% %s         (max return, ~3 trades/yr)\n", ticker)
        @printf("       %s; in QQQ since %s\n",
                trend[si] == 1 && mom[si] == 1 ? "both filters IN" : "at least one filter IN", d.date[lc(either)])
    else
        @printf("   ► Either-on   ▼ SELL / WAIT — hold cash       (max return, ~3 trades/yr)\n")
        @printf("       both filters OUT; in cash since %s\n", d.date[lc(either)])
    end
    ex = round(Int, 100avg[si])
    if ex >= 100
        @printf("   ► Avg ½-size  ▲ HOLD — 100%% %s               (smoother ride, ~12 trades/yr)\n", ticker)
        @printf("       both filters IN; at this exposure since %s\n", d.date[lc(avg)])
    elseif ex <= 0
        @printf("   ► Avg ½-size  ▼ SELL / WAIT — hold cash       (smoother ride, ~12 trades/yr)\n")
        @printf("       both filters OUT; at this exposure since %s\n", d.date[lc(avg)])
    else
        @printf("   ► Avg ½-size  ◐ HALF — 50%% %s / 50%% cash     (smoother ride, ~12 trades/yr)\n", ticker)
        @printf("       one filter IN, one OUT; at this exposure since %s\n", d.date[lc(avg)])
    end
    println("-"^64)
    println("  Either-on: in QQQ unless BOTH filters are OUT (re-enter when either turns IN).")
    println("  Avg: hold the average of the two — 100% if both IN, 50% if one, cash if none.")

    if ticker == "QQQ" && isdir(WEBDIR)
        try
            write_web_bundle(d; path=joinpath(WEBDIR, "data.js"), provisional=prov)
            println("↻ refreshed web/data.js (open web/index.html for the same signal in a browser)")
        catch e
            @printf("⚠ could not refresh web bundle (%s)\n", sprint(showerror, e))
        end
    end
end

let mode = ("--fetch" in ARGS) ? :force : ("--no-fetch" in ARGS) ? :never : :auto,
    ti = something(findfirst(a -> !startswith(a, "--"), ARGS), 0)
    show_signal(ti == 0 ? "QQQ" : uppercase(ARGS[ti]); mode = mode)
end
