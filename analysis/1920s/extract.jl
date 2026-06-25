# Extract a DJIA monthly time series from the screenshot DJIA_1920-1955.png.
#
# Method: parse the BMP, find the blue plot line in every pixel column, take the
# median y of the line in that column, and convert y -> index value with an axis
# calibration fitted to the chart's horizontal gridlines (0..600). The x axis is
# calibrated by assuming the line spans Jan-1920 (leftmost blue column) to
# Dec-1955 (rightmost), monthly. Writes:
#   djia_monthly.csv  — 432 month-end closes (the extracted series)
#   djia_daily.csv    — the monthly series linearly interpolated to business days
#                       (so the day-tuned strategy keeps its real time-horizons)
using Dates, Statistics, Printf

const DIR = @__DIR__
# Decode the PNG to a 32-bit BMP we can parse with base Julia (sips ships with macOS).
const BMP = joinpath(DIR, "DJIA.bmp")
isfile(BMP) || run(`sips -s format bmp $(joinpath(DIR,"DJIA_1920-1955.png")) --out $BMP`)
bytes = read(BMP)
off  = Int(reinterpret(Int32, bytes[11:14])[1])
w    = Int(reinterpret(Int32, bytes[19:22])[1])
hraw = Int(reinterpret(Int32, bytes[23:26])[1]); h = abs(hraw); topdown = hraw < 0
bpp  = Int(reinterpret(Int16, bytes[29:30])[1]); stride = w*(bpp÷8)

@inline function px(x, y)
    row = topdown ? y : (h-1-y)
    o = off + row*stride + x*(bpp÷8)
    (Int(bytes[o+3]), Int(bytes[o+2]), Int(bytes[o+1]))   # (R,G,B)
end
isblue(r,g,b) = b > 110 && (b-r) > 35 && (b-g) > 15

# --- axis calibration -------------------------------------------------------
# gridlines (probe): y=63->600, 196->500, 327->400, 458->300 ; least-squares fit
#   value(y) = A + B*y
gy = [63.0,196.0,327.0,458.5]; gv = [600.0,500.0,400.0,300.0]
B = sum((gy .- mean(gy)).*(gv .- mean(gv)))/sum((gy .- mean(gy)).^2)
A = mean(gv) - B*mean(gy)
value(y) = A + B*y
@printf("y->value fit: value = %.3f + %.5f*y   (check y=797 -> %.1f, y=206 -> %.1f)\n",
        A, B, value(797), value(206))

# --- extract curve value for every pixel column ----------------------------
const XL, XR = 139, 1547                  # leftmost / rightmost blue columns
function column_curve()
    V = fill(NaN, XR-XL+1)
    for (k,x) in enumerate(XL:XR)
        ys = Int[]
        for y in 0:h-1
            r,g,b = px(x,y); isblue(r,g,b) && push!(ys, y)
        end
        isempty(ys) || (V[k] = value(median(ys)))
    end
    # fill any gap columns by linear interpolation between known neighbours
    idx = findall(!isnan, V)
    for k in 1:length(V)
        if isnan(V[k])
            a = findlast(<(k), idx); bb = findfirst(>(k), idx)
            if a !== nothing && bb !== nothing
                ka, kb = idx[a], idx[bb]
                V[k] = V[ka] + (V[kb]-V[ka])*(k-ka)/(kb-ka)
            elseif a !== nothing; V[k]=V[idx[a]]
            elseif bb !== nothing; V[k]=V[idx[bb]] end
        end
    end
    return V
end
V = column_curve()                        # value at each column XL..XR
col(x) = V[clamp(round(Int,x)-XL+1, 1, length(V))]

# --- time calibration: column <-> month ------------------------------------
const NMON = 432                          # Jan-1920 .. Dec-1955 inclusive
months_per_px = (NMON-1)/(XR-XL)
# month m (0-based) sits at column:
mcol(m) = XL + m*(XR-XL)/(NMON-1)
firstdate = Date(1920,1,1)
monthdate(m) = firstdate + Month(m)
# month-end close = curve value sampled at that month's column (avg of ±1 px)
monthly = [mean(col(mcol(m)+dx) for dx in -1:1) for m in 0:NMON-1]

# diagnostics: locate the 1929 peak (max over first 60%) and the 1932 trough (global min)
ncut = round(Int, 0.62*NMON)
pk = argmax(monthly[1:ncut]); tr = argmin(monthly)
endmax = argmax(monthly)
@printf("1929 peak  : %s  value %.0f  (col %.0f)\n", monthdate(pk-1), monthly[pk], mcol(pk-1))
@printf("1932 trough: %s  value %.0f\n", monthdate(tr-1), monthly[tr])
@printf("series end : %s  value %.0f   global max %s value %.0f\n",
        monthdate(NMON-1), monthly[end], monthdate(endmax-1), monthly[endmax])
@printf("B&H peak->trough drawdown (1929->1932): %.1f%%\n", 100*(monthly[tr]/monthly[pk]-1))

# --- write monthly series ---------------------------------------------------
open(joinpath(DIR,"djia_monthly.csv"),"w") do io
    println(io, "date,close")
    for m in 0:NMON-1
        d = lastdayofmonth(monthdate(m))
        @printf(io, "%s,%.2f\n", d, monthly[m+1])
    end
end

# --- interpolate to business days -------------------------------------------
# anchor each monthly close at mid-month; linear-interp onto business days.
anchors_t = [monthdate(m) + Day(14) for m in 0:NMON-1]
anchors_v = monthly
bdays = filter(d -> dayofweek(d) <= 5, collect(Date(1920,1,2):Day(1):Date(1955,12,30)))
function interp(t)
    t <= anchors_t[1] && return anchors_v[1]
    t >= anchors_t[end] && return anchors_v[end]
    j = findlast(<=(t), anchors_t)
    t0,t1 = anchors_t[j], anchors_t[j+1]; v0,v1 = anchors_v[j], anchors_v[j+1]
    f = Dates.value(t-t0)/Dates.value(t1-t0)
    v0 + (v1-v0)*f
end
open(joinpath(DIR,"djia_daily.csv"),"w") do io
    println(io, "date,close")
    for d in bdays
        @printf(io, "%s,%.4f\n", d, interp(d))
    end
end
@printf("wrote djia_monthly.csv (%d months) and djia_daily.csv (%d business days)\n",
        NMON, length(bdays))
