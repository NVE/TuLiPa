"""
We implement CostTerm and SumCost

CostTerm represents a single contribution to the objective function

SumCost sums up several CostTerms for a Flow or Storage
"""

# -------- Generic fallback --------------------
isdurational(::Cost) = false

# --------- Concrete types
mutable struct CostTerm <: Cost
    id::Id
    param::Union{Param, Price}
    isingoing::Bool
end

struct SumCost <: Cost
    terms::Vector{Cost}
    values::Matrix{Float64}
    isupdated::Vector{Bool}

    function SumCost(terms::Vector{Cost}, h::Horizon)
        T = getnumperiods(h)
        numterms = length(terms)
        new(terms, zeros(T, numterms), falses(T))
    end
end

# --------- Interface functions ------------
isconstant(cost::CostTerm) = isconstant(cost.param)
function isconstant(cost::SumCost)
    for term in cost.terms
        !isconstant(term) && return false
    end
    return true
end

isstateful(cost::CostTerm) = isstateful(cost.param)
function isstateful(cost::SumCost)
    for term in cost.terms
        isstateful(term) && return true
    end
    return false
end

getid(cost::CostTerm) = cost.id

# Indicate positive or negative contribution to objective function
isingoing(cost::CostTerm) = cost.isingoing
isingoing(cost::SumCost) = true

function getparamvalue(cost::CostTerm, t::ProbTime, d::TimeDelta; ix=0)
    value = getparamvalue(cost.param, t, d, ix=ix)
    if !isingoing(cost)
        return -value
    else
        return value
    end
end
function getparamvalue(cost::SumCost, t::ProbTime, d::TimeDelta) # quick fix for AggSupplyCurve, implement cost, lb and ub for aggsupplycurve
    value = float(0)
    for term in cost.terms
        value += getparamvalue(term, t, d)
    end
    return value
end

function setconstants!(p::Prob, var::Any, sumcost::SumCost)
    T = getnumperiods(var.horizon)
    for (col, term) in enumerate(sumcost.terms)
        if isconstant(term) && !isstateful(term)
            dummytime = ConstantTime()
            for t in 1:T
                querydelta = gettimedelta(var.horizon, t)
                sumcost.values[t, col] = getparamvalue(term, dummytime, querydelta, ix=t)::Float64
                sumcost.isupdated[t] = true
            end
        end
    end

    if isconstant(sumcost) && !isstateful(sumcost)
        for t in 1:T
            if sumcost.isupdated[t] == true
                value = sum(sumcost.values[t, :])
                setobjcoeff!(p, var.id, t, value)
            end
        end
    end
end

function update!(p::Prob, var::Any, sumcost::SumCost, start::ProbTime)
    fill!(sumcost.isupdated, false)

    T = getnumperiods(var.horizon)
    for (col, term) in enumerate(sumcost.terms)
        if !isconstant(term) || isstateful(term)
            for t in 1:T
                if mustupdate(var.horizon, t)
                    querystart = getstarttime(var.horizon, t, start)
                    querydelta = gettimedelta(var.horizon, t)
                    sumcost.values[t, col] = getparamvalue(term, querystart, querydelta, ix=t)::Float64
                    sumcost.isupdated[t] = true
                end
            end
        end
    end

    for t in 1:T
        (future_t, ok) = mayshiftfrom(var.horizon, t)
        if ok && (sumcost.isupdated[t] == false)
            value = getobjcoeff!(p, var.id, future_t)
            setobjcoeff!(p, var.id, t, value)
        end
    end

    for t in 1:T
        if sumcost.isupdated[t] == true
            value = sum(sumcost.values[t, :])
            setobjcoeff!(p, var.id, t, value)
        end
    end
end

# ------ Include dataelements -------
function includeCostTerm!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    (param, ok) = getdictparamvalue(lowlevel, elkey, value)
    ok || return false
    @assert !isdurational(param)

    varname    = getdictvalue(value, WHICHINSTANCE, String, elkey)
    varconcept = getdictvalue(value, WHICHCONCEPT,  String, elkey)
    varkey = Id(varconcept, varname)
    haskey(toplevel, varkey) || return false

    var = toplevel[varkey]

    isingoing = getdictisingoing(value, elkey)
    
    id = getobjkey(elkey)

    cost = CostTerm(id, param, isingoing)

    addcost!(var, cost)
    
    return true    
end

INCLUDEELEMENT[TypeKey(COST_CONCEPT, "CostTerm")] = includeCostTerm!