"""
We implement TimeDeltaOffset and IsoYearOffset

TimeDeltaOffset shifts ProbTime with a TimeDelta

IsoYearOffset shifts ProbTime with a TimeDelta and also the 
scenariotime to another isoyear.
"""

# ----- Concrete types ----------
struct TimeDeltaOffset <: Offset
    timedelta::TimeDelta
end

mutable struct IsoYearOffset <: Offset
    isoyear::Int
    timedelta::TimeDelta
end

# --------- Interface functions ------------

gettimedelta(offset::Offset) = offset.timedelta
getisoyear(offset::IsoYearOffset) = offset.isoyear

function getoffsettime(start::ProbTime, offset::TimeDeltaOffset)
    return start + gettimedelta(offset)
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