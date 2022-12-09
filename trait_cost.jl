"""
We implement CostTerm and SimpleSumCost

CostTerm represents a single contribution to the objective function

SimpleSumCost sums up several CostTerms for a Flow or Storage
"""

# -------- Generic fallback --------------------
isdurational(::Cost) = false

# --------- Concrete types
struct CostTerm <: Cost
    id::Id
    param::Union{Param, Price}
    isingoing::Bool
end

struct SimpleSumCost <: Cost
    terms::Vector{Cost}
end

# --------- Interface functions ------------
isconstant(cost::CostTerm) = isconstant(cost.param)
function isconstant(cost::SimpleSumCost)
    for term in cost.terms
        !isconstant(term) && return false
    end
    return true
end

# Indicate positive or negative contribution to objective function
isingoing(cost::CostTerm) = cost.isingoing
isingoing(cost::SimpleSumCost) = true

getparamvalue(cost::CostTerm, t::ProbTime, d::TimeDelta) = getparamvalue(cost.param, t, d)
function getparamvalue(cost::SimpleSumCost, start::ProbTime, d::TimeDelta)
    value = 0.0
    for term in cost.terms
        termvalue = getparamvalue(term, start, d)
        if !isingoing(term) 
            termvalue = -termvalue
        end
        value += termvalue
    end
    return value
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