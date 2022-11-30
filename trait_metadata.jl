function includeStoragehint!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(toplevel, elkey)
    
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

INCLUDEELEMENT[TypeKey(METADATA_CONCEPT, STORAGEHINTKEY)] = includeStoragehint!
