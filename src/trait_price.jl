"""
We implement BasePrice (see abstracttypes.jl)
"""

# ---- Concrete types ----
mutable struct BasePrice <: Price
    param::Param

    function BasePrice(param)
        @assert !isdurational(param)
        new(param)
    end
end

# --------- Interface functions ------------
isconstant(price::BasePrice) = isconstant(price.param)
iszero(price::BasePrice) = iszero(price.param)
isdurational(price::BasePrice) = false
getparamvalue(price::BasePrice, t::ProbTime, d::TimeDelta) = getparamvalue(price.param, t, d)

# ------ Include dataelements -------
function includeBasePrice!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)

    deps = Id[]
    
    (id, param, ok) = getdictparamvalue(lowlevel, elkey, value)
    _update_deps(deps, id, ok)

    ok || return (false, deps)

    lowlevel[getobjkey(elkey)] = BasePrice(param)
    return (true, deps)
end

INCLUDEELEMENT[TypeKey(PRICE_CONCEPT, "BasePrice")] = includeBasePrice!
