# This is a value-averaging investment calculator for VOO
# Donglai Gong, 2021-08-19
#
# starting date 2021-08-19
# ETFs to invest: VOO (S&P 500 index fund from Vanguard) and QQQ

trading_periods_per_year = 52

ticker = "VOO"  #2021-08-19
share_price_initial = 405;
fund_historical_performance_frac = 0.15
    fund_target_performance_frac = 0.25
    fund_added_performance_frac = fund_target_performance_frac - fund_historical_performance_frac
investment_initial = 3637.98; # where we are starting from
investment_annual = (100.0-9.0)*share_price_initial*(1.0+fund_historical_performance_frac);   # aiming to gain 91 shares of VOO

ticker = "QQQ" #2021-08-19
share_price_initial = 365;
fund_historical_performance_frac = 0.21
    fund_target_performance_frac = 0.35
    fund_added_performance_frac = fund_target_performance_frac - fund_historical_performance_frac
investment_initial = 5461.35+7275.6; # where we are starting from
investment_annual = (200.0-35.0)*share_price_initial*(1.0+fund_historical_performance_frac); # aiming to gain 91 shares of VOO

ticker = "QQQ" #hypothetical
fund_historical_performance_frac = 0.21
    fund_target_performance_frac = fund_historical_performance_frac+0.1
    fund_added_performance_frac = fund_target_performance_frac - fund_historical_performance_frac
investment_initial = 100000; # where we are starting from
investment_annual = 0 # 

principal = investment_initial+investment_annual

#investment_annual_boost_frac = investment_annual / investment_initial;
#investment_expected_performance_frac = fund_historical_performance_frac + investment_annual_boost_frac;

# expected lump sum investment return based on historical average:
expected_investment_return = principal * (1.0 + fund_historical_performance_frac);

# this is the desired compound interest rate on investment on a weekly basis, 
historical_rate = (1.0 + fund_historical_performance_frac) ^ (1/Float64(trading_periods_per_year)) - 1.0;
#boosted_rate = fund_added_performance_frac / (Float64(trading_periods_per_year));
boosted_rate = (1.0 + fund_added_performance_frac) ^ (1/Float64(trading_periods_per_year)) - 1.0
target_rate = historical_rate + boosted_rate
target_rate2 = (1.0 + fund_target_performance_frac) ^ (1/Float64(trading_periods_per_year)) - 1.0
#weekly_rate = (fund_historical_performance_frac + fund_added_performance_frac) / (Float64(trading_weeks_per_year))

# calculate the investment amount and the total for each week during a year
investment_now = Array{Float64}(undef,trading_periods_per_year+1);
investment_now[1] = investment_initial;
investment_target_change = Array{Float64}(undef,trading_periods_per_year+1);
investment_target_change[1] = 0.0;
share_price = Array{Float64}(undef,trading_periods_per_year+1);
share_price[1] = share_price_initial;
trading_period = collect(0:trading_periods_per_year);

for ii = 1:trading_periods_per_year
    investment_target_change[ii+1] = (investment_now[ii] * target_rate) + (investment_annual / trading_periods_per_year);
    investment_now[ii+1] = investment_now[ii] + investment_target_change[ii+1];
    share_price[ii+1] = share_price[ii] * (1.0 + target_rate);
end
investment_final = investment_now[end]

investment_performance = investment_final / principal

# printout of the investment strategy for value averaging
[trading_period round.(investment_target_change) round.(investment_now) share_price];
