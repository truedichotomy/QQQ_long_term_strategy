# Can short-term interest rates improve the QQQ blend? An exploratory test of rate-based
# signals. QQQ's 27 years hold only a handful of rate cycles, so every idea is also run on
# the Nasdaq-100 (1985–) and S&P 500 (1970–) price indices — the 1970s inflation, Volcker,
# 1994 and 2022 are where "rising rates hurt stocks" should show up if it is real.
#
#   A. Do stocks and T-bill yields move in OPPOSITE directions? Correlation of index returns
#      with yield changes over the same quarter, by decade.
#   B. Do yield moves PREDICT the next 6 months? Forward returns by the 6-month bill trend,
#      for all months and for months the either-on blend is already long.
#   C. Rate overlays on the adopted either-on blend: exit when bills rose fast ("don't fight
#      the Fed"), exit after emergency cuts, exit while the curve is inverted (10y < 3m),
#      and re-enter early on aggressive easing.
#   D. Absolute (time-series) momentum with a T-bill hurdle vs a zero hurdle.
#
# Cash earns the 3-month T-bill throughout (engine default).
#
#   julia --startup-file=no analysis/tests/rate_signals.jl

include(joinpath(dirname(@__DIR__), "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const DATADIR = joinpath(dirname(dirname(@__DIR__)), "data")
const TB  = tbill()
const TNX = load_rate(TNX_FILE, "10Y T-note"; dir=DATADIR)
const MKTS = [(tk, load_ticker(tk; dir=DATADIR)) for tk in ("QQQ", "NDX", "SPX")]
rule(c='═', w=104) = println(c^w)

# yield change over the past k trading days (0 until k days of history exist)
chg(y, k) = [i > k ? y[i] - y[i-k] : 0.0 for i in eachindex(y)]

# ─────────────────────────────────────────────────────────────────────────────────────────────
rule(); println("A. SAME-QUARTER CO-MOVEMENT — correlation of index return with the change in the bill yield"); rule()
println("(non-overlapping 63-day quarters; negative = stocks fall when bill yields rise)")
decs = [(1970, 1979), (1980, 1989), (1990, 1999), (2000, 2009), (2010, 2019), (2020, 2026), (1970, 2026)]
@printf("%-8s", "market"); for (a, b) in decs; @printf("%13s", b - a > 9 ? "ALL" : "$(a)s"); end; println(); println("-"^104)
for (tk, d) in MKTS
    y = rate_on(TB, d.date); @printf("%-8s", tk)
    for (a, b) in decs
        idx = [i for i in 64:63:length(d) if a <= year(d.date[i]) <= b]
        if length(idx) < 12; @printf("%13s", "–"); continue; end
        r = [d.close[i] / d.close[i-63] - 1 for i in idx]; dy = [y[i] - y[i-63] for i in idx]
        @printf("%13s", @sprintf("%+.2f (n=%d)", cor(r, dy), length(idx)))
    end
    println()
end

# ─────────────────────────────────────────────────────────────────────────────────────────────
println(); rule(); println("B. DO BILL MOVES PREDICT? — next-6-month return by the PAST 6-month change in the bill yield"); rule()
println("(sampled monthly; forward windows overlap, so counts overstate independence)")
bands = [("bills fell > 1pp", -Inf, -0.01), ("fell 0.25–1pp", -0.01, -0.0025), ("flat ±0.25pp", -0.0025, 0.0025),
         ("rose 0.25–1pp", 0.0025, 0.01), ("rose > 1pp", 0.01, Inf)]
for (tk, d) in MKTS
    y = rate_on(TB, d.date); d6 = chg(y, 126); n = length(d)
    eo = blend_either_on(d)
    println("\n", tk, "  ", d.date[1], " … ", d.date[end])
    @printf("  %-18s %20s %26s\n", "past-6m bill move", "all months", "months either-on is long")
    for (lbl, lo, hi) in bands
        idx = [i for i in 127:21:n-126 if lo <= d6[i] < hi]
        il  = filter(i -> eo[i] == 1, idx)
        f(v) = isempty(v) ? "–" : @sprintf("%+5.1f%% (%2.0f%% up, n=%3d)",
                   100mean(d.close[i+126] / d.close[i] - 1 for i in v), 100mean(d.close[i+126] > d.close[i] for i in v), length(v))
        @printf("  %-18s %22s %26s\n", lbl, f(idx), f(il))
    end
end

# ─────────────────────────────────────────────────────────────────────────────────────────────
println(); rule(); println("C. RATE OVERLAYS ON THE EITHER-ON BLEND — vs the plain blend (cash = T-bill)"); rule()
function overlays(d)
    y = rate_on(TB, d.date); s = rate_on(TNX, d.date) .- y
    d6, d3 = chg(y, 126), chg(y, 63); eo = blend_either_on(d)
    gate(ok) = eo .* ok
    return [("either-on (base)",                eo),
            ("exit if bills +0.5pp in 6m",      gate(d6 .<= 0.005)),
            ("exit if bills +1pp in 6m",        gate(d6 .<= 0.01)),
            ("exit if bills +2pp in 6m",        gate(d6 .<= 0.02)),
            ("exit after cuts −0.5pp in 3m",    gate(d3 .>= -0.005)),
            ("exit after cuts −1pp in 3m",      gate(d3 .>= -0.01)),
            ("exit while curve inverted",       gate(s .>= 0)),
            ("re-enter on easing −1pp in 6m",   max.(eo, Float64.(d6 .< -0.01)))]
end
for (tk, d) in MKTS
    rows = overlays(d); base = compute_metrics(run_backtest(d, rows[1][2]))
    println("\n", tk, "  ", d.date[1], " … ", d.date[end], "   buy & hold CAGR ",
            @sprintf("%.1f%%", 100compute_metrics(run_backtest(d, buyhold(d))).cagr))
    @printf("  %-32s %7s %7s %7s %7s %6s %7s %13s\n", "rule", "CAGR", "maxDD", "Sharpe", "Calmar", "%in", "trades", "ΔCAGR/ΔDD")
    for (nm, sig) in rows
        m = compute_metrics(run_backtest(d, sig))
        @printf("  %-32s %6.2f%% %6.1f%% %7.2f %7.2f %5.0f%% %7d %13s\n", nm, 100m.cagr, 100m.maxdd, m.sharpe,
                m.calmar, 100m.pct_invested, m.ntrades,
                nm == rows[1][1] ? "" : @sprintf("%+.2f / %+.1f", 100(m.cagr - base.cagr), 100(m.maxdd - base.maxdd)))
    end
end

# ─────────────────────────────────────────────────────────────────────────────────────────────
println(); rule(); println("D. ABSOLUTE MOMENTUM — long if the trailing 12-month return beats a hurdle: 0% vs T-bills"); rule()
@printf("%-8s %-24s %7s %7s %7s %6s %7s\n", "market", "hurdle", "CAGR", "maxDD", "Sharpe", "%in", "trades")
println("-"^104)
for (tk, d) in MKTS
    y = rate_on(TB, d.date); n = length(d)
    cash = cumprod([1.0; [(1 + y[i-1])^(1/252) for i in 2:n]])        # T-bill account
    r12(i) = d.close[i] / d.close[i-252] - 1
    for (lbl, hurdle) in (("12m return > 0", i -> 0.0), ("12m return > 12m T-bill", i -> cash[i] / cash[i-252] - 1))
        sig = [i > 252 && r12(i) > hurdle(i) ? 1.0 : 0.0 for i in 1:n]
        m = compute_metrics(run_backtest(d, sig))
        @printf("%-8s %-24s %6.2f%% %6.1f%% %7.2f %5.0f%% %7d\n", tk, lbl, 100m.cagr, 100m.maxdd, m.sharpe, 100m.pct_invested, m.ntrades)
    end
end

# ─────────────────────────────────────────────────────────────────────────────────────────────
println(); rule(); println("E. STRESS TEST of the one rule that helped everywhere — exit when bills rose > X over the past L days"); rule()
println("Δ Calmar vs the plain either-on blend (ΔCAGR pp in brackets); a robust effect is a broad plateau, not one cell")
THR = (0.005, 0.0075, 0.01, 0.0125, 0.015, 0.02); LB = (63, 126, 189, 252)
for (tk, d) in MKTS
    y = rate_on(TB, d.date); eo = blend_either_on(d); b = compute_metrics(run_backtest(d, eo))
    println("\n", tk, "   rise X →", join([@sprintf("%15s", @sprintf("+%.2fpp", 100x)) for x in THR]))
    for L in LB
        dL = chg(y, L); @printf("  over %3dd    ", L)
        for x in THR
            m = compute_metrics(run_backtest(d, eo .* (dL .<= x)))
            @printf("%15s", @sprintf("%+.2f [%+.1f]", m.calmar - b.calmar, 100(m.cagr - b.cagr)))
        end
        println()
    end
end

println("\nSplit halves — exit if bills +1pp in 6m vs plain either-on  (CAGR / maxDD / Calmar)")
for (tk, d) in MKTS
    y = rate_on(TB, d.date); eo = blend_either_on(d); v = eo .* (chg(y, 126) .<= 0.01)
    mid = d.date[1] + Day(round(Int, Dates.value(d.date[end] - d.date[1]) / 2))
    for (lo, hi) in ((d.date[1], mid), (mid, d.date[end]))
        a, z = date_range(d, lo, hi)
        mb = compute_metrics(run_backtest(subset(d, a, z), eo[a:z])); mv = compute_metrics(run_backtest(subset(d, a, z), v[a:z]))
        @printf("  %-4s %s … %s   base %5.1f%% / %4.0f%% / %.2f   veto %5.1f%% / %4.0f%% / %.2f\n", tk, d.date[a], d.date[z],
                100mb.cagr, 100mb.maxdd, mb.calmar, 100mv.cagr, 100mv.maxdd, mv.calmar)
    end
end

println("\nQQQ episodes where the veto pulled the blend out (≥ 10 days) — QQQ's move while sidelined:")
let (tk, d) = MKTS[1], y = rate_on(TB, d.date), eo = blend_either_on(d), off = (eo .== 1) .& (chg(y, 126) .> 0.01), i = 1, n = length(d)
    while i <= n
        if off[i]
            j = i; while j < n && off[j+1]; j += 1; end
            j - i + 1 >= 10 && @printf("  %s → %s  %3d days   QQQ %+6.1f%%   bills %.2f%% → %.2f%%\n",
                                      d.date[i], d.date[j], j - i + 1, 100(d.close[j] / d.close[i] - 1), 100y[i], 100y[j])
            i = j + 1
        else
            i += 1
        end
    end
end
