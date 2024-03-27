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

mutable struct VectorPrice <: Price
    values::Vector{Float64}
end

# --------- Interface functions ------------
isconstant(price::BasePrice) = isconstant(price.param)
isconstant(price::VectorPrice) = false

iszero(price::BasePrice) = iszero(price.param)
iszero(price::VectorPrice) = false

isdurational(price::BasePrice) = false
isdurational(price::VectorPrice) = false

isstateful(cost::BasePrice) = isstateful(cost.param)
isstateful(cost::VectorPrice) = true

getparamvalue(price::BasePrice, t::ProbTime, d::TimeDelta; ix=0) = getparamvalue(price.param, t, d)
getparamvalue(price::VectorPrice, t::ProbTime, d::TimeDelta; ix=0) = price.values[ix]

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
function includeVectorPrice!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)

    values = getdictvalue(value, "Vector", Vector{Float64}, elkey)

    lowlevel[getobjkey(elkey)] = VectorPrice(values)
    return true
end

INCLUDEELEMENT[TypeKey(PRICE_CONCEPT, "BasePrice")] = includeBasePrice!
INCLUDEELEMENT[TypeKey(PRICE_CONCEPT, "VectorPrice")] = includeVectorPrice!
