"""
We implement ConstantTime, TwoTime and FixedDataTwoTime (see abstracttypes.jl)

ConstantTime is used when getting the value from a constant parameter
Then the time does not matter (our framework is built around getting 
values from time series data)

TwoTime has datatime and scenariotime where both of them are iterated 
through the horizon. Used when the power system and weather scenarios 
change throughout the horizon.

FixedDataTwoTime has datatime and scenariotime but only scenariotime is
iterated through the horizon. Datatime is fixed throughout the Horizon.
Used when the power system stays the same thrughout the horizon.
"""

using Dates

import Base.:+, Base.:-

# --- Generic fallbacks ---

function +(t::ProbTime, d::Period)
    T = typeof(t)
    T((getfield(t, f) + d for f in fieldnames(T))...)
end

function -(t::ProbTime, d::Period)
    T = typeof(t)
    T((getfield(t, f) - d for f in fieldnames(T))...)
end

+(t::ProbTime, d::TimeDelta) = t + getduration(d)
-(t::ProbTime, d::TimeDelta) = t - getduration(d)

+(d::Period, t::ProbTime) = t + d
-(d::Period, t::ProbTime) = t - d

+(d::TimeDelta, t::ProbTime) = t + d
-(d::TimeDelta, t::ProbTime) = t - d

# --- Concrete time types ----

struct ConstantTime <: ProbTime 
    value::DateTime
    ConstantTime() = new(DateTime(2022, 10, 7))
end
+(t::ConstantTime, ::Period) = t
-(t::ConstantTime, ::Period) = t
getconstanttime(x::ConstantTime) = x.value
getdatatime(x::ConstantTime) = x.value
getscenariotime(x::ConstantTime) = x.value


# --- TwoTime ---
struct TwoTime <: ProbTime
    datatime::DateTime
    scenariotime::DateTime
end

getdatatime(x::TwoTime) = x.datatime
getscenariotime(x::TwoTime) = x.scenariotime


# --- FixedDataTwoTime ---
struct FixedDataTwoTime <: ProbTime
    datatime::DateTime
    scenariotime::DateTime
end

getdatatime(x::FixedDataTwoTime) = x.datatime
getscenariotime(x::FixedDataTwoTime) = x.scenariotime

+(t::FixedDataTwoTime, d::Period) = FixedDataTwoTime(getdatatime(t), getscenariotime(t) + d)
-(t::FixedDataTwoTime, d::Period) = FixedDataTwoTime(getdatatime(t), getscenariotime(t) - d)

+(t::FixedDataTwoTime, d::TimeDelta) = FixedDataTwoTime(getdatatime(t), getscenariotime(t) + getduration(d))
-(t::FixedDataTwoTime, d::TimeDelta) = FixedDataTwoTime(getdatatime(t), getscenariotime(t) - getduration(d))