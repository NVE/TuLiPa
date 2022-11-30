

# ---- Concrete types ----
mutable struct BasePrice <: Price
    param::Param

    function BasePrice(param)
        @assert !isdurational(param)
        new(param)
    end
end

# ---- General functions ----
isconstant(price::BasePrice) = isconstant(price.param)
iszero(price::BasePrice) = iszero(price.param)
isdurational(price::BasePrice) = false
getparamvalue(price::BasePrice, t::ProbTime, d::TimeDelta) = getparamvalue(price.param, t, d)

build!(::Prob, ::BasePrice) = nothing
setconstants!(::Prob, ::BasePrice) = nothing
update!(::Prob, ::BasePrice, ::ProbTime) = nothing

# ------ Includefunctions ----------------
function includeBasePrice!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    (param, ok) = getdictparamvalue(lowlevel, elkey, value)
    ok || return false

    lowlevel[getobjkey(elkey)] = BasePrice(param)
    return true
end

INCLUDEELEMENT[TypeKey(PRICE_CONCEPT, "BasePrice")] = includeBasePrice!
