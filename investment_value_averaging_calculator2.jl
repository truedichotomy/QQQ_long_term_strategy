# This is a value-averaging investment calculator for VOO
# Donglai Gong, 2021-08-19
#
# starting date 2021-08-19
# ETFs to invest: VOO (S&P 500 index fund from Vanguard) and QQQ

trading_periods_per_year = 45

#=
ticker = "VOO"  #2021-08-19
share_price_initial = 405;
fund_anticipated_annual_frac = 0.35
investment_initial = 3637.98; # where we are starting from
shares_initial = 9.0;
investment_annual = (100.0-shares_initial)*share_price_initial*(1.0+fund_anticipated_annual_frac);   # aiming to gain 91 shares of VOO
=#

ticker = "VOO"  #2021-10-05
share_price_initial = 398.04;
fund_anticipated_annual_frac = 0.30
investment_initial = 14453.63; # where we are starting from
shares_initial = 36.312;
investment_annual = (100.0-shares_initial)*share_price_initial*(1.0+fund_anticipated_annual_frac);   # aiming to gain 91 shares of VOO

#=
ticker = "QQQ" #2021-08-19
share_price_initial = 365;
shares_initial = 35
fund_anticipated_annual_frac = 0.35
investment_initial = 5461.35+7275.6; # where we are starting from
investment_annual = (200.0-shares_initial)*share_price_initial*(1.0+fund_anticipated_annual_frac); # aiming to gain 91 shares of VOO
=#

#=
ticker = "QQQ" #2021-10-05
share_price_initial = 357.38;
shares_initial = 72.542
fund_anticipated_annual_frac = 0.30
investment_initial = 25925.05; # where we are starting from
investment_annual = (200.0-shares_initial)*share_price_initial*(1.0+fund_anticipated_annual_frac); # aiming to gain 91 shares of VOO
=#

#=
ticker = "QQQ" #hypothetical
share_price_initial = 373.83;
shares_initial = 10
fund_anticipated_annual_frac = 0.4
investment_initial = 3738.30; # where we are starting from
investment_annual = 6000 # 
=#
principal = investment_initial+investment_annual

# expected lump sum investment return based on historical average:
expected_investment_return = principal * (1.0 + fund_anticipated_annual_frac);

# this is the desired compound interest rate on investment on a weekly basis, 
fund_anticipated_weekly_frac = (1.0 + fund_anticipated_annual_frac) ^ (1/Float64(trading_periods_per_year)) - 1.0;

# calculate the investment amount and the total for each week during a year
investment_now = Array{Float64}(undef,trading_periods_per_year+1);
investment_now[1] = investment_initial;
investment_change = Array{Float64}(undef,trading_periods_per_year+1);
investment_change[1] = 0.0;
share_price = Array{Float64}(undef,trading_periods_per_year+1);
share_price[1] = share_price_initial;
shares_change = Array{Float64}(undef,trading_periods_per_year+1);
shares_change[1] = 0.0;
trading_period = collect(0:trading_periods_per_year);

for ii = 1:trading_periods_per_year
    investment_change[ii+1] = (investment_now[ii] * fund_anticipated_weekly_frac) + (investment_annual / trading_periods_per_year);
    investment_now[ii+1] = investment_now[ii] + investment_change[ii+1];
    share_price[ii+1] = share_price[ii] * (1.0 + fund_anticipated_weekly_frac);
    shares_change[ii+1] = investment_change[ii+1] / share_price[ii+1];
end
shares_change = investment_change ./ share_price;
shares_count = shares_initial .+ cumsum(shares_change);
investment_final = investment_now[end]

investment_performance = investment_final / principal

# printout of the investment strategy for value averaging
investtable = [trading_period round.(investment_change) round.(investment_now) share_price shares_count];
