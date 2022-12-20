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

INCLUDEELEMENT[TypeKey(METADATA_CONCEPT, RESIDUALHINTKEY)] = includeResidualhint!
INCLUDEELEMENT[TypeKey(METADATA_CONCEPT, STORAGEHINTKEY)] = includeStoragehint!
