# Does avg > either-on survive realistic intra-month noise, or is it a smoothing
# artifact? The extracted series is a monthly line interpolated to business days,
# so it has almost no daily wiggle (vol ~3% vs a real ~15-20%). Here we add noise
# back as a per-month Brownian BRIDGE (pinned at each month-end so the macro path
# the chart actually shows is preserved exactly), sweep the noise level, and Monte-
# Carlo both blends. If avg's edge over either-on vanishes as vol rises, it was an
# artifact; if it persists, it's real.
using Dates, Printf, Statistics, Random
include(joinpath(dirname(@__DIR__), "QQQBacktest.jl")); using .QQQBacktest

lines = readlines(joinpath(@__DIR__,"djia_daily.csv"))[2:end]
dates = [Date(split(l,",")[1]) for l in lines]
sclose = [parse(Float64, split(l,",")[2]) for l in lines]
slog = log.(sclose)
n = length(dates)
# month segments [a,b]
function month_segments()
    segs = Tuple{Int,Int}[]; a=1
    for i in 2:n
        if (year(dates[i]),month(dates[i])) != (year(dates[i-1]),month(dates[i-1]))
            push!(segs,(a,i-1)); a=i
        end
    end
    push!(segs,(a,n)); segs
end
segs = month_segments()

# build a noisy close: smooth log-price + monthly Brownian bridge of innovation σ
function noisy_close(σ, rng)
    lg = copy(slog)
    for (a,b) in segs
        L = b-a+1; L < 2 && continue
        g = σ .* randn(rng, L); g[1]=0.0
        w = cumsum(g)
        for j in 1:L
            lg[a+j-1] += w[j] - ((j-1)/(L-1))*w[L]   # pin both ends of the month
        end
    end
    exp.(lg)
end

function run_one(close)
    d = MarketData("DJIA", dates, copy(close),copy(close),copy(close),copy(close), zeros(n))
    eo = compute_metrics(run_backtest(d, blend_either_on(d); cost=5e-4, rf_annual=0.01))
    av = compute_metrics(run_backtest(d, blend_avg(d);       cost=5e-4, rf_annual=0.01))
    (eo.cagr, eo.maxdd, eo.ntrades, av.cagr, av.maxdd, av.ntrades, eo.vol)
end

println("σ=0 baseline (the smooth series):")
b = run_one(sclose)
@printf("  either-on  CAGR %.1f%%  maxDD %.1f%%  vol %.1f%%  trades %d\n", 100b[1],100b[2],100b[7],b[3])
@printf("  avg (½)    CAGR %.1f%%  maxDD %.1f%%             trades %d\n", 100b[4],100b[5],b[6])

NS = 60
println("\nMonte Carlo, $NS seeds per noise level (mean across seeds):")
@printf("%-9s %-7s | %-22s | %-22s | %s\n","σ/day","realvol","either-on CAGR / maxDD","avg(½)   CAGR / maxDD","avg beats e-o")
for σ in (0.004, 0.008, 0.012, 0.016)
    ce=Float64[]; de=Float64[]; ca=Float64[]; da=Float64[]; vv=Float64[]; te=Float64[]; ta=Float64[]
    wr=0; wd=0
    for s in 1:NS
        rng = MersenneTwister(1000+s)
        r = run_one(noisy_close(σ, rng))
        push!(ce,r[1]);push!(de,r[2]);push!(te,r[3]);push!(ca,r[4]);push!(da,r[5]);push!(ta,r[6]);push!(vv,r[7])
        r[4] > r[1] && (wr+=1)
        r[5] > r[2] && (wd+=1)   # less-negative maxDD = shallower
    end
    @printf("%-9.3f %5.1f%%  | %+6.1f%% / %5.1f%% (tr %3.0f) | %+6.1f%% / %5.1f%% (tr %3.0f) | ret %2d/%d  dd %2d/%d\n",
        σ, 100mean(vv), 100mean(ce),100mean(de),mean(te), 100mean(ca),100mean(da),mean(ta), wr,NS, wd,NS)
end
