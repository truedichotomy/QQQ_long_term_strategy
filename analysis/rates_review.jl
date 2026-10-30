# Rate-aware review of the QQQ blend strategies.
#
# Every earlier evaluation credited cash a FLAT 4%/yr and used 4% as the Sharpe hurdle. Real
# short-term rates swung from ~6% (2000) to ~0% (2009–15, 2020–21) to ~5% (2023–24), and the
# strategies sit in cash at very particular times (crashes — which is exactly when the Fed
# cuts). This re-runs the evaluation with cash earning the actual daily 13-week T-bill yield
# (`load_tbill`, ^IRX ≈ FRED DTB3) and the same yield as the risk-free hurdle, alongside the old
# flat-4% and a no-interest (0%) case so the effect of the assumption is explicit.
#
#   julia --startup-file=no analysis/rates_review.jl

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST = 5e-4
const DATADIR = joinpath(dirname(@__DIR__), "data")

d  = load_ticker("QQQ"; dir=DATADIR)
TB = load_tbill(dir=DATADIR)
yld = rate_on(TB, d.date)                       # annualized T-bill in effect on each QQQ date
n = length(d)

mom, trend = blend_components(d)
NAMES = ["buy & hold", "trend (SMA 50/200)", "momentum (CCI40)", "either-on ★", "avg ½-size"]
SIGS  = [buyhold(d), trend, mom, blend_either_on(d), blend_avg(d)]
bt(sig, rf) = run_backtest(d, sig; cost=COST, rf_annual=rf)
ev(sig, a, b, rf) = compute_metrics(run_backtest(subset(d, a, b), sig[a:b]; cost=COST, rf_annual=rf))
win(f, t) = date_range(d, f, t)
pct(x) = @sprintf("%.1f%%", 100x)
rule(c='═', w=100) = println(c^w)

BT = [bt(s, TB) for s in SIGS]                  # T-bill accounting (the new default view)
MT = [compute_metrics(b) for b in BT]

println("QQQ ", d.date[1], " … ", d.date[end], "  ·  cash earns the 13-week T-bill (^IRX), ",
        "5 bps/trade, 1-day signal lag")
@printf("T-bill over this span: average %.2f%%, low %.2f%%, high %.2f%%; today %.2f%%\n\n",
        100mean(yld), 100minimum(yld), 100maximum(yld), 100yld[end])

# ─────────────────────────────────────────────────────────────────────────────────────────────
rule(); println("1. FULL HISTORY — how much the cash assumption matters"); rule()
@printf("%-22s %7s %10s %10s %10s %11s %16s\n", "strategy", "in mkt", "CAGR @0%", "@flat 4%",
        "@T-bill", "cash adds", "edge vs B&H 4%→TB")
println("-"^100)
c0 = [compute_metrics(bt(s, 0.0)).cagr for s in SIGS]
c4 = [compute_metrics(bt(s, 0.04)).cagr for s in SIGS]
ct = [m.cagr for m in MT]
for k in eachindex(SIGS)
    edge = k == 1 ? "—" : @sprintf("%+.2f → %+.2f pp", 100(c4[k] - c4[1]), 100(ct[k] - ct[1]))
    @printf("%-22s %7s %9.2f%% %9.2f%% %9.2f%% %+9.2fpp %18s\n", NAMES[k], pct(MT[k].pct_invested),
            100c0[k], 100c4[k], 100ct[k], 100(ct[k] - c0[k]), edge)
end
println("\nFull metrics with T-bill cash (Sharpe/Sortino = excess over the day's T-bill yield):")
println(METRIC_HEADER); println("-"^100)
for k in eachindex(SIGS); println(metric_row(NAMES[k], MT[k])); end
println("\nSharpe, old flat-4% hurdle → T-bill hurdle:")
for k in eachindex(SIGS)
    @printf("  %-22s %5.2f → %5.2f\n", NAMES[k], compute_metrics(bt(SIGS[k], 0.04)).sharpe, MT[k].sharpe)
end

# ─────────────────────────────────────────────────────────────────────────────────────────────
println(); rule(); println("2. WHEN IS EACH STRATEGY IN CASH — and what did cash pay then?"); rule()
@printf("%-22s %14s %18s %18s\n", "strategy", "years in cash", "avg T-bill earned", "vs span average")
println("-"^100)
for k in 2:length(SIGS)
    w = 1 .- BT[k].pos[2:n]; y = yld[1:n-1]               # cash weight × yield in effect
    yrs = sum(w) / 252; ye = sum(w .* y) / max(sum(w), eps())
    @printf("%-22s %14.1f %17.2f%% %+17.2fpp\n", NAMES[k], yrs, 100ye, 100(ye - mean(y)))
end
println("(Positive = the strategy tends to be out when bills pay MORE than average.)")

# ─────────────────────────────────────────────────────────────────────────────────────────────
println(); rule(); println("3. BY ERA — T-bill accounting  (CAGR / maxDD / Sharpe)"); rule()
eras = [("1999–2009 lost decade", Date(1999,3,10), Date(2009,12,31)),
        ("2010–2019 ZIRP & QE",   Date(2010,1,1),  Date(2019,12,31)),
        ("2020–2021 COVID ZIRP",  Date(2020,1,1),  Date(2021,12,31)),
        ("2022–now  rates 0→5→4%", Date(2022,1,1), d.date[end]),
        ("2004–now  ex dot-com",  Date(2004,3,15), d.date[end])]
SHOW = [1, 4, 5]
@printf("%-24s %7s", "era", "T-bill"); for k in SHOW; @printf("%23s", NAMES[k]); end; println(); println("-"^100)
for (lbl, f, t) in eras
    a, b = win(f, t)
    @printf("%-24s %6.2f%%", lbl, 100mean(yld[a:b]))
    for k in SHOW
        m = ev(SIGS[k], a, b, TB)
        @printf("%23s", @sprintf("%5.1f%% /%4.0f%% / %.2f", 100m.cagr, 100m.maxdd, m.sharpe))
    end
    println()
end

# ─────────────────────────────────────────────────────────────────────────────────────────────
println(); rule(); println("4. BY RATE REGIME — annualized return on the days the bill yield was in each band"); rule()
bands = [("bills < 1%  (ZIRP)", 0.0, 0.01), ("bills 1–3%", 0.01, 0.03), ("bills ≥ 3%", 0.03, Inf)]
@printf("%-20s %8s", "regime", "share"); for k in SHOW; @printf("%22s", NAMES[k]); end; println(); println("-"^100)
for (lbl, lo, hi) in bands
    idx = [i for i in 2:n if lo <= yld[i-1] < hi]
    @printf("%-20s %7.0f%%", lbl, 100length(idx) / (n - 1))
    for k in SHOW
        eq = BT[k].eq
        ann = exp(sum(log(eq[i] / eq[i-1]) for i in idx) * 252 / length(idx)) - 1
        @printf("%22s", @sprintf("%+6.1f%%  (%3.0f%% in)", 100ann, 100mean(BT[k].pos[idx])))
    end
    println()
end

# ─────────────────────────────────────────────────────────────────────────────────────────────
println(); rule(); println("5. ROBUSTNESS — % of rolling windows beating B&H on return (flat 4% → T-bill) and on drawdown"); rule()
eqb4 = bt(SIGS[1], 0.04).eq; eqbt = BT[1].eq
@printf("%-8s", "window")
for k in (4, 5); @printf("%30s%18s", NAMES[k] * " return", "shallower DD"); end; println(); println("-"^100)
ms4 = Dict(k => Dict(multiscale(bt(SIGS[k], 0.04).eq, eqb4)) for k in (4, 5))
mst = Dict(k => Dict(multiscale(BT[k].eq, eqbt)) for k in (4, 5))
for lbl in ("1yr", "3yr", "5yr", "10yr")
    @printf("%-8s", lbl)
    for k in (4, 5)
        @printf("%30s%18s", @sprintf("%3.0f%% → %3.0f%%", 100ms4[k][lbl].return_win_rate, 100mst[k][lbl].return_win_rate),
                @sprintf("%3.0f%%", 100mst[k][lbl].dd_win_rate))
    end
    println()
end

# ─────────────────────────────────────────────────────────────────────────────────────────────
println(); rule(); println("6. RECENT — T-bill accounting  (total return / maxDD over each window)"); rule()
recent = [("since 2026-06-25 review", Date(2026,6,25)), ("2026 YTD", Date(2025,12,31)),
          ("trailing 12 mo", d.date[end] - Year(1)), ("trailing 3 yr", d.date[end] - Year(3)),
          ("trailing 5 yr", d.date[end] - Year(5))]
@printf("%-26s", "window"); for k in SHOW; @printf("%22s", NAMES[k]); end; println(); println("-"^100)
for (lbl, f) in recent
    a, b = win(f, d.date[end])
    @printf("%-26s", lbl)
    for k in SHOW
        m = ev(SIGS[k], a, b, TB)
        @printf("%22s", @sprintf("%+6.1f%% / %4.1f%%", 100m.total_return, 100m.maxdd))
    end
    println()
end

lc(s) = (x = 1; for i in 2:n; s[i] != s[i-1] && (x = i); end; d.date[x])
println("\nNow (", d.date[end], "): trend ", trend[n] == 1 ? "IN" : "OUT", " since ", lc(trend),
        " · momentum ", mom[n] == 1 ? "IN" : "OUT", " since ", lc(mom),
        " → either-on ", SIGS[4][n] == 1 ? "100% QQQ" : "cash", ", avg ", round(Int, 100SIGS[5][n]), "% QQQ")
@printf("T-bill %.2f%% — the avg blend's cash half is currently earning ~%.1f%%/yr on the whole portfolio.\n",
        100yld[end], 100(1 - SIGS[5][n]) * yld[end])
