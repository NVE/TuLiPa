mutable struct BaseSoftBound <: SoftBound
    id::Id
    var::Any
    softcap::Param
    penalty::Param
    isupper::Bool
    
    function BaseSoftBound(id, var, softcap, penalty, isupper)
        return new(id, var, softcap, penalty, isupper)
    end
end

getid(trait::BaseSoftBound) = trait.id
getvar(trait::BaseSoftBound) = trait.var
getsoftcap(trait::BaseSoftBound) = trait.softcap
getpenalty(trait::BaseSoftBound) = trait.penalty
isupper(trait::BaseSoftBound) = trait.isupper

getmainmodelobject(trait::BaseSoftBound) = trait.var

function includeBaseSoftBound!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    (softcap, ok) = getdictparamvalue(lowlevel, elkey, value, SOFTCAPKEY)
    ok || return false
    
    (penalty, ok) = getdictparamvalue(lowlevel, elkey, value, PENALTYKEY)
    ok || return false
    
    isupper = getdictisupper(value, elkey)
    
    varname    = getdictvalue(value, WHICHINSTANCE, String, elkey)
    varconcept = getdictvalue(value, WHICHCONCEPT,  String, elkey)
    varkey = Id(varconcept, varname)
    haskey(toplevel, varkey) || return false

    var = toplevel[varkey]
        
    varkey = getobjkey(elkey)
    toplevel[varkey] = BaseSoftBound(varkey, var, softcap, penalty, isupper)
    
    return true     
end

INCLUDEELEMENT[TypeKey(SOFTBOUND_CONCEPT, "BaseSoftBound")] = includeBaseSoftBound!

function assemble!(trait::BaseSoftBound)
    # return if var not assembled yet
    isnothing(gethorizon(trait.var)) && return false

    return true
end

function getleid(trait::BaseSoftBound)
    Id(getconceptname(trait.id), "Le" * getinstancename(trait.id))
end

function getbreachvarid(trait::BaseSoftBound)
    Id(getconceptname(trait.id), "Breach" * getinstancename(trait.id))
end
    
function getsoftcapid(trait::BaseSoftBound)
    Id(getconceptname(trait.id), "SoftCap" * getinstancename(trait.id))
end

function build!(p::Prob, trait::BaseSoftBound)
    T = getnumperiods(gethorizon(getvar(trait)))

    addvar!(p, getbreachvarid(trait), T)
    addle!(p, getleid(trait), T)

    return
end

function setconstants!(p::Prob, trait::BaseSoftBound)
    horizon = gethorizon(trait.var)
    T = getnumperiods(horizon)

    if trait.isupper
        rhssign = 1.0 # same as vardirection
    else
        rhssign = -1.0
    end
        
    varid = getid(trait.var)
    leid = getleid(trait)
    breachvarid = getbreachvarid(trait)
    softcapid = getsoftcapid(trait)

    if isconstant(trait.penalty)
        c = getparamvalue(trait.penalty, ConstantTime(), MsTimeDelta(Hour(1)))

        for t in 1:T
            setobjcoeff!(p, breachvarid, t, c)
        end
    end
    
    if !_must_dynamic_update(trait.softcap, horizon)
        if isdurational(trait.softcap)
            for t in 1:T
                querydelta = gettimedelta(horizon, t)
                value = getparamvalue(trait.softcap, ConstantTime(), querydelta)
                setrhsterm!(p, leid, softcapid, t, value*rhssign)
            end
        else
            value = getparamvalue(trait.softcap, ConstantTime(), MsTimeDelta(Hour(1)))
            for t in 1:T
                setrhsterm!(p, leid, softcapid, t, value*rhssign)
            end
        end
    end

    for t in 1:T
        # Non-negative vars
        setlb!(p, breachvarid, t, 0.0)

        # rhssign*boundedvar[t] - breachvar[t] <= rhssign*softcap
        setconcoeff!(p, leid, varid, t, t, rhssign)
        setconcoeff!(p, leid, breachvarid, t, t, -1.0)
    end
    return
end

function update!(p::Prob, trait::BaseSoftBound, start::ProbTime)
    horizon = gethorizon(trait.var)
    T = getnumperiods(horizon)
    
    if trait.isupper
        rhssign = 1.0 # same as vardirection
    else
        rhssign = -1.0
    end
    
    # Set varective coeff if its not constant
    if !isconstant(trait.penalty)
        softcapid = getsoftcapid(trait)
        for t in 1:T
            querystart = getstarttime(horizon, t, start)
            querydelta = gettimedelta(horizon, t)
            c = getparamvalue(trait.penalty, querystart, querydelta)
            
            setobjcoeff!(p, breachvarid, t, c)
        end
    end
    
    # Set rhs if its not constant
    if _must_dynamic_update(trait.softcap, horizon)
        softcapid = getsoftcapid(trait)
        leid = getleid(trait)
        for t in 1:T
            querystart = getstarttime(horizon, t, start)
            querydelta = gettimedelta(horizon, t)
            value = getparamvalue(trait.softcap, querystart, querydelta)
            
            setrhsterm!(p, leid, softcapid, t, value*rhssign)
        end
    end
    return
end