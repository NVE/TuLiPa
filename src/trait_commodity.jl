"""
We implement BaseCommodity (see abstracttypes.jl)
"""

# --- Concrete types ---
mutable struct BaseCommodity <: Commodity
    id::Id
    horizon::Horizon
end

# --------- Interface functions ------------
getid(commodity::BaseCommodity) = commodity.id
gethorizon(commodity::BaseCommodity) = commodity.horizon

# ------ Include dataelements -------
function includeBaseCommodity!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)

    deps = Id[]
    
    haskey(value, HORIZON_CONCEPT) || error("Missing $HORIZON_CONCEPT for $elkey")

    horizon = getdictvalue(value, HORIZON_CONCEPT, Union{String, Horizon}, elkey)

    if horizon isa String
        horizonkey = Id(HORIZON_CONCEPT, horizon)
        push!(deps, horizonkey)
        haskey(lowlevel, horizonkey) || return (false, deps)
        horizon = lowlevel[horizonkey]
    end
   
    objkey = getobjkey(elkey)
    
    lowlevel[objkey] = BaseCommodity(objkey, horizon)
    
    return (true, deps)
end

INCLUDEELEMENT[TypeKey(COMMODITY_CONCEPT, "BaseCommodity")] = includeBaseCommodity!
