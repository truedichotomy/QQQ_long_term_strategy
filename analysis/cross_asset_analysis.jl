# Does information from the OTHER ETFs improve QQQ timing?
#
# Base = the QQQ-only flagship (50/200 SMA golden cross). We gate it with
# cross-asset signals (broad-market regime from SPY/DIA/IWM, QQQ-vs-SPY relative
# strength, risk-on/off vs TLT) and ask whether any of them beats the base on
# CAGR while keeping drawdown no worse. We also validate the 50/200 filter on all
# eight ETFs to confirm the effect is general, not a QQQ artifact.
#
#   julia analysis/cross_asset_analysis.jl

include(joinpath(@__DIR__, "QQQBacktest.jl"))
using .QQQBacktest
using Printf, Statistics, Dates

const COST, RF = 5e-4, 0.04
const DATADIR = joinpath(dirname(@__DIR__), "data")
const OUTDIR  = joinpath(@__DIR__, "results")
bt(d, sig) = run_backtest(d, sig; cost=COST, rf_annual=RF)

d   = load_ticker("QQQ"; dir=DATADIR)
spy = load_ticker("SPY"; dir=DATADIR)
dia = load_ticker("DIA"; dir=DATADIR)
iwm = load_ticker("IWM"; dir=DATADIR)
tlt = load_ticker("TLT"; dir=DATADIR)

qc   = d.close
spyc = align_close(d, spy)
diac = align_close(d, dia)
iwmc = align_close(d, iwm)
tltc = align_close(d, tlt)

base = sma_cross(d; fast=50, slow=200)   # QQQ-only flagship

candidates = Tuple{String,Vector{Float64}}[
    ("buy & hold QQQ",          buyhold(d)),
    ("QQQ 50/200 (base)",       base),
    ("base & SPY>SMA200",       gate_and(base, above_own_sma(spyc, 200))),
    ("base & SPY 50/200",       gate_and(base, cross_own(spyc, 50, 200))),
    ("base | SPY 50/200",       gate_or(base,  cross_own(spyc, 50, 200))),
    ("base & QQQ>SPY RS100",    gate_and(base, rel_strength(qc, spyc, 100))),
    ("base & QQQ>SPY RS50",     gate_and(base, rel_strength(qc, spyc, 50))),
    ("base & DIA>SMA200",       gate_and(base, above_own_sma(diac, 200))),
    ("base & IWM>SMA200",       gate_and(base, above_own_sma(iwmc, 200))),
    ("base & risk-on vs TLT63", gate_and(base, risk_on(qc, tltc, 63))),
    ("SPY 50/200 → QQQ",        cross_own(spyc, 50, 200)),
    ("QQQ>SPY RS100 only",      rel_strength(qc, spyc, 100)),
]

results = [(name, bt(d, sig)) for (name, sig) in candidates]
bh_b = results[1][2]

# full-period and modern (2005+, all informers live) sub-period stats
function sub(b, i0, i1)
    es = b.eq[i0:i1] ./ b.eq[i0]
    yrs = max(Dates.value(d.date[i1] - d.date[i0]) / 365.25, 1e-9)
    return (cagr = es[end]^(1 / yrs) - 1, maxdd = max_drawdown(es), tot = es[end])
end
m0, m1 = date_range(d, Date(2005, 1, 1), d.date[end])
win1y(b) = (s = rolling_compare(b.eq, bh_b.eq, 252; step=21); (s.return_win_rate, s.dd_win_rate))

@printf("QQQ cross-asset study  (%s … %s, cash=%.0f%%/yr, cost=%.0f bps)\n\n",
        d.date[1], d.date[end], 100RF, 1e4COST)
@printf("%-24s | %-19s | %-19s | %s\n", "", "FULL 1999–2026", "MODERN 2005–2026", "vs QQQ B&H (1yr win)")
@printf("%-24s | %8s %8s | %8s %8s | %6s %6s\n", "strategy", "CAGR", "maxDD", "CAGR", "maxDD", "ret%", "dd%")
println("-"^96)
for (name, b) in results
    f = sub(b, 1, length(d)); md = sub(b, m0, m1)
    rw, dw = name == "buy & hold QQQ" ? (0.5, 1.0) : win1y(b)
    @printf("%-24s | %7.2f%% %7.1f%% | %7.2f%% %7.1f%% | %5.0f%% %5.0f%%\n",
            name, 100f.cagr, 100f.maxdd, 100md.cagr, 100md.maxdd, 100rw, 100dw)
end

# ----------------------------------------------------------------------------
# Generality check: 50/200 golden cross on every ETF vs its own buy & hold.
# ----------------------------------------------------------------------------
println("\n50/200 golden-cross filter across ETFs (each vs its own buy & hold):")
@printf("%-5s | %-19s | %-19s | %s\n", "ETF", "buy & hold", "50/200 filter", "filter edge")
@printf("%-5s | %8s %8s | %8s %8s | %8s %8s\n", "", "CAGR", "maxDD", "CAGR", "maxDD", "ΔCAGR", "ΔmaxDD")
println("-"^82)
for t in ("QQQ", "SPY", "DIA", "IWM", "XLE", "TLT", "GLD", "TIP")
    et = load_ticker(t; dir=DATADIR)
    bh = run_backtest(et, buyhold(et); cost=COST, rf_annual=RF)
    fl = run_backtest(et, sma_cross(et; fast=50, slow=200); cost=COST, rf_annual=RF)
    mb = compute_metrics(bh); mf = compute_metrics(fl)
    @printf("%-5s | %7.2f%% %7.1f%% | %7.2f%% %7.1f%% | %+7.2fpp %+6.1fpp\n",
            t, 100mb.cagr, 100mb.maxdd, 100mf.cagr, 100mf.maxdd,
            100(mf.cagr - mb.cagr), 100(mf.maxdd - mb.maxdd))
end

# save the cross-asset comparison
mkpath(OUTDIR)
open(joinpath(OUTDIR, "cross_asset.csv"), "w") do io
    println(io, "strategy,full_cagr,full_maxdd,modern_cagr,modern_maxdd,ret_win_1y,dd_win_1y")
    for (name, b) in results
        f = sub(b, 1, length(d)); md = sub(b, m0, m1)
        rw, dw = name == "buy & hold QQQ" ? (0.5, 1.0) : win1y(b)
        @printf(io, "%s,%.6f,%.6f,%.6f,%.6f,%.4f,%.4f\n",
                name, f.cagr, f.maxdd, md.cagr, md.maxdd, rw, dw)
    end
end
println("\nWrote ", joinpath(OUTDIR, "cross_asset.csv"))
