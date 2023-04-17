"""
We implement TransmissionRamping (also see abstracttypes.jl)
This is ramping restriction for both up and down-ramping on a transmission line. 
The transmission is represented by two flows, one for each direction.
Ramping capacity input is percentage of max capacity of one of the flows (TODO: Make version where up and downramping is different?)
- Assumes that the flow capacity is a MWToGWhSeriesParam with a level and a profile (TODO?)

Internal variables: sumtransmission (sum of tranmsission in both directions, and has state variables)
Equations restricting the internal variable:
sumtransmission[t] = secondflow[t] - firstflow[t]
(d/dt) sumtransmission[t] <= rampingcap[t] (upramping)
- (d/dt) sumtransmission[t] <= rampingcap[t] for t > 1 (downramping)
"""

# ------- Concrete type --------------------
mutable struct TransmissionRamping <: Ramping
    id::Id
    firstflow::Flow
    secondflow::Flow
    rampingcap::Param
end

# ------- Interface functions ----------------
getid(trait::TransmissionRamping) = trait.id
gethorizon(trait::TransmissionRamping) = gethorizon(trait.firstflow)

# Assumes firstflow and secondflow are always in the same system and will be grouped together
# TODO: Replace with getobjects, more robust
# getobjects(trait::TransmissionRamping) = [trait.firstflow, trait.secondflow]
getparent(trait::TransmissionRamping) = trait.firstflow

# TransmissionRamping needs internal state variables for ramping
# x[T] (var_out) is part of the ramping variable while x[0] (var_in) has to be named and built seperately
function getstatevariables(trait::TransmissionRamping)
    var_in_id = getstartsumtransmissionvarid(trait)
    var_out_id = getsumtransmissionvarid(trait)
    var_out_ix = getnumperiods(gethorizon(trait))
    info = StateVariableInfo((var_in_id, 1), (var_out_id, var_out_ix))
    return [info]
end

# TransmissionRamping creates variables and equations that needs ids/names
function getstartsumtransmissionvarid(trait::TransmissionRamping)
    Id(getconceptname(trait.id), "StartSumTransmission" * getinstancename(trait.id))
end

function getsumtransmissionvarid(trait::TransmissionRamping)
    Id(getconceptname(trait.id), "SumTransmission" * getinstancename(trait.id))
end

function getsumtransmissionconid(trait::TransmissionRamping)
    Id(getconceptname(trait.id), "SumTransmissionCon" * getinstancename(trait.id))
end

function getuprampingconid(trait::TransmissionRamping)
    Id(getconceptname(trait.id), "UpRampingCon" * getinstancename(trait.id))
end

function getdownrampingconid(trait::TransmissionRamping)
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

# TransmissionRamping types are toplevel objects in dataset_compiler, so we must implement assemble!
function assemble!(trait::TransmissionRamping)

    # return if flows not assembled yet
    isnothing(gethorizon(trait.firstflow)) && return false
    isnothing(gethorizon(trait.secondflow)) && return false

    # check that horizons are the same in the two flows
    @assert gethorizon(trait.firstflow) == gethorizon(trait.secondflow)

    return true
end

# ------ Include dataelements -------
function includeTransmissionRamping!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(toplevel, elkey)
    
    firstflowname = getdictvalue(value, "FirstFlow", String, elkey)
    firstflowkey = Id(FLOW_CONCEPT, firstflowname)
    haskey(toplevel, firstflowkey) || return false
    secondflowname = getdictvalue(value, "SecondFlow", String, elkey)
    secondflowkey = Id(FLOW_CONCEPT, secondflowname)
    haskey(toplevel, secondflowkey) || return false

    firstflow = toplevel[firstflowkey]
    secondflow = toplevel[secondflowkey]
    isnothing(getub(firstflow)) && return false
    isnothing(getub(secondflow)) && return false

    rampingpercentage = ConstantParam(getdictvalue(value, "RampingPercentage", Real, elkey))
    flowcap = getub(firstflow).param
    maxflowcap = MWToGWhSeriesParam(flowcap.level, ConstantTimeVector(1.0))
    rampingcap = TwoProductParam(maxflowcap, rampingpercentage)

    objkey = getobjkey(elkey)

    toplevel[objkey] = TransmissionRamping(objkey, firstflow, secondflow, rampingcap)
    
    return true
 end

INCLUDEELEMENT[TypeKey(RAMPING_CONCEPT, "TransmissionRamping")] = includeTransmissionRamping!