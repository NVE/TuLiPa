
isdurational(::Cost) = false

struct CostTerm <: Cost
    id::Id
    param::Union{Param, Price}
    isingoing::Bool
end

# --------- Interface functions ------------
isconstant(cost::CostTerm) = isconstant(cost.param)
getparamvalue(cost::CostTerm, t::ProbTime, d::TimeDelta) = getparamvalue(cost.param, t, d)
isingoing(cost::CostTerm) = cost.isingoing

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

# ------ SumCosts ----

struct SimpleSumCost <: Cost
    terms::Vector{Cost}
end

isingoing(cost::SimpleSumCost) = true

function isconstant(cost::SimpleSumCost)
    for term in cost.terms
        !isconstant(term) && return false
    end
    return true
end

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