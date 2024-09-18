"""
We implement BaseSoftBound (see abstracttypes.jl)
"""

# ----------- Concrete types -------------
mutable struct BaseSoftBound <: SoftBound
    id::Id
    var::Any
    softcap::Param
    penalty::Param
    isupper::Bool
    fixable::Bool
end

# --------- Interface functions ------------
getid(trait::BaseSoftBound) = trait.id
getvar(trait::BaseSoftBound) = trait.var
getsoftcap(trait::BaseSoftBound) = trait.softcap
getpenalty(trait::BaseSoftBound) = trait.penalty
isupper(trait::BaseSoftBound) = trait.isupper
isfixable(trait::BaseSoftBound) = trait.fixable

getparent(trait::BaseSoftBound) = trait.var

# BaseSoftBound creates variables and equations that needs ids/names
function getleid(trait::BaseSoftBound)
    Id(getconceptname(trait.id), "Le" * getinstancename(trait.id))
end

function getbreachvarid(trait::BaseSoftBound)
    Id(getconceptname(trait.id), "Breach" * getinstancename(trait.id))
end
    
function getsoftcapid(trait::BaseSoftBound)
    Id(getconceptname(trait.id), "SoftCap" * getinstancename(trait.id))
end

# ---------- build!, setconstants! and update! ---------

# Build variables and equations for softbound equation, also make breachvar fixable
function build!(p::Prob, trait::BaseSoftBound)
    T = getnumperiods(gethorizon(getvar(trait)))

    addvar!(p, getbreachvarid(trait), T)
    addle!(p, getleid(trait), T)

    if isfixable(trait)
        for t in 1:T
            makefixable!(p, getbreachvarid(trait), t)
        end
    end

    return
end

function setconstants!(p::Prob, trait::BaseSoftBound)
    horizon = gethorizon(trait.var)
    T = getnumperiods(horizon)

    # Positive or negative contribution in softbound equation
    # depending on upper or lower softbound
    if trait.isupper
        sign = 1.0 # sign used for rhs and var in equation
    else
        sign = -1.0
    end
        
    varid = getid(trait.var)
    leid = getleid(trait)
    breachvarid = getbreachvarid(trait)
    softcapid = getsoftcapid(trait)

    for t in 1:T
        # Non-negative breachvars
        setlb!(p, breachvarid, t, 0.0)

        # Var and breachvar in softbound equation
        # sign*var[t] - breachvar[t] <= sign*softcap[t]
        setconcoeff!(p, leid, varid, t, t, sign)
        setconcoeff!(p, leid, breachvarid, t, t, -1.0)
    end

    # Set breach penalty in objective function if its not constant
    if !_must_dynamic_update(trait.penalty)
        c = getparamvalue(trait.penalty, ConstantTime(), MsTimeDelta(Hour(1)))

        for t in 1:T
            setobjcoeff!(p, breachvarid, t, c)
        end
    end
    
    # Set RHS in softbound if it is the same for all scenarios and horizon periods
    if !_must_dynamic_update(trait.softcap, horizon)
        if isdurational(trait.softcap) # SequentialHorizon can have two or more sets of (nperiods, duration) pairs
            for t in 1:T
                querydelta = gettimedelta(horizon, t)
                value = getparamvalue(trait.softcap, ConstantTime(), querydelta)
                setrhsterm!(p, leid, softcapid, t, value*sign)
            end
        else
            value = getparamvalue(trait.softcap, ConstantTime(), MsTimeDelta(Hour(1)))
            for t in 1:T
                setrhsterm!(p, leid, softcapid, t, value*sign)
            end
        end
    end

    return
end

# See comments in setconstants!
function update!(p::Prob, trait::BaseSoftBound, start::ProbTime)
    horizon = gethorizon(trait.var)
    T = getnumperiods(horizon)
    
    if trait.isupper
        sign = 1.0
    else
        sign = -1.0
    end
    
    if _must_dynamic_update(trait.penalty)
        softcapid = getsoftcapid(trait)
        for t in 1:T
            querystart = getstarttime(horizon, t, start)
            querydelta = gettimedelta(horizon, t)
            c = getparamvalue(trait.penalty, querystart, querydelta)
            
            setobjcoeff!(p, breachvarid, t, c)
        end
    end
    
    if _must_dynamic_update(trait.softcap, horizon)
        softcapid = getsoftcapid(trait)
        leid = getleid(trait)
        for t in 1:T
            querystart = getstarttime(horizon, t, start)
            querydelta = gettimedelta(horizon, t)
            value = getparamvalue(trait.softcap, querystart, querydelta)
            
            setrhsterm!(p, leid, softcapid, t, value*sign)
        end
    end
    return
end

function getbreachvars(trait::BaseSoftBound)
    if isfixable(trait)
        horizon = gethorizon(trait.var)
        T = getnumperiods(horizon)
        breachvarid = getbreachvarid(trait)

        breachvars = Tuple{Id, Int}[]
        for t in 1:T
            push!(breachvars, (breachvarid, t))
        end

        return breachvars
    else
        return []
    end
end 

assemble!(trait::BaseSoftBound) = !isnothing(gethorizon(trait.var))

# ------ Include dataelements -------
function includeBaseSoftBound!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    deps = Id[]

    isupper = getdictisupper(value, elkey)
    
    varname    = getdictvalue(value, WHICHINSTANCE, String, elkey)
    varconcept = getdictvalue(value, WHICHCONCEPT,  String, elkey)
    varkey = Id(varconcept, varname)
    push!(deps, varkey)

    all_ok = true

    (id, softcap, ok) = getdictparamvalue(lowlevel, elkey, value, SOFTCAPKEY)
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)
    
    (id, penalty, ok) = getdictparamvalue(lowlevel, elkey, value, PENALTYKEY)
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    all_ok || return (false, deps)
    haskey(toplevel, varkey) || return (false, deps)
    
    var = toplevel[varkey]
        
    varkey = getobjkey(elkey)
    toplevel[varkey] = BaseSoftBound(varkey, var, softcap, penalty, isupper, false)
    
    return (true, deps)     
end

INCLUDEELEMENT[TypeKey(SOFTBOUND_CONCEPT, "BaseSoftBound")] = includeBaseSoftBound!

