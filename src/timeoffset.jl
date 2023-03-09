"""
We implement TimeDeltaOffset and IsoYearOffset

TimeDeltaOffset shifts ProbTime with a TimeDelta

ScenarioOffset also has an offset that represent the scenario. The total
offset is the sum of the two offsets. Compatible with PhaseInTwoTime where 
both offsets does not apply to the same elements.

IsoYearOffset shifts ProbTime with a TimeDelta and also the 
scenariotime to another isoyear.
"""

# ----- Concrete types ----------
struct TimeDeltaOffset <: Offset
    timedelta::TimeDelta
end

struct ScenarioOffset <: Offset
    timedelta::TimeDelta
    scenariodelta::TimeDelta
end

mutable struct IsoYearOffset <: Offset
    isoyear::Int
    timedelta::TimeDelta
end

# --------- Interface functions ------------

gettimedelta(offset::Offset) = offset.timedelta
getscenariodelta(offset::Offset) = offset.timedelta
getisoyear(offset::IsoYearOffset) = offset.isoyear

function getoffsettime(start::ProbTime, offset::TimeDeltaOffset)
    return start + gettimedelta(offset)
end

function getoffsettime(start::PhaseinTwoTime, offset::TimeDeltaOffset)
    return PhaseinTwoTime(getdatatime(start), getscenariotime1(start), getscenariotime2(start) + getduration(gettimedelta(offset)), getphaseinvector(start))
end


function getoffsettime(start::TwoTime, offset::ScenarioOffset) # generic fallback
    return start + gettimedelta(offset) + getscenariodelta(offset)
end

function getoffsettime(start::PhaseinTwoTime, offset::ScenarioOffset)
    starttime = PhaseinTwoTime(getdatatime(start), getscenariotime1(start), getscenariotime2(start) + getduration(getscenariodelta(offset)), getphaseinvector(start))
    return starttime + gettimedelta(offset)
end


function getoffsettime(start::TwoTime, offset::IsoYearOffset)
    starttime = TwoTime(getdatatime(start), getsimilardatetime(getscenariotime(start), getisoyear(offset)))
    return starttime += gettimedelta(offset)
end

function getoffsettime(start::FixedDataTwoTime, offset::IsoYearOffset)
    starttime = FixedDataTwoTime(getdatatime(start), getsimilardatetime(getscenariotime(start), getisoyear(offset)))
    return starttime += gettimedelta(offset)
end

function getoffsettime(start::PhaseinTwoTime, offset::IsoYearOffset)
    starttime = PhaseinTwoTime(getdatatime(start), getscenariotime1(start), getsimilardatetime(getscenariotime2(start), getisoyear(offset)), getphaseinvector(start))
    return starttime += gettimedelta(offset)
end