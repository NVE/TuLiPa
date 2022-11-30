# --- Concrete types ---
mutable struct BaseCommodity <: Commodity
    id::Id
    horizon::Horizon
end

# --- Commodity interface functions ---
getid(commodity::BaseCommodity) = commodity.id
gethorizon(commodity::BaseCommodity) = commodity.horizon

# --- dataelements to modelobjects ---
function includeBaseCommodity!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    haskey(value, HORIZON_CONCEPT) || error("Missing $HORIZON_CONCEPT for $elkey")

    horizon = getdictvalue(value, HORIZON_CONCEPT, Union{String, Horizon}, elkey)

    if horizon isa String
        horizonkey = Id(HORIZON_CONCEPT, horizon)
        haskey(lowlevel, horizonkey) || return false
        horizon = lowlevel[horizonkey]
    end
   
    objkey = getobjkey(elkey)
    
    lowlevel[objkey] = BaseCommodity(objkey, horizon)
    
    return true
end

INCLUDEELEMENT[TypeKey(COMMODITY_CONCEPT, "BaseCommodity")] = includeBaseCommodity!
