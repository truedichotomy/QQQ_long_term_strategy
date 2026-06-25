# How long should a DCA phase-in be, if each tranche is then managed by the avg
# overlay? For every historical "your situation" entry (signal IN, price near its
# high), deploy capital in equal monthly tranches over a phase-in of P months
# (P=0 = lump sum); undeployed cash earns 4%/yr, deployed capital follows the avg
# overlay. Measure, over the 3 years from entry: the worst drawdown on the WHOLE
# portfolio (entry-risk) and the total return (the cost of phasing in slowly).
using Dates, Printf, Statistics
include(joinpath(@__DIR__, "QQQBacktest.jl")); using .QQQBacktest

const RFD = (1.04)^(1/252) - 1
cashgrow(days) = (1+RFD)^days
q(x,p) = quantile(x,p)

function study(tk; W=756, MONTH=21)
    d = load_ticker(tk; dir=joinpath(dirname(@__DIR__), "data")); n = length(d)
    eqa = run_backtest(d, blend_avg(d); cost=5e-4, rf_annual=0.04).eq
    eo  = run_backtest(d, blend_either_on(d); cost=5e-4, rf_annual=0.04)
    cmax = accumulate(max, d.close)
    Ps = [0,1,2,3,6,12]
    maxlag = maximum(Ps)*MONTH
    # identical entry set across all P: signal IN, near high, room for phase-in + 3yr window
    entries = [i for i in 1:n if eo.pos[i]==1 && d.close[i] >= 0.95*cmax[i] && i + W <= n]
    # portfolio value path from entry t0 over the next W days, phasing in over P months
    function pv_path(t0, P)
        k = P + 1                                   # tranches at t0, t0+21, ..., t0+P*21
        S = [t0 + m*MONTH for m in 0:P]
        pv = Vector{Float64}(undef, W+1)
        for off in 0:W
            i = t0 + off; acc = 0.0
            for s in S
                acc += (1/k) * (i < s ? cashgrow(i-t0) : cashgrow(s-t0) * eqa[i]/eqa[s])
            end
            pv[off+1] = acc
        end
        pv
    end
    @printf("\n%s — %d near-high, signal-IN entries; 3-yr window per entry\n", tk, length(entries))
    @printf("%-12s %14s %14s %16s\n","phase-in","worst dd p05","worst dd abs","3-yr return med")
    for P in Ps
        dds=Float64[]; rets=Float64[]
        for t0 in entries
            pv = pv_path(t0, P)
            push!(dds, max_drawdown(pv))
            push!(rets, pv[end]/pv[1]-1)
        end
        label = P==0 ? "lump sum" : "$(P) mo"
        @printf("%-12s %13.0f%% %13.0f%% %15.0f%%\n", label, 100q(dds,0.05), 100minimum(dds), 100median(rets))
    end
end
study("QQQ"); study("NDX")
