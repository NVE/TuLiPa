
# Generic fallbacks
gethorizon(storage::Storage) = gethorizon(getbalance(storage))

function getstatevariables(x::Storage)
    var_in_id = getstartvarid(x)
    var_out_id = getid(x)
    var_out_ix = getnumperiods(gethorizon(getbalance(x)))
    info = StateVariableInfo((var_in_id, 1), (var_out_id, var_out_ix))
    return [info]
end

# --- BaseStorage ---
mutable struct BaseStorage <: Storage
    id::Id
    balance::Balance
    lb::Capacity
    ub::Union{Nothing, Capacity}
    loss::Union{Nothing, Loss}
    costs::Vector{Cost}
    sumcost::Union{Nothing, SimpleSumCost}
    metadata::Dict

    function BaseStorage(id, balance)
        # check that parameters behave as they should
        @assert !isexogen(balance)
        return new(id, balance, LowerZeroCapacity(), nothing, nothing, [], nothing, Dict())
    end
end

getid(var::BaseStorage) = var.id

getloss(var::BaseStorage) = var.loss
getub(var::BaseStorage) = var.ub
getlb(var::BaseStorage) = var.lb
getcosts(var::BaseStorage) = var.costs

function getstoragehint(var::BaseStorage)
    if haskey(var.metadata, STORAGEHINTKEY)
        return var.metadata[STORAGEHINTKEY]
    else
        return nothing
    end
end

setub!(var::BaseStorage, ub::Capacity) = var.ub = ub
setlb!(var::BaseStorage, lb::Capacity) = var.lb = lb
setloss!(var::BaseStorage, loss::Loss) = var.loss = loss

setmetadata!(var::BaseStorage, k::String, v::Any) = var.metadata[k] = v

addcost!(var::BaseStorage, cost::Cost) = push!(var.costs, cost)

getbalance(var::BaseStorage) = var.balance

getstartvarid(var::BaseStorage) = Id(getconceptname(var.id), string("Start", getinstancename(var.id)))

function build!(p::Prob, var::BaseStorage)
    T = getnumperiods(gethorizon(var))
    addvar!(p, var.id, T)

    # add ingoing state variable
    addvar!(p, getstartvarid(var), 1)

    # make ingoing and outgoing state variables fixable
    makefixable!(p, getstartvarid(var), 1)
    makefixable!(p, var.id, T)
    return
end

function setconstants!(p::Prob, var::BaseStorage)
    T = getnumperiods(gethorizon(var))
    for t in 1:T
        setconcoeff!(p, getid(getbalance(var)), getid(var), t, t, -1.0)
    end

    if !isnothing(var.loss) && isconstant(var.loss)
        dummytime = ConstantTime()
        dummydelta = MsTimeDelta(Hour(1))
        coeff = 1.0 - getparamvalue(var.loss, dummytime, dummydelta)
    else
        coeff = 1.0
    end

    for t in 2:T
        setconcoeff!(p, getid(getbalance(var)), getid(var), t, t-1, coeff)
    end

    # set start storage variable in first balance equation
    setconcoeff!(p, getid(getbalance(var)), getstartvarid(var), 1, 1, coeff)

    setconstants!(p, var, var.lb)
    setconstants!(p, var, var.ub)

    if !isnothing(var.sumcost)
        setconstants!(p, var.sumcost)
    end

    return
end

function update!(p::Prob, var::BaseStorage, start::ProbTime)
    update!(p, var, var.lb, start)
    update!(p, var, var.ub, start)

    if !isnothing(var.sumcost)
        update!(p, var.sumcost, start)
    end

    if !isnothing(var.loss) && !isconstant(var.loss)
        horizon = gethorizon(var)

        querystart = getstarttime(horizon, 1, start)
        querydelta = gettimedelta(horizon, 1)
        coeff = 1.0 - getparamvalue(var.loss, querystart, querydelta)
        setconcoeff!(p, getid(getbalance(var)), getstartvarid(var), t, 1, coeff)

        T = getnumperiods(horizon)
        for t in 2:T
            querystart = getstarttime(horizon, t, start)
            querydelta = gettimedelta(horizon, t)
            coeff = 1.0 - getparamvalue(var.loss, querystart, querydelta)
            setconcoeff!(p, getid(getbalance(var)), getid(var), t, t-1, coeff)
        end    
    end

    return
end

function assemble!(var::BaseStorage)::Bool
    id = getid(var)

    isnothing(var.ub) && error("No upper bound for $id")

    balance = getbalance(var)

    # return if balance not assembled yet
    isnothing(gethorizon(balance)) && return false
    
    horizon = gethorizon(balance)
    T = getnumperiods(horizon)
    (T < 2) && error("Storage balance must have at least 2 periods in horizon for $id")

    if length(var.costs) > 0
        var.sumcost = SimpleSumCost(var.costs)
    end

    return true
end

function includeBaseStorage!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(toplevel, elkey)
    
    balancename = getdictvalue(value, BALANCE_CONCEPT, String, elkey)
    balancekey = Id(BALANCE_CONCEPT, balancename)
    haskey(toplevel, balancekey) || return false
    
    objkey = getobjkey(elkey)

    toplevel[objkey] = BaseStorage(objkey, toplevel[balancekey])
    
    return true    
end

INCLUDEELEMENT[TypeKey(STORAGE_CONCEPT, "BaseStorage")] = includeBaseStorage!
