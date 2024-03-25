"""
We implement BaseConversion (see abstracttypes.jl)

We implement PumpConversion, which is similar to BaseConversion,
but holds information that can be used to recalculate the conversion
factor given the reservoir level in upper and lower reservoirs.
"""

# ---- Concrete types ----
mutable struct BaseConversion <: Conversion
    param::Param

    function BaseConversion(param)
        @assert !isdurational(param)
        new(param)
    end
end

mutable struct PumpConversion <: Conversion
    param::Param

    releaseheightcurve
    hmin::Float64
    hmax::Float64
    pumppower::Float64
    intakelevel::Float64

    function PumpConversion(param, releaseheightcurve, hmin, hmax, pumppower, intakelevel)
        @assert !isdurational(param)
        new(param, releaseheightcurve, hmin, hmax, pumppower, intakelevel)
    end
end

# --------- Interface functions ------------
isconstant(conversion::Conversion) = isconstant(conversion.param)
iszero(conversion::Conversion) = iszero(conversion.param)
isone(conversion::Conversion) = isone(conversion.param)
isdurational(conversion::Conversion) = false
getparamvalue(conversion::Conversion, t::ProbTime, d::TimeDelta) = getparamvalue(conversion.param, t, d)

# Only does something for more complex Conversions
build!(::Prob, ::Conversion) = nothing
setconstants!(::Prob, ::Conversion) = nothing
update!(::Prob, ::Conversion, ::ProbTime) = nothing

# ------ Include dataelements -------
function includeBaseConversion!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)

    deps = Id[]
    
    (id, param, ok) = getdictparamvalue(lowlevel, elkey, value)
    _update_deps(deps, id, ok)

    ok || return (false, deps)

    lowlevel[getobjkey(elkey)] = BaseConversion(param)
    return (true, deps)
end

function includePumpConversion!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)

    deps = Id[]

    (id, param, ok) = getdictparamvalue(lowlevel, elkey, value)
    ok || return (false, deps)

    hmin = getdictvalue(value, "hmin", Float64, elkey) 
    hmax = getdictvalue(value, "hmax", Float64, elkey)
    qmin = getdictvalue(value, "qmin", Float64, elkey) 
    qmax = getdictvalue(value, "qmax", Float64, elkey)
    releaseheightcurve = XYCurve([hmin, hmax], [qmin, qmax])

    intakelevel = getdictvalue(value, "IntakeLevel", Float64, elkey)
    pumppower = getdictvalue(value, "PumpPower", Float64, elkey)

    lowlevel[getobjkey(elkey)] = PumpConversion(param, releaseheightcurve, hmin, hmax, pumppower, intakelevel)
    return (true, deps)
end

INCLUDEELEMENT[TypeKey(CONVERSION_CONCEPT, "BaseConversion")] = includeBaseConversion!
INCLUDEELEMENT[TypeKey(CONVERSION_CONCEPT, "PumpConversion")] = includePumpConversion!