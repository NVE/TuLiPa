"""
We implement BaseRHSTerm (see abstracttypes.jl)

# TODO: Implement RoRRHSTerm. A simplification of the run-of-river 
hydropower could be to include the inflow (with cutoff at max production)
as a parameter rather than modelling it as a variable. 
Motivation is simplification of the problem or to include the unregulated
inflow when we make an AdaptiveHorizon based on the residual load
"""

# -------- Generic fallback function ---------------
isdurational(rhsterm::RHSTerm) = true

# -------- Concrete types --------------
struct BaseRHSTerm <: RHSTerm
    id::Id
    param::Param
    isingoing::Bool
    metadata::Dict

    function BaseRHSTerm(id, param, isingoing)
        return new(id, param, isingoing, Dict())
    end
end

# --------- Interface functions ------------
getid(rhsterm::BaseRHSTerm) = rhsterm.id
isconstant(rhsterm::BaseRHSTerm) = isconstant(rhsterm.param)
getparamvalue(rhsterm::BaseRHSTerm, t::ProbTime, d::TimeDelta) = getparamvalue(rhsterm.param, t, d)

# Represents positive or negative contribution to the Balance
isingoing(rhsterm::BaseRHSTerm) = rhsterm.isingoing

# We store ResidualHint in the metadata element
setmetadata!(var::BaseRHSTerm, k::String, v::Any) = var.metadata[k] = v
function getresidualhint(var::BaseRHSTerm)
    if haskey(var.metadata, RESIDUALHINTKEY)
        return var.metadata[RESIDUALHINTKEY]
    else
        return nothing
    end
end

# ------ Include dataelements -------
function includeBaseRHSTerm!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    (param, ok) = getdictparamvalue(lowlevel, elkey, value)
    ok || return false
    @assert isdurational(param)
    
    balancename = getdictvalue(value, BALANCE_CONCEPT, String, elkey)
    balancekey = Id(BALANCE_CONCEPT, balancename)
    haskey(toplevel, balancekey) || return false
    
    isingoing = getdictisingoing(value, elkey)

    balance = toplevel[balancekey]

    id = getobjkey(elkey)
    
    rhsterm = BaseRHSTerm(id, param, isingoing)
        
    addrhsterm!(balance, rhsterm)
    
    return true    
end

INCLUDEELEMENT[TypeKey(RHSTERM_CONCEPT, "BaseRHSTerm")] = includeBaseRHSTerm!
