"""
We implement BaseFlow (see general description in abstracttypes.jl)
"""

# ---------- Concrete types ---------------
mutable struct BaseFlow <: Flow
    id::Id

    horizon::Union{Horizon, Nothing}

    ub::Union{Capacity, Nothing}
    lb::Union{Capacity}

    costs::Vector{Cost}
    sumcost::Union{Nothing, SumCost}

    arrows::Vector{Arrow}

    metadata::Dict
    
    function BaseFlow(id::Id)
        new(id, nothing, nothing, LowerZeroCapacity(), [], nothing, [], Dict())
    end
end

# --- Interface functions ---

getid(var::BaseFlow) = var.id
gethorizon(var::BaseFlow) = var.horizon
getub(var::BaseFlow) = var.ub
getlb(var::BaseFlow) = var.lb
getcost(var::BaseFlow) = var.sumcost
getarrows(var::BaseFlow) = var.arrows

hascost(var::BaseFlow) = var.sumcost !== nothing

setub!(var::BaseFlow, capacity::Capacity) = var.ub = capacity
setlb!(var::BaseFlow, capacity::Capacity) = var.lb = capacity
sethorizon!(var::BaseFlow, horizon::Horizon) = var.horizon = horizon
setmetadata!(var::BaseFlow, k::String, v::Any) = var.metadata[k] = v

addarrow!(var::BaseFlow, arrow::Arrow) = push!(var.arrows, arrow)
addcost!(var::BaseFlow, cost::Cost) = push!(var.costs, cost)

# Flow objects can have state variables depending on the capacities and arrows
function getstatevariables(var::BaseFlow)
    vars = StateVariableInfo[]
    if !isnothing(var.lb)
        for s in getstatevariables(var.lb)
            push!(vars, s)
        end
    end
    if !isnothing(var.ub)
        for s in getstatevariables(var.ub)
            push!(vars, s)
        end
    end
    for arrow in getarrows(var)
        for s in getstatevariables(arrow)
            push!(vars, s)
        end
    end
    return vars
end

# Build the variable for each time period in the horizon
# Set upper and lower bounds (capacities)
# Include costs in the objective function (sumcost)
# Include variables in the balances (arrows)
function build!(p::Prob, var::BaseFlow)
    addvar!(p, var.id, getnumperiods(var.horizon))

    build!(p, var, var.lb)

    isnothing(var.ub) || build!(p, var, var.ub)

    for a in var.arrows
        build!(p, var, a)
    end
    return
end

function setconstants!(p::Prob, var::BaseFlow)
    !isnothing(var.sumcost) && setconstants!(p, var, var.sumcost)

    setconstants!(p, var, var.lb)

    isnothing(var.ub) || setconstants!(p, var, var.ub)

    for a in var.arrows
        setconstants!(p, var, a)
    end
    return
end

function update!(p::Prob, var::BaseFlow, start::ProbTime)
    !isnothing(var.sumcost) && update!(p, var, var.sumcost, start)

    update!(p, var, var.lb, start)

    isnothing(var.ub) || update!(p, var, var.ub, start)

    for a in var.arrows
        update!(p, var, a, start)
    end

    return
end

# Flow types are toplevel objects in dataset_compiler, so we must implement assemble!
function assemble!(var::BaseFlow)::Bool
    isempty(var.arrows) && error("No arrows for $(var.id)")

    # First check if all Arrows (with Balances) are assembled
    for a in var.arrows
        isnothing(gethorizon(a)) && return false
    end

    # Put costs from ExogenBalance into list of cost terms
    for a in var.arrows
        excost = getexogencost(a)
        if !isnothing(excost)        
            addcost!(var, excost)
        end
    end

    # Collect the finest Balance Horizon that the Flow is connected to through arrows. 
    # TODO: Add checks that the finest Horizon is compatible with the others
    var.horizon = gethorizon(first(var.arrows))
    for i in 2:lastindex(var.arrows)
        h = gethorizon(var.arrows[i])
        if getnumperiods(h) > getnumperiods(var.horizon)
            var.horizon = h
        end
    end

    # Make sumcost from all costterms
    if length(var.costs) > 0
        var.sumcost = SumCost(var.costs, var.horizon)
    end

    return true
end

# ------ Include dataelements -------
function includeBaseFlow!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)
    checkkey(toplevel, elkey)

    deps = Id[]
    
    objkey = getobjkey(elkey)
    
    toplevel[objkey] = BaseFlow(objkey)
    
    return (true, deps)    
end

INCLUDEELEMENT[TypeKey(FLOW_CONCEPT, "BaseFlow")] = includeBaseFlow!
