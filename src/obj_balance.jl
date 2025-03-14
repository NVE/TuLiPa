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
        if !_must_dynamic_update(rhsterm)
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
        if _must_dynamic_update(rhsterm) || !hasconstantdurations(balance.horizon)
            if isstateful(rhsterm)
                for t in 1:getnumperiods(balance.horizon)
                    _update_rhsterm(p, balance, start, rhsterm, t)
                end
            else
                for t in 1:getnumperiods(balance.horizon)
                    (future_t, ok) = mayshiftfrom(balance.horizon, t)
                    if ok
                        value = getrhsterm(p, balance.id, getid(rhsterm), future_t)
                        setrhsterm!(p, balance.id, getid(rhsterm), t, value)
                    end
                end
                for t in 1:getnumperiods(balance.horizon)
                    if mustupdate(balance.horizon, t)
                        _update_rhsterm(p, balance, start, rhsterm, t)
                    end
                end
            end
        end
    end
    return
end

function _update_rhsterm(p, balance, start, rhsterm, t)
    querystart = getstarttime(balance.horizon, t, start)
    querydelta = gettimedelta(balance.horizon, t)
    value = getparamvalue(rhsterm, querystart, querydelta)
    if !isingoing(rhsterm)
        value = -value
    end
    setrhsterm!(p, balance.id, getid(rhsterm), t, value)
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
function includeBaseBalance!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(toplevel, elkey)

    commodityname = getdictvalue(value, COMMODITY_CONCEPT, String, elkey)
    commoditykey = Id(COMMODITY_CONCEPT, commodityname)

    deps = Id[]
    push!(deps, commoditykey)

    haskey(lowlevel, commoditykey) || return (false, deps)
    
    id = getobjkey(elkey)
    
    toplevel[id] = BaseBalance(id, lowlevel[commoditykey])
    
    return (true, deps)    
end

function includeExogenBalance!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(toplevel, elkey)

    deps = Id[]

    commodityname = getdictvalue(value, COMMODITY_CONCEPT, String, elkey)
    commoditykey = Id(COMMODITY_CONCEPT, commodityname)
    push!(deps, commoditykey)

    (id, price, ok) = getdictpricevalue(lowlevel, elkey, value)
    _update_deps(deps, id, ok)

    ok || return (false, deps)
    haskey(lowlevel, commoditykey) || return (false, deps)
    
    id = getobjkey(elkey)
    
    toplevel[id] = ExogenBalance(id, lowlevel[commoditykey], price)
    
    return (true, deps)    
end

INCLUDEELEMENT[TypeKey(BALANCE_CONCEPT, "BaseBalance")] = includeBaseBalance!
INCLUDEELEMENT[TypeKey(BALANCE_CONCEPT, "ExogenBalance")] = includeExogenBalance!
