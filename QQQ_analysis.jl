# algorithm to test: 
#T= -X/(X+1) where X is the fraction change in the stock each day and T is the fraction of the current value to buy or sell.

using CSV, Dates, DataFrames, Statistics, Plots

datapath = "QQQ_2000-2024.csv";
t0 = Dates.Date(2010,5,1);
tN = Dates.Date(2020,5,1);
P0 = 100000;

findata = CSV.read(datapath, DataFrame);
t = collect(findata.Date);
pps = collect(findata.Close); # price per share
vol = collect(findata.Volume); # volume
dpps = pps[2:end] - pps[1:end-1]; # price change from day to day

ind0 = findmin(abs.(t-t0))[2];
indN = findmin(abs.(t-tN))[2];

V = Array{Float64}(undef, size(t[ind0:indN]));
P = Array{Float64}(undef, size(t[ind0:indN])); 
E = Array{Float64}(undef, size(t[ind0:indN])); 
BH = Array{Float64}(undef, size(t[ind0:indN])); 

V[1] = P0;
P[1] = P0;
E[1] = 0.0;
BH[1] = P0;

X = dpps[ind0:indN-1] ./ pps[ind0:indN-1];
T = -X ./ (X .+ 1);

for ii = 1:(length(pps[ind0:indN])-1)
    V[ii+1] = V[ii] * (1 + T[ii]) * (1 + X[ii]);
    E[ii+1] = V[ii] * (1 + T[ii]) - V[ii]; 
    P[ii+1] = P[ii] + V[ii] * T[ii];

    BH[ii+1] = BH[ii] * (1 + X[ii]);
end

#V[end] + cumsum(E)[end]
plot(log10.(BH))
BH[end]