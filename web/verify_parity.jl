# Full-history parity check: the web JS port (strategy.js) must reproduce the Julia
# pipeline bar-for-bar. Recomputes the merged OHLCV series, the four indicators
# (SMA-50/200, CCI-40, TMA-200) and the four position series (momentum, trend,
# either-on, avg) here, dumps the same from Node (`verify_node.js --dump`), and
# requires the two to be byte-identical. Run by the nightly workflow so any drift
# between src/{indicators,strategies}.jl and web/strategy.js fails CI.
#
#   julia --startup-file=no web/verify_parity.jl     # exits nonzero on any mismatch
include(joinpath(dirname(@__DIR__), "analysis", "QQQBacktest.jl"))
using .QQQBacktest
using Printf

d = load_ticker("QQQ"; dir=joinpath(dirname(@__DIR__), "data"))
s50 = sma(d.close, 50); s200 = sma(d.close, 200)
c40 = cci(d.high, d.low, d.close, 40); t200 = tma(d.close, 200)
mom, tr = blend_components(d)
either = blend_either_on(d); avg = blend_avg(d)

jl = [(@sprintf("%s,%.4f,%.4f,%.4f,%.4f,%.0f,%.6f,%.6f,%.6f,%.6f,%g,%g,%g,%g",
                d.date[i], d.open[i], d.high[i], d.low[i], d.close[i], d.volume[i],
                s50[i], s200[i], c40[i], t200[i], mom[i], tr[i], either[i], avg[i]))
      for i in 1:length(d)]

js = readlines(`node $(joinpath(@__DIR__, "verify_node.js")) --dump`)

bad = [i for i in 1:max(length(jl), length(js)) if get(jl, i, nothing) != get(js, i, nothing)]
if isempty(bad)
    @printf("PARITY OK — %d bars byte-identical (%s … %s: OHLCV, indicators, positions)\n",
            length(jl), d.date[1], d.date[end])
else
    @printf("PARITY FAILED — %d mismatching bar(s) of %d; first at line %d:\n",
            length(bad), max(length(jl), length(js)), bad[1])
    println("  julia: ", get(jl, bad[1], "<missing>"))
    println("  js:    ", get(js, bad[1], "<missing>"))
    exit(1)
end
