"""
We implement BaseConversion (see abstracttypes.jl)
"""

# ---- Concrete types ----
mutable struct BaseConversion <: Conversion
    param::Param

    function BaseConversion(param)
        @assert !isdurational(param)
        new(param)
    end
end

# --------- Interface functions ------------
isconstant(conversion::BaseConversion) = isconstant(conversion.param)
iszero(conversion::BaseConversion) = iszero(conversion.param)
isone(conversion::BaseConversion) = isone(conversion.param)
isdurational(conversion::BaseConversion) = false
getparamvalue(conversion::BaseConversion, t::ProbTime, d::TimeDelta) = getparamvalue(conversion.param, t, d)

# Only does something for more complex Conversions
build!(::Prob, ::BaseConversion) = nothing
setconstants!(::Prob, ::BaseConversion) = nothing
update!(::Prob, ::BaseConversion, ::ProbTime) = nothing

# ------ Include dataelements -------
function includeBaseConversion!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    (param, ok) = getdictparamvalue(lowlevel, elkey, value)
    ok || return false

    lowlevel[getobjkey(elkey)] = BaseConversion(param)
    return true
end

INCLUDEELEMENT[TypeKey(CONVERSION_CONCEPT, "BaseConversion")] = includeBaseConversion!
