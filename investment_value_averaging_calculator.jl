# This is a value-averaging investment calculator for VOO
# Donglai Gong, 2021-08-19
#
# starting date 2021-08-19
# ETF to invest: VOO (S&P 500 index fund from Vanguard)

ticker = "VOO"
investment_initial = 3634.56; # where we are starting from
investment_annual = (100.0-9.0)*403.84 # aiming to gain 91 shares of VOO
fund_historical_performance_frac = 0.16
fund_added_performance_frac = 0.07

#ticker = "QQQ"
#investment_initial = 7277.20; # where we are starting from
#investment_annual = (100.0-20.0)*363.86 # aiming to gain 91 shares of VOO
#fund_historical_performance_frac = 0.23
#fund_added_performance_frac = 0.07

#investment_initial = 50000.0;
#investment_annual = 6000.0;

principal = investment_initial+investment_annual

trading_weeks_per_year = 52
added_performance_frac = fund_added_performance_frac

#investment_annual_boost_frac = investment_annual / investment_initial;
#investment_expected_performance_frac = fund_historical_performance_frac + investment_annual_boost_frac;

# optimistic estimation of investment_goal assuming lump sum investment of investment_annual at the beginning of year:
investment_goal = (investment_initial + investment_annual) * (1.0 + fund_historical_performance_frac);

# this is the desired interest rate on investment on a weekly basis
weekly_historical_rate = (1.0 + fund_historical_performance_frac) ^ (1/Float64(trading_weeks_per_year)) - 1.0;
weekly_boosted_rate = added_performance_frac / (Float64(trading_weeks_per_year));
weekly_rate = weekly_historical_rate + weekly_boosted_rate
#weekly_rate = (fund_historical_performance_frac + added_performance_frac) / (Float64(trading_weeks_per_year))

# calculate the investment amount and the total for each week during a year
investment_now = Array{Float64}(undef,trading_weeks_per_year+1);
investment_now[1] = investment_initial;
investment_weekly_change = Array{Float64}(undef,trading_weeks_per_year+1);
investment_weekly_change[1] = 0.0;
trading_week = collect(0:trading_weeks_per_year);

for ii = 1:trading_weeks_per_year
    investment_weekly_change[ii+1] = (investment_now[ii] * weekly_rate) + (investment_annual / trading_weeks_per_year);
    investment_now[ii+1] = investment_now[ii] + investment_weekly_change[ii+1];
end
investment_final = investment_now[end]

investment_performance = investment_final / principal

# printout of the investment strategy for value averaging
[trading_week investment_weekly_change investment_now]

