"""
We implement SimpleStartUpCost (also see abstracttypes.jl)
This is a linearized cost of increasing a Flow 
from 0 up to minimal stable load.
- startupcost is cost per unit (GW for thermal) increase of online capacity
- msl is the minimal stable load as a percentage of capacity

Internal non-negative variables: online and startvar
Equations restricting the Flow:
flow[t] >= online[t] * msl
flow[t] <= online[t]
startvar[t] >= (d/dt) online[t] (therefore online has statevariables)
Objective function contribution:
startupcost * startvar[t] / ub(flow)[t] 

# TODO: Implement RampingStartUpCost where startup ramping is restricted based on starthours
"""

# ------- Concrete type --------------------
mutable struct SimpleStartUpCost <: StartUpCost
    id::Id
    flow::Flow
    startcost::Float64
    msl::Float64
end

# ------- Interface functions ----------------
getid(trait::SimpleStartUpCost) = trait.id
getflow(trait::SimpleStartUpCost) = trait.flow

getparent(trait::SimpleStartUpCost) = getflow(trait)

# SimpleStartUpCost needs internal statevariables for online
# x[T] (var_out) is part of the online variable while x[0] (var_in) has to be named and built seperately
function getstatevariables(trait::SimpleStartUpCost)
    var_in_id = getstartonlinevarid(trait)
    var_out_id = getonlinevarid(trait)
    var_out_ix = getnumperiods(gethorizon(getflow(trait)))
    info = StateVariableInfo((var_in_id, 1), (var_out_id, var_out_ix))
    return [info]
end

# SimpleStartUpCost creates variables and equations that needs ids/names
function getonlinevarid(trait::SimpleStartUpCost)
    Id(getconceptname(trait.id), "OnlineCap" * getinstancename(trait.id))
end

function getstartonlinevarid(trait::SimpleStartUpCost)
    Id(getconceptname(trait.id), "StartOnlineCap" * getinstancename(trait.id))
end

function getstartconid(trait::SimpleStartUpCost)
    Id(getconceptname(trait.id), "StartCon" * getinstancename(trait.id))
end

function getstartvarid(trait::SimpleStartUpCost)
    Id(getconceptname(trait.id), "StartVar" * getinstancename(trait.id))
end

function getubconid(trait::SimpleStartUpCost)
    Id(getconceptname(trait.id), "UB" * getinstancename(trait.id))
end

function getlbconid(trait::SimpleStartUpCost)
    Id(getconceptname(trait.id), "LB" * getinstancename(trait.id))
end

function build!(p::Prob, trait::StartUpCost)
    T = getnumperiods(gethorizon(getflow(trait)))

    # Build internal variables and equations
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

function setconstants!(p::Prob, trait::StartUpCost)
    T = getnumperiods(gethorizon(trait.flow))

    flowid = getid(trait.flow)
    startvarid = getstartvarid(trait)
    startconid = getstartconid(trait)
    onlinevarid = getonlinevarid(trait)
    lbconid = getlbconid(trait)
    ubconid = getubconid(trait)

    for t in 1:T
        # Non-negative vars
        setlb!(p, onlinevarid, t, 0.0)
        setlb!(p, startvarid,  t, 0.0)

        # Include variables in equations
        # flow[t] >= online[t] * msl
        setconcoeff!(p, lbconid, flowid,   t, t, 1.0)
        setconcoeff!(p, lbconid, onlinevarid, t, t, -trait.msl)

        # flow[t] <= online[t]
        setconcoeff!(p, ubconid, flowid, t, t, 1.0)
        setconcoeff!(p, ubconid, onlinevarid, t, t, -1.0)

        # startvar[t] >= (d/dt) online[t] * msl for t > 1
        setconcoeff!(p, startconid, startvarid, t, t, 1.0)
        setconcoeff!(p, startconid, onlinevarid, t, t, -trait.msl) 
        if t > 1
            setconcoeff!(p, startconid, onlinevarid, t, t-1, trait.msl) 
        end
    end

    # set state variable
    start_id = getstartonlinevarid(trait)
    setconcoeff!(p, startconid, start_id, 1, 1, trait.msl)

    # Set objective coeff if it is constant
    cap = getub(trait.flow)
    if isconstant(cap)
        capvalue = getparamvalue(cap, ConstantTime(), MsTimeDelta(Hour(1)))
        @assert capvalue > 0.0
        c = trait.startcost / capvalue # cost of full startup

        # We want in objective [cost of 100% startup] * [share of capacity started]
        # Which is the same as
        # [cost of 100% startup] * [cap_started_GWh/Installed_Cap_GWh]
        # so the cost coefficient becomes [cost of 100% startup /Installed_Cap_GWh]
        # since the start variable is in GWh
        for t in 1:T
            setobjcoeff!(p, startvarid, t, c)
        end
    end

    return
end

# Set objective coeff if its not constant
function update!(p::Prob, trait::StartUpCost, start::ProbTime)
    startvarid = getstartvarid(trait)
    cap = getub(trait.flow)
    if !isconstant(cap)
        cost = trait.startcost * trait.starthours
        h = gethorizon(trait.flow)
        
        for t in 1:getnumperiods(h)
            querystart = getstarttime(h, t, start)
            querydelta = gettimedelta(h, t)
            capvalue = getparamvalue(cap, querystart, querydelta)
            if capvalue > 0.0
                coeff = cost / capvalue
            else
                coeff = 0.0
            end
            setobjcoeff!(p, startvarid, t, coeff)
        end
    end
    return
end

# SimpleStartUpCost types are toplevel objects in dataset_compiler, som we must implement assemble!
function assemble!(trait::SimpleStartUpCost)

    # return if flow not assembled yet
    isnothing(gethorizon(trait.flow)) && return false

    id = trait.id
    isnothing(getub(trait.flow)) && error("Flow does not have capacity for $id")

    return true
end

# ------ Include dataelements -------
function includeSimpleStartUpCost!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(toplevel, elkey)
    
    flowname = getdictvalue(value, FLOW_CONCEPT, String, elkey)
    flowkey = Id(FLOW_CONCEPT, flowname)
    haskey(toplevel, flowkey) || return false

    msl = getdictvalue(value, "MinStableLoad", Real, elkey)
    startcost = getdictvalue(value, "StartCost", Real, elkey)
    
    objkey = getobjkey(elkey)

    toplevel[objkey] = SimpleStartUpCost(objkey, toplevel[flowkey], startcost, msl)
    
    return true
 end

INCLUDEELEMENT[TypeKey(STARTUPCOST_CONCEPT, "SimpleStartUpCost")] = includeSimpleStartUpCost!