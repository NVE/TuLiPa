"""
We implement two types of Balance: BaseBalance and ExogenBalance
Both are defined for a commodity, horizon and they both have metadata

BaseBalance is a conventional balance defined for each period in the 
horizon. It can take contributions from variables (e.g. Flow or Storage) 
or parameters (from RHSTerm). The contribution from each variable is 
decided by arrows (it converts the variable into the Commodity of the 
Balance, and may take into account losses and lag)

ExogenBalance represent an exogen system, and holds the Price of the 
Commodity in this system. Flows (with Arrow) that contribute to this 
Balance will have an income or cost, which is included in the objective 
function. The contribution to the objective function is decided by 
the price of the commodity multiplied with the contribution from the 
variable into the Balance.

This framework make us able to use the same dataset regardless of if 
a Flow (with Arrow) is connected to an Endogenous or Exogenous system. 
For example can a hydropower system be switched from being connected
to a power market (endogenous) to a price (exogenous),
and only the Balance object will have to be changed.
"""

# ---------- Concrete types -----------------
mutable struct BaseBalance <: Balance
    id::Id
    commodity::Commodity
    horizon::Union{Horizon, Nothing}
    rhsterms::Vector{RHSTerm}
    metadata::Dict
    
    function BaseBalance(id, commodity)
        # Q: Why not init horizon as well?
        # A: Then Horizon must be in dataset, and we want Horizon to be set later as run settings
        #    We also may want to set horizon either through Commodity or directly on Balance
        new(id, commodity, nothing, [], Dict()) 
    end
end

mutable struct ExogenBalance <: Balance
    id::Id
    commodity::Commodity
    horizon::Union{Horizon, Nothing}
    price::Price
    metadata::Dict
    
    function ExogenBalance(id, commodity, price)
        new(id, commodity, nothing, price, Dict())
    end
end

# --- Interface functions ---

# Implementation of interface for our Balance types
const OurBalanceTypes = Union{BaseBalance, ExogenBalance}

getid(balance::OurBalanceTypes) = balance.id
gethorizon(balance::OurBalanceTypes) = balance.horizon
getcommodity(balance::OurBalanceTypes) = balance.commodity

setmetadata!(var::OurBalanceTypes, k::String, v::Any) = var.metadata[k] = v

# Since isexogen is false we must implement getrhsterms and addrhsterm!
isexogen(::BaseBalance) = false
getrhsterms(balance::BaseBalance) = balance.rhsterms
addrhsterm!(balance::BaseBalance, rhsterm::RHSTerm) = push!(balance.rhsterms, rhsterm) ; return

# Since isexogen is true we must implement getprice
isexogen(::ExogenBalance) = true
getprice(balance::ExogenBalance) = balance.price

# ExogenBalance does not have equations to build and update
build!(::Prob, ::ExogenBalance) = nothing
setconstants!(::Prob, ::ExogenBalance) = nothing
update!(::Prob, ::ExogenBalance, ::ProbTime) = nothing

# Build empty balance equation for BaseBalance
function build!(p::Prob, balance::BaseBalance)
    addeq!(p, balance.id, getnumperiods(balance.horizon))
    return
end

# Set RHSterms if they are constant 
function setconstants!(p::Prob, balance::BaseBalance)
    hasconstantdurations(balance.horizon) || return

    for rhsterm in balance.rhsterms
        if isconstant(rhsterm)
            dummytime = ConstantTime()
            for t in 1:getnumperiods(balance.horizon)
                querystart = getstarttime(balance.horizon, t, dummytime)
                querydelta = gettimedelta(balance.horizon, t)
                value = getparamvalue(rhsterm, querystart, querydelta)
                if !isingoing(rhsterm)
                    value = -value
                end
                setrhsterm!(p, balance.id, getid(rhsterm), t, value)
            end
        end
    end
    return
end

# Set RHSterms if they have to be updated dynamically
function update!(p::Prob, balance::BaseBalance, start::ProbTime)

    for rhsterm in balance.rhsterms
        if !isconstant(rhsterm) || !hasconstantdurations(balance.horizon)
            for t in 1:getnumperiods(balance.horizon)
                querystart = getstarttime(balance.horizon, t, start)
                querydelta = gettimedelta(balance.horizon, t)
                value = getparamvalue(rhsterm, querystart, querydelta)
                if !isingoing(rhsterm)
                    value = -value
                end
                setrhsterm!(p, balance.id, getid(rhsterm), t, value)
            end
        end
    end
    return
end

# Balance types are toplevel objects in dataset_compiler, so we must 
# implement assemble!
# If horizon is nothing it is initialized from the commodity
function assemble!(balance::OurBalanceTypes)::Bool 
    if isnothing(balance.horizon)
        horizon = gethorizon(balance.commodity)
        isnothing(horizon) && error("No horizon for $(balance.id)")
        balance.horizon = horizon
    end
    return true
end

# ------ Include dataelements -------
function includeBaseBalance!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(toplevel, elkey)
    
    commodityname = getdictvalue(value, COMMODITY_CONCEPT, String, elkey)
    commoditykey = Id(COMMODITY_CONCEPT, commodityname)
    haskey(lowlevel, commoditykey) || return false
    
    id = getobjkey(elkey)
    
    toplevel[id] = BaseBalance(id, lowlevel[commoditykey])
    
    return true    
end

function includeExogenBalance!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(toplevel, elkey)

    (price, ok) = getdictpricevalue(lowlevel, elkey, value)
    ok || return false
    
    commodityname = getdictvalue(value, COMMODITY_CONCEPT, String, elkey)
    commoditykey = Id(COMMODITY_CONCEPT, commodityname)
    haskey(lowlevel, commoditykey) || return false
    
    id = getobjkey(elkey)
    
    toplevel[id] = ExogenBalance(id, lowlevel[commoditykey], price)
    
    return true    
end

INCLUDEELEMENT[TypeKey(BALANCE_CONCEPT, "BaseBalance")] = includeBaseBalance!
INCLUDEELEMENT[TypeKey(BALANCE_CONCEPT, "ExogenBalance")] = includeExogenBalance!
