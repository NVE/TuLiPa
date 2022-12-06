
function getstatevariables(trait::StartUpCost)
    var_in_id = getstartonlinevarid(trait)
    var_out_id = getonlinevarid(trait)
    var_out_ix = getnumperiods(gethorizon(getflow(trait)))
    info = StateVariableInfo((var_in_id, 1), (var_out_id, var_out_ix))
    return [info]
end

getparent(trait::StartUpCost) = getflow(trait)

# Prob interface 

function build!(p::Prob, trait::StartUpCost)
    T = getnumperiods(gethorizon(getflow(trait)))

    addvar!(p, getonlinevarid(trait), T)
    addvar!(p, getstartvarid(trait), T)

    addge!(p, getstartconid(trait), T)
    addge!(p, getlbconid(trait), T)
    addle!(p, getubconid(trait), T)

    addvar!(p, getstartonlinevarid(trait), 1)

    # make ingoing and outgoing state variables fixable
    makefixable!(p, getstartonlinevarid(trait), 1)
    makefixable!(p, getonlinevarid(trait), T)

    return
end

function update!(p::Prob, trait::StartUpCost, start::ProbTime)
    # Set objective coeff if its not constant
    startvarid = getstartvarid(trait)
    cap = getub(trait.flow)
    if !isconstant(cap)
        F = trait.startcost * trait.starthours / trait.msl
        h = gethorizon(trait.flow)
        
        for t in 1:getnumperiods(h)
            querystart = getstarttime(h, t, start)
            querydelta = gettimedelta(h, t)
            capvalue = getparamvalue(cap, querystart, querydelta)
            if capvalue > 0.0
                c = F / capvalue
            else
                c = 0.0
            end
            setobjcoeff!(p, startvarid, t, c)
        end
    end
    return
end

function setconstants!(p::Prob, trait::StartUpCost)
    T = getnumperiods(gethorizon(trait.flow))

    flowid = getid(trait.flow)
    startvarid = getstartvarid(trait)
    startconid = getstartconid(trait)
    onlinevarid = getonlinevarid(trait)
    lbconid = getlbconid(trait)
    ubconid = getubconid(trait)

    # Set objective coeff if it is constant
    cap = getub(trait.flow)
    if isconstant(cap)
        capvalue = getparamvalue(cap, ConstantTime(), MsTimeDelta(Hour(1)))
        @assert capvalue > 0.0
        c = trait.startcost * trait.starthours / (capvalue * trait.msl)
        for t in 1:T
            setobjcoeff!(p, startvarid, t, c)
        end
    end

    for t in 1:T
        # Non-negative vars
        setlb!(p, onlinevarid, t, 0.0)
        setlb!(p, startvarid,  t, 0.0)

        # gen[t] >= online[t] * msl
        setconcoeff!(p, lbconid, flowid,   t, t, 1.0)
        setconcoeff!(p, lbconid, onlinevarid, t, t, -trait.msl)

        # gen[t] <= online[t]
        setconcoeff!(p, ubconid, flowid, t, t, 1.0)
        setconcoeff!(p, ubconid, onlinevarid, t, t, -1.0)

        # startvar[t] >= (d/dt) online[t] for t > 1
        setconcoeff!(p, startconid, startvarid, t, t, 1.0)
        setconcoeff!(p, startconid, onlinevarid, t, t, -1.0)
        if t > 1
            setconcoeff!(p, startconid, onlinevarid, t, t-1, 1.0)
        end
    end

    # set state variable
    start_id = getstartonlinevarid(trait)
    setconcoeff!(p, startconid, start_id, 1, 1, 1.0)

    return
end

mutable struct BaseStartUpCost <: StartUpCost
    id::Id
    flow::Flow
    startcost::Float64
    starthours::Float64
    msl::Float64
    
    function BaseStartUpCost(id, genflow, startcost, starthours, msl)
        return new(id, genflow, startcost, starthours, msl)
    end
end

getid(trait::BaseStartUpCost) = trait.id

# BaseStartUpCost creates variables and equations that needs ids/names
function getonlinevarid(trait::BaseStartUpCost)
    Id(getconceptname(trait.id), "OnlineCap" * getinstancename(trait.id))
end

function getstartonlinevarid(trait::BaseStartUpCost)
    Id(getconceptname(trait.id), "StartOnlineCap" * getinstancename(trait.id))
end

function getstartconid(trait::BaseStartUpCost)
    Id(getconceptname(trait.id), "StartCon" * getinstancename(trait.id))
end

function getstartvarid(trait::BaseStartUpCost)
    Id(getconceptname(trait.id), "StartVar" * getinstancename(trait.id))
end

function getubconid(trait::BaseStartUpCost)
    Id(getconceptname(trait.id), "UB" * getinstancename(trait.id))
end

function getlbconid(trait::BaseStartUpCost)
    Id(getconceptname(trait.id), "LB" * getinstancename(trait.id))
end

getflow(trait::BaseStartUpCost) = trait.flow

# Assemble interface

function assemble!(trait::BaseStartUpCost)

    # return if flow not assembled yet
    isnothing(gethorizon(trait.flow)) && return false

    id = trait.id
    isnothing(getub(trait.flow)) && error("Flow does not have capacity for $id")

    return true
end

# ------ Include dataelements -------
function includeBaseStartUpCost!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(toplevel, elkey)
    
    flowname = getdictvalue(value, FLOW_CONCEPT, String, elkey)
    flowkey = Id(FLOW_CONCEPT, flowname)
    haskey(toplevel, flowkey) || return false

    msl = getdictvalue(value, "MinStableLoad", Real, elkey)
    starthours = getdictvalue(value, "StartHours", Real, elkey)
    startcost = getdictvalue(value, "StartCost", Real, elkey)
    
    objkey = getobjkey(elkey)

    toplevel[objkey] = BaseStartUpCost(objkey, toplevel[flowkey], startcost, starthours, msl)
    
    return true
 end

INCLUDEELEMENT[TypeKey(STARTUPCOST_CONCEPT, "BaseStartUpCost")] = includeBaseStartUpCost!