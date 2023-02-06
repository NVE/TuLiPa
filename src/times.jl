"""
We implement ConstantTime, TwoTime, FixedDataTwoTime and 
PhaseInTwoTime (see abstracttypes.jl)

ConstantTime is used when getting the value from a constant parameter
Then the time does not matter (our framework is built around getting 
values from time series data)

TwoTime has datatime and scenariotime where both of them are iterated 
through the horizon. Used when the power system and weather scenarios 
change throughout the horizon.

FixedDataTwoTime has datatime and scenariotime but only scenariotime is
iterated through the horizon. Datatime is fixed throughout the Horizon.
Used when the power system stays the same thrughout the horizon.

PhaseinTwoTime works similar to FixedDataTwoTime, but it also has two
scenariotimes. PhaseinTwoTime should be used when we want to use
different scenarios at different times in the Horizon, or combine 
scenarios. The field "phaseinvector" holds information on how much 
each scenario should be weighted at a specific time.
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

# --- PhaseinTwoTime ---
struct PhaseinTwoTime <: ProbTime
    datatime::DateTime
    scenariotime1::DateTime
    scenariotime2::DateTime
    phaseinvector::InfiniteTimeVector
    
    function PhaseinTwoTime(datatime, scenariotime1, scenariotime2, phaseinvector)
        new(datatime, scenariotime1, scenariotime2, phaseinvector)
    end

    function PhaseinTwoTime(datatime, scenariotime1, scenariotime2, 
        phaseinoffset, phaseindelta, phaseinsteps)
        
        index = Vector{DateTime}(undef, phaseinsteps+1)
        values = Vector{Float64}(undef, phaseinsteps+1)
        for i in 0:phaseinsteps
            index[i+1] = scenariotime1 + phaseinoffset + Millisecond(round(Int, phaseindelta.value*(i-1)/phaseinsteps))
            values[i+1] = round(i/phaseinsteps,digits=3)
        end
        phaseinvector = InfiniteTimeVector(index, values)
        new(datatime, scenariotime1, scenariotime2, phaseinvector)
    end
end

getdatatime(x::PhaseinTwoTime) = x.datatime
getscenariotime1(x::PhaseinTwoTime) = x.scenariotime1
getscenariotime2(x::PhaseinTwoTime) = x.scenariotime2
getphaseinvector(x::PhaseinTwoTime) = x.phaseinvector

+(t::PhaseinTwoTime, d::Period) = PhaseinTwoTime(getdatatime(t), getscenariotime1(t) + d, getscenariotime2(t) + d, getphaseinvector(t))
-(t::PhaseinTwoTime, d::Period) = PhaseinTwoTime(getdatatime(t), getscenariotime1(t) - d, getscenariotime2(t) + d, getphaseinvector(t))

+(t::PhaseinTwoTime, d::TimeDelta) = PhaseinTwoTime(getdatatime(t), getscenariotime1(t) + getduration(d), getscenariotime2(t) + getduration(d), getphaseinvector(t))
-(t::PhaseinTwoTime, d::TimeDelta) = PhaseinTwoTime(getdatatime(t), getscenariotime1(t) - getduration(d), getscenariotime2(t) + getduration(d), getphaseinvector(t))