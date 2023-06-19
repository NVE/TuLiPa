"""
Metadata is an extra field in the main objects (Flow, Storage, Balance)
that can store extra information about the objects in a dictionary
This extra information can be used in the object manipulation before
running the model or in the result handling
This was added to give the user a possibility to include external
information into the modelobjects

We include Storagehint, which holds information about how long it
takes to empty the reservoir with full production. This can be used
to remove short-term storage systems from the model, if the model is
run for a coarse horizon

We include Residualhint, which says if the RHSTerm should be included
when calculating the residual load. See AdaptiveHorizon for how the 
residual load is used to make a Horizon.

We include ReservoirCurve, which holds information about the relationship
between the head to reservoir filling curve for a hydropower storage. It
fills the gap with interpolation.

We include ProductionInfo, which holds the nominal head and outlet level
of a hydropower plant. Only has data for plants with a upper reservoir
that has a reservoir curve. Else nominal head = 0 and outlet level = -1.

We include HydraulicHint, which tells if a hydrobalance is behind and 
restricting two production units as a hydraulic coupling.

We include GlobalEneq, which holds the global energy equivalent of a
hydrobalance. Can be used to find the global energy equivalent of 
inflow (RHSTerm to Balance) or for a reservoir that belongs to the balance.

TODO: Add metadata for all objects?
"""

# ------ Include dataelements -------
function includeStoragehint!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)::Bool
    storagename = getdictvalue(value, STORAGE_CONCEPT, String, elkey)
    storagekey = Id(STORAGE_CONCEPT, storagename)
    haskey(toplevel, storagekey) || return false

    storage = toplevel[storagekey]

    period = getdictvalue(value, "Period", Union{Period, Int}, elkey)
    period isa Nanosecond && error("Nanosecond not allowed for $elkey")
    period = Millisecond(period)
    period > Millisecond(0) || error("Period <= Millisecond(0) for $elkey")
    period = MsTimeDelta(period)

    setmetadata!(storage, STORAGEHINTKEY, period)
    
    return true    
end

function includeResidualhint!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool    
    rhsname = getdictvalue(value, RHSTERM_CONCEPT, String, elkey)
    rhskey = Id(RHSTERM_CONCEPT, rhsname)
    haskey(lowlevel, rhskey) || return false

    rhsterm = lowlevel[rhskey]

    residual = getdictisresidual(value, elkey)

    setmetadata!(rhsterm, RESIDUALHINTKEY, residual)
    
    return true    
end

function includeReservoirCurve!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)::Bool
    storagename = getdictvalue(value, STORAGE_CONCEPT, String, elkey)
    storagekey = Id(STORAGE_CONCEPT, storagename)
    haskey(toplevel, storagekey) || return false

    storage = toplevel[storagekey]
    
    res = getdictvalue(value, "Res", Vector{Float64}, elkey)
    head = getdictvalue(value, "Head", Vector{Float64}, elkey)

    rescurve = XYCurve(res,head)
    setmetadata!(storage, RESERVOIRCURVEKEY, rescurve)

    return true
end

function includeProductionInfo!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)::Bool
    flowname = getdictvalue(value, FLOW_CONCEPT, String, elkey)
    flowkey = Id(FLOW_CONCEPT, flowname)
    haskey(toplevel, flowkey) || return false

    flow = toplevel[flowkey]
    
    outlet = getdictvalue(value, OUTLETLEVELKEY, Float64, elkey) # better word than outlet level?
    head = getdictvalue(value, NOMINALHEADKEY, Float64, elkey)

    setmetadata!(flow, OUTLETLEVELKEY, outlet)
    setmetadata!(flow, NOMINALHEADKEY, head)

    return true
end

function includeHydraulichint!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)::Bool
    balancename = getdictvalue(value, BALANCE_CONCEPT, String, elkey)
    balancekey = Id(BALANCE_CONCEPT, balancename)
    haskey(toplevel, balancekey) || return false

    balance = toplevel[balancekey]
    
    code = getdictvalue(value, "Code", Float64, elkey) 

    setmetadata!(balance, HYDRAULICHINTKEY, code)

    return true
end

function includeGlobalEneq!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)::Bool
    balancename = getdictvalue(value, BALANCE_CONCEPT, String, elkey)
    balancekey = Id(BALANCE_CONCEPT, balancename)
    haskey(toplevel, balancekey) || return false

    balance = toplevel[balancekey]
    
    globaleneq = getdictvalue(value, "Value", Float64, elkey) # TODO: Shold be a Param

    setmetadata!(balance, GLOBALENEQKEY, globaleneq)

    return true
end

INCLUDEELEMENT[TypeKey(METADATA_CONCEPT, RESIDUALHINTKEY)] = includeResidualhint!
INCLUDEELEMENT[TypeKey(METADATA_CONCEPT, STORAGEHINTKEY)] = includeStoragehint!
INCLUDEELEMENT[TypeKey(METADATA_CONCEPT, RESERVOIRCURVEKEY)] = includeReservoirCurve!
INCLUDEELEMENT[TypeKey(METADATA_CONCEPT, PRODUCTIONINFOKEY)] = includeProductionInfo!
INCLUDEELEMENT[TypeKey(METADATA_CONCEPT, HYDRAULICHINTKEY)] = includeHydraulichint!
INCLUDEELEMENT[TypeKey(METADATA_CONCEPT, GLOBALENEQKEY)] = includeGlobalEneq!
