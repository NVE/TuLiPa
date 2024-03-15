"""
We implement TransmissionRamping, HydroRampingWithout, HydroRamping (also see abstracttypes.jl)

TransmissionRamping is ramping restriction for both up and down-ramping on a transmission line. 
The transmission is represented by two flows, one for each direction.
Ramping capacity input is percentage of max capacity of one of the flows (TODO: Make version where up and downramping is different?)
- Assumes that the flow capacity is a MWToGWhSeriesParam with a level and a profile (TODO?)
Internal variables: sumtransmission (sum of tranmsission in both directions, and has state variables)
Equations restricting the internal variable:
sumtransmission[t] = secondflow[t] - firstflow[t]
(d/dt) sumtransmission[t] <= rampingcap[t] (upramping)
- (d/dt) sumtransmission[t] <= rampingcap[t] for t > 1 (downramping)

HydroRampingWithout is a hard ramping restriction for both up and down-ramping on hydropower release.
It does not have ramping costs. Neither state variables that can be fixed.
Ramping capacity input is percentage of max capacity of one of the release
It does not have any internal variables, only equations that restrict the release:
(d/dt) flow[t] <= rampingcap[t] for t > 2 (up)
- (d/dt) flow[t] <= rampingcap[t] for t > 2 (down)

HydroRamping is similar to HydroRampingWithout, but it has state variables

TODO: Make soft hydropower release ramping that have costs or that restricts multiple releases.

"""

# ------- Concrete type --------------------
mutable struct TransmissionRamping <: Ramping
    id::Id
    firstflow::Flow
    secondflow::Flow
    rampingcap::Param
end

mutable struct HydroRampingWithout <: Ramping
    id::Id
    flow::Flow
    rampingcap::Param
end

mutable struct HydroRamping <: Ramping
    id::Id
    flow::Flow
    rampingcap::Param
end

# ------- Interface functions ----------------
getid(trait::Ramping) = trait.id

# Assumes firstflow and secondflow are always in the same system and will be grouped together
# TODO: Replace with getobjects, more robust
# getobjects(trait::TransmissionRamping) = [trait.firstflow, trait.secondflow]
getparent(trait::TransmissionRamping) = trait.firstflow
getparent(trait::HydroRampingWithout) = trait.flow
getparent(trait::HydroRamping) = trait.flow

gethorizon(trait::Ramping) = gethorizon(getparent(trait))

# TransmissionRamping needs internal state variables for ramping
# x[T] (var_out) is part of the ramping variable while x[0] (var_in) has to be named and built seperately
function getstatevariables(trait::TransmissionRamping)
    var_in_id = getstartsumtransmissionvarid(trait)
    var_out_id = getsumtransmissionvarid(trait)
    var_out_ix = getnumperiods(gethorizon(trait))
    info = StateVariableInfo((var_in_id, 1), (var_out_id, var_out_ix))
    return [info]
end

# HydroRamping contains the state variables of the ramping variable (flow)
# var_out is equal to x[T] of the ramping variable, while var_in represents x[0] of the ramping variable. Both have to be named and built
function getstatevariables(trait::HydroRamping)
    var_in_id = getstartflowvarid(trait)
    var_out_id = getendflowvarid(trait)
    info = StateVariableInfo((var_in_id, 1), (var_out_id, 1))
    return [info]
end

# Ramping traits creates variables and equations that needs ids/names
function getstartsumtransmissionvarid(trait::TransmissionRamping)
    Id(getconceptname(trait.id), "StartSumTransmission" * getinstancename(trait.id))
end

function getsumtransmissionvarid(trait::TransmissionRamping)
    Id(getconceptname(trait.id), "SumTransmission" * getinstancename(trait.id))
end

function getsumtransmissionconid(trait::TransmissionRamping)
    Id(getconceptname(trait.id), "SumTransmissionCon" * getinstancename(trait.id))
end

function getstartflowvarid(trait::Ramping)
    Id(getconceptname(trait.id), "Start" * getinstancename(trait.id))
end

function getendflowvarid(trait::Ramping)
    Id(getconceptname(trait.id), "End" * getinstancename(trait.id))
end

function getendvarconid(trait::Ramping)
    Id(getconceptname(trait.id), "EndVarCon" * getinstancename(trait.id))
end

function getuprampingconid(trait::Ramping)
    Id(getconceptname(trait.id), "UpRampingCon" * getinstancename(trait.id))
end

function getdownrampingconid(trait::Ramping)
    Id(getconceptname(trait.id), "DownRampingCon" * getinstancename(trait.id))
end

function build!(p::Prob, trait::TransmissionRamping)
    T = getnumperiods(gethorizon(trait))

    # Build internal variables and equations
    addvar!(p, getsumtransmissionvarid(trait), T)

    addeq!(p, getsumtransmissionconid(trait), T)
    addle!(p, getuprampingconid(trait), T)
    addle!(p, getdownrampingconid(trait), T)

    addvar!(p, getstartsumtransmissionvarid(trait), 1)

    # make ingoing and outgoing state variables fixable
    makefixable!(p, getstartsumtransmissionvarid(trait), 1)
    makefixable!(p, getsumtransmissionvarid(trait), T)

    return
end
function build!(p::Prob, trait::HydroRampingWithout)
    T = getnumperiods(gethorizon(trait))

    # Build internal variables and equations
    addle!(p, getuprampingconid(trait), T-1)
    addle!(p, getdownrampingconid(trait), T-1)

    return
end
function build!(p::Prob, trait::HydroRamping)
    T = getnumperiods(gethorizon(trait))

    # Build internal variables and equations
    addvar!(p, getstartflowvarid(trait), 1)
    addvar!(p, getendflowvarid(trait), 1)

    addle!(p, getuprampingconid(trait), T)
    addle!(p, getdownrampingconid(trait), T)
    addeq!(p, getendvarconid(trait), 1)

    # make ingoing and outgoing state variables fixable
    makefixable!(p, getstartflowvarid(trait), 1)
    makefixable!(p, getendflowvarid(trait), 1)

    return
end

function setconstants!(p::Prob, trait::TransmissionRamping)
    h = gethorizon(trait)
    T = getnumperiods(h)

    startsumtransmissionvarid = getstartsumtransmissionvarid(trait)
    sumtransmissionvarid = getsumtransmissionvarid(trait)
    sumtransmissionconid = getsumtransmissionconid(trait)

    uprampingconid = getuprampingconid(trait)
    downrampingconid = getdownrampingconid(trait)

    for t in 1:T

        # Include variables in equations
        # secondflow[t] - firstflow[t] == sumtransmission[t]
        setconcoeff!(p, sumtransmissionconid, getid(trait.secondflow), t, t, 1.0)
        setconcoeff!(p, sumtransmissionconid, getid(trait.firstflow), t, t, -1.0)
        setconcoeff!(p, sumtransmissionconid, sumtransmissionvarid, t, t, -1.0)

        # (d/dt) sumtransmission[t] <= rampingcap[t] for t > 1 (up)
        # - (d/dt) sumtransmission[t] <= rampingcap[t] for t > 1 (down)
        setconcoeff!(p, uprampingconid, sumtransmissionvarid, t, t, -1.0)
        setconcoeff!(p, downrampingconid, sumtransmissionvarid, t, t, 1.0) 
        if t > 1
            setconcoeff!(p, uprampingconid, sumtransmissionvarid, t, t-1, 1.0) 
            setconcoeff!(p, downrampingconid, sumtransmissionvarid, t, t-1, -1.0) 
        end
    end

    # set state variable in (d/dt) sumtransmission[t] <= rampingcap[t] (up)
    # set state variable in - (d/dt) sumtransmission[t] <= rampingcap[t] (down)
    setconcoeff!(p, uprampingconid, startsumtransmissionvarid, 1, 1, 1.0)
    setconcoeff!(p, downrampingconid, startsumtransmissionvarid, 1, 1, -1.0)

    # Set ramping cap if it does not have to update dynamically
    _must_dynamic_update(trait.rampingcap, h) && return

    if isdurational(trait.rampingcap)
        dummytime = ConstantTime()
        # Q: Why not calculate value only once here?
        # A: Because SequentialHorizon can have two or more sets of (nperiod, duration) pairs
        for t in 1:T
            querydelta = gettimedelta(h, t)
            value = getparamvalue(trait.rampingcap, dummytime, querydelta)
            setrhsterm!(p, uprampingconid, trait.id, t, value)
            setrhsterm!(p, downrampingconid, trait.id, t, value)
        end
    else
        dummytime = ConstantTime()
        dummydelta = MsTimeDelta(Hour(1))
        value = getparamvalue(trait.rampingcap, dummytime, dummydelta)
        for t in 1:T
            setrhsterm!(p, uprampingconid, trait.id, t, value)
            setrhsterm!(p, downrampingconid, trait.id, t, value)
        end
    end
    return
end

function setconstants!(p::Prob, trait::HydroRampingWithout)
    h = gethorizon(trait)
    T = getnumperiods(h)

    flowid = getid(trait.flow)
    uprampingconid = getuprampingconid(trait)
    downrampingconid = getdownrampingconid(trait)

    for t in 2:T
        # Include variables in equations

        # (d/dt) flow[t] <= rampingcap[t] for t > 2 (up)
        # - (d/dt) flow[t] <= rampingcap[t] for t > 2 (down)
        setconcoeff!(p, uprampingconid, flowid, t-1, t, -1.0)
        setconcoeff!(p, uprampingconid, flowid, t-1, t-1, 1.0) 
        setconcoeff!(p, downrampingconid, flowid, t-1, t, 1.0)
        setconcoeff!(p, downrampingconid, flowid, t-1, t-1, -1.0)
    end

    # Set ramping cap if it does not have to update dynamically
    _must_dynamic_update(trait.rampingcap, h) && return

    if isdurational(trait.rampingcap)
        dummytime = ConstantTime()
        # Q: Why not calculate value only once here?
        # A: Because SequentialHorizon can have two or more sets of (nperiod, duration) pairs
        for t in 1:(T-1)
            querydelta = gettimedelta(h, t)
            value = getparamvalue(trait.rampingcap, dummytime, querydelta)
            setrhsterm!(p, uprampingconid, trait.id, t, value)
            setrhsterm!(p, downrampingconid, trait.id, t, value)
        end
    else
        dummytime = ConstantTime()
        dummydelta = MsTimeDelta(Hour(1))
        value = getparamvalue(trait.rampingcap, dummytime, dummydelta)
        for t in 1:(T-1)
            setrhsterm!(p, uprampingconid, trait.id, t, value)
            setrhsterm!(p, downrampingconid, trait.id, t, value)
        end
    end
    return
end
function setconstants!(p::Prob, trait::HydroRamping)

    h = gethorizon(trait)
    T = getnumperiods(h)

    startflowid = getstartflowvarid(trait)
    endflowid = getendflowvarid(trait)
    flowid = getid(trait.flow)
    uprampingconid = getuprampingconid(trait)
    downrampingconid = getdownrampingconid(trait)
    endconid = getendvarconid(trait)

    # flow[T] = endflow[T]
    setconcoeff!(p, endconid, endflowid, 1, 1, -1.0)
    setconcoeff!(p, endconid, flowid, 1, T, 1.0)

    for t in 1:T
        # Include variables in equations

        # (d/dt) flow[t] <= rampingcap[t] for t > 1 (up)
        # - (d/dt) flow[t] <= rampingcap[t] for t > 1 (down)
        setconcoeff!(p, uprampingconid, flowid, t, t, -1.0)
        setconcoeff!(p, downrampingconid, flowid, t, t, 1.0)

        if t > 1
            setconcoeff!(p, uprampingconid, flowid, t, t-1, 1.0) 
            setconcoeff!(p, downrampingconid, flowid, t, t-1, -1.0)
        end
    end

    setconcoeff!(p, uprampingconid, startflowid, 1, 1, 1.0)
    setconcoeff!(p, downrampingconid, startflowid, 1, 1, -1.0)

    # Set ramping cap if it does not have to update dynamically
    _must_dynamic_update(trait.rampingcap, h) && return

    if isdurational(trait.rampingcap)
        dummytime = ConstantTime()
        # Q: Why not calculate value only once here?
        # A: Because SequentialHorizon can have two or more sets of (nperiod, duration) pairs
        for t in 1:T
            querydelta = gettimedelta(h, t)
            value = getparamvalue(trait.rampingcap, dummytime, querydelta)
            setrhsterm!(p, uprampingconid, trait.id, t, value)
            setrhsterm!(p, downrampingconid, trait.id, t, value)
        end
    else
        dummytime = ConstantTime()
        dummydelta = MsTimeDelta(Hour(1))
        value = getparamvalue(trait.rampingcap, dummytime, dummydelta)
        for t in 1:T
            setrhsterm!(p, uprampingconid, trait.id, t, value)
            setrhsterm!(p, downrampingconid, trait.id, t, value)
        end
    end
    return
end

# Set ramping cap if it must update dynamically
function update!(p::Prob, trait::TransmissionRamping, start::ProbTime)
    h = gethorizon(trait)

    if !isconstant(trait.rampingcap) || !hasconstantdurations(h)
        for t in 1:getnumperiods(h)
            querystart = getstarttime(h, t, start)
            querydelta = gettimedelta(h, t)
            value = getparamvalue(trait.rampingcap, querystart, querydelta)
            setrhsterm!(p, getuprampingconid(trait), trait.id, t, value)
            setrhsterm!(p, getdownrampingconid(trait), trait.id, t, value)
        end
    end
    return
end

function update!(p::Prob, trait::HydroRampingWithout, start::ProbTime)
    h = gethorizon(trait)

    if !isconstant(trait.rampingcap) || !hasconstantdurations(h)
        for t in 1:(getnumperiods(h)-1)
            querystart = getstarttime(h, t, start)
            querydelta = gettimedelta(h, t)
            value = getparamvalue(trait.rampingcap, querystart, querydelta)
            setrhsterm!(p, getuprampingconid(trait), trait.id, t, value)
            setrhsterm!(p, getdownrampingconid(trait), trait.id, t, value)
        end
    end
    return
end

function update!(p::Prob, trait::HydroRamping, start::ProbTime)
    h = gethorizon(trait)

    if !isconstant(trait.rampingcap) || !hasconstantdurations(h)
        for t in 1:getnumperiods(h)
            querystart = getstarttime(h, t, start)
            querydelta = gettimedelta(h, t)
            value = getparamvalue(trait.rampingcap, querystart, querydelta)
            setrhsterm!(p, getuprampingconid(trait), trait.id, t, value)
            setrhsterm!(p, getdownrampingconid(trait), trait.id, t, value)
        end
    end
    return
end

function assemble!(trait::TransmissionRamping)
    isnothing(gethorizon(trait.firstflow)) && return false
    isnothing(gethorizon(trait.secondflow)) && return false
    @assert gethorizon(trait.firstflow) == gethorizon(trait.secondflow)
    return true
end

assemble!(trait::HydroRampingWithout) = !isnothing(gethorizon(trait.flow))
assemble!(trait::HydroRamping) = !isnothing(gethorizon(trait.flow))

# ------ Include dataelements -------

# NB! Note special handeling of deps in order to support good error messages in these funcs

function includeTransmissionRamping!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)
    checkkey(toplevel, elkey)

    deps = Id[]
    
    firstflowname = getdictvalue(value, "FirstFlow", String, elkey)
    firstflowkey = Id(FLOW_CONCEPT, firstflowname)
    push!(deps, firstflowkey)

    secondflowname = getdictvalue(value, "SecondFlow", String, elkey)
    secondflowkey = Id(FLOW_CONCEPT, secondflowname)
    push!(deps, secondflowkey)

    early_ret = false

    if haskey(toplevel, firstflowkey)
        firstflow = toplevel[firstflowkey]
        if isnothing(getub(firstflow)) 
            early_ret = true
            s = "Missing upper bound in $firstflow for $elkey"
            deps = ([s], deps)
        end
    else
        early_ret = true
    end

    if haskey(toplevel, secondflowkey)
        secondflow = toplevel[secondflowkey]
        if isnothing(getub(secondflow)) 
            early_ret = true
            s = "Missing upper bound in $secondflow for $elkey"
            if deps isa Tuple
                push!(deps[1], s)
            else
                deps = ([s], deps)
            end
        end
    else
        early_ret = true
    end

    early_ret && return (false, deps)

    rampingpercentage = ConstantParam(getdictvalue(value, "RampingPercentage", Real, elkey))
    flowcap = getub(firstflow).param
    maxflowcap = MWToGWhSeriesParam(flowcap.level, ConstantTimeVector(1.0))
    rampingcap = TwoProductParam(maxflowcap, rampingpercentage)

    objkey = getobjkey(elkey)

    toplevel[objkey] = TransmissionRamping(objkey, firstflow, secondflow, rampingcap)
    
    return (true, deps)
 end

 function includeHydroRampingWithout!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)
    checkkey(toplevel, elkey)

    deps = Id[]
    
    flowname = getdictvalue(value, FLOW_CONCEPT, String, elkey)
    flowkey = Id(FLOW_CONCEPT, flowname)

    early_ret = false

    if haskey(toplevel, flowkey)
        flow = toplevel[flowkey]
        if isnothing(getub(flow))
            early_ret = true
            s = "Missing upper bound in $flow for $elkey"
            deps = ([s], deps)
        end
    else
        early_ret = true
    end

    early_ret && return (false, deps)

    rampingpercentage = ConstantParam(getdictvalue(value, "RampingPercentage", Real, elkey))
    flowcap = getub(flow).param
    maxflowcap = M3SToMM3SeriesParam(flowcap.level, ConstantTimeVector(1.0))
    rampingcap = TwoProductParam(maxflowcap, rampingpercentage)

    objkey = getobjkey(elkey)

    toplevel[objkey] = HydroRampingWithout(objkey, flow, rampingcap)
    
    return (true, deps)
 end

 function includeHydroRamping!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)
    checkkey(toplevel, elkey)

    deps = Id[]
    
    flowname = getdictvalue(value, FLOW_CONCEPT, String, elkey)
    flowkey = Id(FLOW_CONCEPT, flowname)

    early_ret = false

    if haskey(toplevel, flowkey)
        flow = toplevel[flowkey]
        if isnothing(getub(flow))
            early_ret = true
            s = "Missing upper bound in $flow for $elkey"
            deps = ([s], deps)
        end
    else
        early_ret = true
    end

    early_ret && return (false, deps)

    rampingpercentage = ConstantParam(getdictvalue(value, "RampingPercentage", Real, elkey))
    flowcap = getub(flow).param
    maxflowcap = M3SToMM3SeriesParam(flowcap.level, ConstantTimeVector(1.0))
    rampingcap = TwoProductParam(maxflowcap, rampingpercentage)

    objkey = getobjkey(elkey)

    toplevel[objkey] = HydroRamping(objkey, flow, rampingcap)
    
    return (true, deps)
 end

INCLUDEELEMENT[TypeKey(RAMPING_CONCEPT, "TransmissionRamping")] = includeTransmissionRamping!
INCLUDEELEMENT[TypeKey(RAMPING_CONCEPT, "HydroRampingWithout")] = includeHydroRampingWithout!
INCLUDEELEMENT[TypeKey(RAMPING_CONCEPT, "HydroRamping")] = includeHydroRamping!