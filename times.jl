"""
A ProbTime have at least two dimensions. 
The first dimention is datatime, the second is scenariotime.
We use datatime to look up capacities and such.
We use scenariotime to look up profile values.

# TODO: Should all ProbTime types implement getdatatime and getscenariotime?
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
#   Datatime is constant
#   Only change scenariotime part

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