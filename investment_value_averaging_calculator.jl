# This is a value-averaging investment calculator for VOO
# Donglai Gong, 2021-08-19
#
# starting date 2021-08-19
# ETFs to invest: VOO (S&P 500 index fund from Vanguard) and QQQ

trading_periods_per_year = 52

ticker = "VOO"  #2021-08-19
investment_initial = 3637.98; # where we are starting from
investment_annual = (100.0-9.0)*405   # aiming to gain 91 shares of VOO
fund_historical_performance_frac = 0.16
fund_added_performance_frac = 0.10

# ticker = "QQQ" #2021-08-19
# investment_initial = 5461.35+7275.6; # where we are starting from
# investment_annual = (200.0-35.0)*365 # aiming to gain 91 shares of VOO
# fund_historical_performance_frac = 0.23
# fund_added_performance_frac = 0.07

# ticker = "QQQ" #hypothetical
# investment_initial = 100000; # where we are starting from
# investment_annual = 5000 # aiming to gain 91 shares of VOO
# fund_historical_performance_frac = 0.23
# fund_added_performance_frac = 0.0

principal = investment_initial+investment_annual
added_performance_frac = fund_added_performance_frac

#investment_annual_boost_frac = investment_annual / investment_initial;
#investment_expected_performance_frac = fund_historical_performance_frac + investment_annual_boost_frac;

# optimistic estimation of investment_goal assuming lump sum investment of investment_annual at the beginning of year:
investment_goal = (investment_initial + investment_annual) * (1.0 + fund_historical_performance_frac);

# this is the desired interest rate on investment on a weekly basis
historical_rate = (1.0 + fund_historical_performance_frac) ^ (1/Float64(trading_periods_per_year)) - 1.0;
boosted_rate = added_performance_frac / (Float64(trading_periods_per_year));
target_rate = historical_rate + boosted_rate
#weekly_rate = (fund_historical_performance_frac + added_performance_frac) / (Float64(trading_weeks_per_year))

# calculate the investment amount and the total for each week during a year
investment_now = Array{Float64}(undef,trading_periods_per_year+1);
investment_now[1] = investment_initial;
investment_target_change = Array{Float64}(undef,trading_periods_per_year+1);
investment_target_change[1] = 0.0;
trading_period = collect(0:trading_periods_per_year);

for ii = 1:trading_periods_per_year
    investment_target_change[ii+1] = (investment_now[ii] * target_rate) + (investment_annual / trading_periods_per_year);
    investment_now[ii+1] = investment_now[ii] + investment_target_change[ii+1];
end
investment_final = investment_now[end]

investment_performance = investment_final / principal

# printout of the investment strategy for value averaging
[trading_period round.(investment_target_change) round.(investment_now)];
