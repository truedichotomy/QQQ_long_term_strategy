# When the QQQ either-on overlay is OUT (in cash dodging a bear), what else was
# going up? Find every out-spell of the adopted overlay, then measure the realized
# return of candidate "safe harbor" assets over exactly those windows.
using Dates, Printf, Statistics
include(joinpath(@__DIR__, "QQQBacktest.jl")); using .QQQBacktest

const DATADIR = joinpath(dirname(@__DIR__), "data")
q = load_ticker("QQQ"; dir=DATADIR)
pos = run_backtest(q, blend_either_on(q); cost=5e-4, rf_annual=0.04).pos

# contiguous out-spells (pos==0), keep the meaningful ones (>= MINLEN trading days)
const MINLEN = 20
spells = Tuple{Int,Int}[]
let i=1, n=length(pos)
    while i<=n
        if pos[i]==0
            j=i; while j<n && pos[j+1]==0; j+=1; end
            (j-i+1) >= MINLEN && push!(spells,(i,j))
            i=j+1
        else; i+=1; end
    end
end

# alt assets + an "as-of" close lookup (last available close <= target date)
alts = ["TLT"=>"20y Treasuries","GLD"=>"gold","TIP"=>"TIPS","XLE"=>"energy",
        "SPY"=>"S&P500","IWM"=>"small-caps"]
data = Dict(t=>load_ticker(t; dir=DATADIR) for (t,_) in alts)
function asof(d, t)
    k = searchsortedlast(d.date, t)
    k==0 ? NaN : d.close[k]
end
spanret(d, t0, t1) = (c0=asof(d,t0); c1=asof(d,t1); (isnan(c0)||c0==0 || d.date[1]>t0) ? NaN : c1/c0-1)
cashret(t0,t1) = (1.04)^(Dates.value(t1-t0)/365.25) - 1

println("QQQ either-on OUT-spells (≥ $MINLEN trading days) — return of each alt over the same window:")
@printf("%-23s %4s %7s | %6s %7s %7s %7s %7s %7s %7s\n",
        "out window","days","QQQ","cash","TLT","GLD","TIP","XLE","SPY","IWM")
agg = Dict(t=>Float64[] for (t,_) in alts); aggc=Float64[]; aggq=Float64[]
for (i,j) in spells
    t0,t1 = q.date[i], q.date[j]; dd=j-i+1
    qr = q.close[j]/q.close[i]-1
    fmt(x) = isnan(x) ? "   –  " : @sprintf("%+5.0f%%",100x)
    rets = Dict(t=>spanret(data[t],t0,t1) for (t,_) in alts)
    @printf("%-23s %4d %+6.0f%% | %+5.0f%% %s %s %s %s %s %s\n",
        string(t0)*"→"*string(t1)[3:end], dd, 100qr, 100cashret(t0,t1),
        fmt(rets["TLT"]),fmt(rets["GLD"]),fmt(rets["TIP"]),fmt(rets["XLE"]),fmt(rets["SPY"]),fmt(rets["IWM"]))
    for (t,_) in alts; r=rets[t]; !isnan(r) && push!(agg[t],r); end
    push!(aggc, cashret(t0,t1)); push!(aggq, qr)
end

println("\nAcross all covered out-spells — median return / % of spells positive / compounded if parked there:")
@printf("%-18s %10s %10s %12s\n","asset","median","% positive","compounded")
function rowstat(name, v)
    isempty(v) && return
    comp = prod(1 .+ v)-1
    @printf("%-18s %9.1f%% %9.0f%% %11.1f%%\n", name, 100median(v), 100mean(v.>0), 100comp)
end
rowstat("cash (4%/yr)", aggc)
for (t,desc) in alts; rowstat("$t ($desc)", agg[t]); end
@printf("%-18s %9.1f%% %9.0f%%\n","QQQ (what you dodged)", 100median(aggq), 100mean(aggq.>0))
