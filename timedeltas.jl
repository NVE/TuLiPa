"""
We implement MsTimeDelta and UnitsTimeDelta

MsTimeDelta is a simple TimeDelta that contains a timedelta in Millisecond.
Used to represent the TimeDelta of a period in a Horizon

UnitsTimeDelta is a more complex TimeDelta used in AdaptiveHorizon
It is used when we want to group hours (or time units) in
an horizon based on their characteristics (e.g. hours 
with similar residual load). Here we don't necessarily care if the
hours are sequential in time.
The units are a list of UnitRanges.
Heres an example if we split the hours in every week 
by high load (day), and low load (night):
UnitsTimeDelta 1: [7:20, 32:40, 56:68, 80:92, 104:116, 128:140, 152:164] - first week high load
UnitsTimeDelta 2: [1:6, 20:31, 41:55 etc...] - first week low load
UnitsTimeDelta 3: [175:188, etc...] - second week high load
UnitsTimeDelta 4: [169:174, etc...] - second week low load
UnitsTimeDelta 5: [...] - third week high load
UnitsTimeDelta 6: [...] - third week low load
"""

# ----- Concrete types ----------
struct MsTimeDelta <: TimeDelta
    ms::Millisecond
    
    function MsTimeDelta(p::Period, ps::Period...)
        ms = Millisecond(p)
        for i in ps
            ms += Millisecond(i)
        end
        return new(ms)
    end
end

mutable struct UnitsTimeDelta <: TimeDelta
    units::Vector{UnitRange{Int}}
    unit_duration::Millisecond
end

# ------ General functions ------------

# Get the total duration of the TimeDelta
getduration(x::MsTimeDelta) = x.ms
function getduration(x::UnitsTimeDelta)
    length(x.units) == 0 && return Millisecond(0)
    sum(length(r) for r in x.units) * x.unit_duration
end

# How many units are in the UnitsTimeDelta
function getlength(x::UnitsTimeDelta)
    length(x.units) == 0 && return Millisecond(0)
    return sum(length(r) for r in x.units)
end

# ---- Includefunction -----
function includeMsTimeDelta!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    period = getdictvalue(value, "Period", Union{Period, Int}, elkey)
    
    period isa Nanosecond && error("Nanosecond not allowed for $elkey")

    period = Millisecond(period)
    
    period > Millisecond(0) || error("Period <= Millisecond(0) for $elkey")
    
    lowlevel[getobjkey(elkey)] = MsTimeDelta(period)
    return true
end

INCLUDEELEMENT[TypeKey(TIMEDELTA_CONCEPT, "MsTimeDelta")] = includeMsTimeDelta!
