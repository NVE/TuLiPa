"""
TimeDeltas support

  getduration(::TimeDelta) -> Millisecond
"""

# UnitsTimeDelta is used in AdaptiveHorizon

mutable struct UnitsTimeDelta <: TimeDelta
    units::Vector{UnitRange{Int}}
    unit_duration::Millisecond
end

function getduration(x::UnitsTimeDelta)
    length(x.units) == 0 && return Millisecond(0)
    sum(length(r) for r in x.units) * x.unit_duration
end

function getlength(x::UnitsTimeDelta)
    length(x.units) == 0 && return Millisecond(0)
    return sum(length(r) for r in x.units)
end

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

getduration(x::MsTimeDelta) = x.ms

# TODO: Delete this? Not used?
isconstant(::MsTimeDelta) = true

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

# --------------------------------------

struct SegmentDelta <: TimeDelta
    segments::Vector{UnitRange{Int}}
    timedelta::MsTimeDelta
    totaltimedelta::MsTimeDelta # Can be removed and calculated every time
end

getsegments(d::SegmentDelta) = d.segments
gettimedelta(d::SegmentDelta) = d.timedelta
gettotaltimedelta(d::SegmentDelta) = d.totaltimedelta
getduration(d::SegmentDelta) = getduration(d.totaltimedelta) # sum(length(segment) for segment in segments(d))*timedelta(d)
getstarttime(first::Int, timedelta::TimeDelta, start::DateTime) = start + getduration(timedelta)*(first-1) # Er denne malplassert?


