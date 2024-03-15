"""
We implement MsTimeDelta and UnitsTimeDelta

MsTimeDelta is a simple TimeDelta that contains a single timedelta in 
Millisecond. Used to represent the TimeDelta of a period in a Horizon

UnitsTimeDelta is a more complex TimeDelta used in AdaptiveHorizon.
The units are a list of time periods with unit_duration
See AdaptiveHorizon in horizons.jl
"""

import Base.:/, Base.:*, Base.:+, Base.:-

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

# --------- Interface functions ------------

# Get the total duration of the TimeDelta
getduration(x::MsTimeDelta) = x.ms
function getduration(x::UnitsTimeDelta)
    length(x.units) == 0 && return Millisecond(0)
    sum(length(r) for r in x.units) * x.unit_duration
end

# How many units are in the UnitsTimeDelta
function getlength(x::UnitsTimeDelta)
    length(x.units) == 0 && return 0
    return sum(length(r) for r in x.units)
end

+(d::MsTimeDelta, duration::Millisecond) = MsTimeDelta(getduration(d) + duration)
-(d::MsTimeDelta, duration::Millisecond) = MsTimeDelta(getduration(d) - duration)
+(d::MsTimeDelta, d1::MsTimeDelta) = MsTimeDelta(getduration(d) + getduration(d1))
-(d::MsTimeDelta, d1::MsTimeDelta) = MsTimeDelta(getduration(d) - getduration(d1))
/(d::MsTimeDelta, i::Int) = MsTimeDelta(getduration(d)/i)
*(d::MsTimeDelta, i::Int) = MsTimeDelta(getduration(d)*i)

# ------ Include dataelements -------
# TODO: Is this ever used? Can it be removed?
function includeMsTimeDelta!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)

    deps = Id[]
    
    period = getdictvalue(value, "Period", Union{Period, Int}, elkey)
    
    period isa Nanosecond && error("Nanosecond not allowed for $elkey")

    period = Millisecond(period)
    
    period > Millisecond(0) || error("Period <= Millisecond(0) for $elkey")
    
    lowlevel[getobjkey(elkey)] = MsTimeDelta(period)
    return (true, deps)
end

INCLUDEELEMENT[TypeKey(TIMEDELTA_CONCEPT, "MsTimeDelta")] = includeMsTimeDelta!
