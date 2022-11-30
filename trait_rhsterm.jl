
# TODO: Implement RoRRHSTerm

isdurational(rhsterm::RHSTerm) = true

struct BaseRHSTerm <: RHSTerm
    id::Id
    param::Param
    isingoing::Bool
end

isconstant(rhsterm::BaseRHSTerm) = isconstant(rhsterm.param)
getparamvalue(rhsterm::BaseRHSTerm, t::ProbTime, d::TimeDelta) = getparamvalue(rhsterm.param, t, d)
isingoing(rhsterm::BaseRHSTerm) = rhsterm.isingoing
getid(rhsterm::BaseRHSTerm) = rhsterm.id

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
