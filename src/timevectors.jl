"""
We implement several concrete TimeVectors.
Supports isconstant() and getweightedaverage()
- getweightedaverage() outputs the weighted average of the TimeVector
from a starting time and over a timedelta
- getweightedaverage() is implemented for different TimeDeltas

ConstantTimeVector contains a single value

RotatingTimeVector contains a time-series. When we get to the end of the
time-series we reuse it (therefore rotating)
Start and stop indicates which part of the timeseries should be used
Uses getsimilardatetime() to find values for a problem time which is 
not necessarily inside the range of the time-series
Used for profile i.e wind profile from 1981-2010

InfiniteTimeVector contains a time-series that represents the
value at a given problem time (infinite because it does not rotate)
Used for level i.e. installed wind capacity in 2021, 2030, 2040 and 2050

Building blocks of the TimeVectors above are also included from the DataElements.
These are commented at the end. These are also stored in lowlevel.

TODO: We can use the time-series more efficiently
- If data points have constant distance between them, we can make a more 
efficient getweightedaverage that takes advantage of this
- Many objects can get data from the same time-series. Instead of the same calculations
being done several times, we could store the results in a intermediate storage
- We could store the index of the previous time-series query, to quicker look up
the next value
"""

# ----- Concrete types -----------
struct ConstantTimeVector <: TimeVector
    value::Float64
end

mutable struct InfiniteTimeVector{I, V} <: TimeVector
    index::I
    values::V
end

struct RotatingTimeVector{I, V} <: TimeVector
    index::I
    values::V
    start::DateTime
    stop::DateTime
    function RotatingTimeVector(index, values, start, stop)
        # Only keep indexes and values inside of [start, stop]
        istart = searchsortedfirst(index, start)
        istop  = searchsortedlast(index, stop)
        i = @view index[istart:istop]
        v = @view values[istart:istop]
        new{typeof(i), typeof(v)}(i, v, start, stop)
    end
end

# ---- General functions -----------
isconstant(::ConstantTimeVector) = true
isconstant(::InfiniteTimeVector) = false
isconstant(::RotatingTimeVector) = false

getweightedaverage(x::ConstantTimeVector, ::DateTime, ::TimeDelta) = x.value
getweightedaverage(x::ConstantTimeVector, ::DateTime, ::UnitsTimeDelta) = x.value

function getweightedaverage(x::TimeVector, start::DateTime, delta::UnitsTimeDelta)
    count = 0
    value = 0.0
    for unit_range in delta.units
        num_units = length(unit_range)
        querystart = start + delta.unit_duration * (first(unit_range) - 1)
        querydelta = MsTimeDelta(delta.unit_duration * num_units)
        value += getweightedaverage(x, querystart, querydelta) * num_units
        count += num_units
    end
    return value / count
end

function getweightedaverage(x::InfiniteTimeVector, t::DateTime, delta::MsTimeDelta)
    values = x.values
    index = x.index

    T = eltype(values)

    qstart = t
    qstop  = t + getduration(delta)
    
    istart = searchsortedlast(index, qstart)
    istop  = searchsortedlastlo(index, qstop, max(istart, 1))

    (istart == istop == 0             ) && return first(values)
    (istart == istop == length(values)) && return last(values)
    (istart == istop)                   && return values[istop]
    ((istart == 0) && (istop == 1))     && return values[istop]
        
    if istart == 0
        istart = 1
        tstart = first(index)
        d = T((tstart - qstart).value)
        x = first(values) * d
        n = d
    else
        tstart = index[istart]
        x = zero(T)
        n = zero(T)
    end
    
    tstop = index[istop]

    @inbounds for i in istart:(istop-1)
        d = T((index[i+1] - index[i]).value)
        x += values[i] * d
        n += d
    end 
    
    if qstart > tstart
        d = T((qstart - tstart).value)
        x -= @inbounds values[istart] * d
        n -= d
    end
    
    if qstop > tstop
        d = T((qstop - tstop).value)
        x += @inbounds values[istop] * d
        n += d    
    end
    
    avg = x / n
    
    return avg
end

function getweightedaverage(x::RotatingTimeVector, t::DateTime, delta::MsTimeDelta)
    # Get some variables
    index = x.index
    values = x.values
    lb = x.start
    ub = x.stop
    t0 = first(index)
    tN = last(index)
    x0 = first(values)
    xN = last(values)

    T = eltype(values)

    # Find tininterval = t in [lb, ub]
    if t < lb
        gap = lb - t
        interval = ub - lb
        shifts = Int(ceil(gap.value / interval.value))
        tininterval = t + (interval * shifts)
        tininterval = getsimilardatetime(t, getisoyear(tininterval))

    elseif t > ub
        gap = t - ub
        interval = ub - lb
        shifts = Int(ceil(gap.value / interval.value))
        tininterval = t - (interval * shifts)
        tininterval = getsimilardatetime(t, getisoyear(tininterval))    # can result in tininterval > ub
        if tininterval > ub
            tininterval = tininterval - interval
            tininterval = getsimilardatetime(t, getisoyear(tininterval)) 
        end
    
    else
        tininterval = t
    end

    # Ensure tininterval = t in [lb, ub)
    if tininterval == ub
        tininterval = lb
    end

    # Start alg
    qstart = tininterval
    qstop  = tininterval + getduration(delta)

    istart = searchsortedlast(index, qstart)
    istop  = searchsortedlastlo(index, qstop, istart) # Can cause stability issues? Solution?: searchsortedlastlo(index, qstop, max(istart, 1)) like for getweightedaverage(::InfiniteTimeVector)
    
    # Return early if possible
    (istart == istop == 0)            && return xN # use xN for [lb, t0] and [tN, ub]
    (istart == istop)                 && return values[istop]
    
    # correct for qstart and ensure inbounds
    if istart == 0
        istart = 1
        tstart = t0
        d = T((tstart - qstart).value)
        x = xN * d # use xN for [lb, t0] and [tN, ub]   
        n = d
    else
        tstart = index[istart]
        x = zero(T)
        n = zero(T)       
        if qstart > tstart
            d = T((qstart - tstart).value)
            x -= @inbounds values[istart] * d
            n -= d
        end
    end
    
    tstop = index[istop]

    # No rotation (usually the case)
    if qstop <= ub + (t0 - lb)
        # Add chunk
        @inbounds for i in istart:(istop-1)
            d = T((index[i+1] - index[i]).value)
            x += values[i] * d
            n += d
        end         

        # Add remainder
        if qstop > tstop
            d = T((qstop - tstop).value)
            x += @inbounds values[istop] * d
            n += d    
        end
        
        return x / n
    end

    # Rotate once (sometimes the case)
    if qstop <= ub + (t0 - lb) + (ub - lb)
        # Since we are here we know qstop > tN
        # @assert length(index) == istop

        # Add chunk to tN
        @inbounds for i in istart:(istop-1)
            d = T((index[i+1] - index[i]).value)
            x += values[i] * d
            n += d
        end    

        # Use xN for intervals # use xN for [lb, t0] and [tN, ub]
        d = T((ub - tstop).value + (t0 - lb).value)
        x += xN * d
        n += d    

        # We rotate by updating so that we start at t0
        # Update tstop by subtracting already covered intervals
        tstart = t0
        istart = 1

        tstop = qstop - (ub - qstart) + (t0 - lb)
        istop = searchsortedlast(index, tstop)
        
        # Add remainding chunk
        @inbounds for i in istart:(istop-1)
            d = T((index[i+1] - index[i]).value)
            x += values[i] * d
            n += d
        end    

        # Add remainder
        if qstop > tstop
            d = T((qstop - tstop).value)
            x += @inbounds values[istop] * d
            n += d    
        end
        
        return x / n
    end

    # Rotate many (teoretical corner case)
    numintervals::T = floor((qstop - ub + lb - t0).value / (ub - lb).value)
    
    # Calculate values for whole interval once
    intervalx = zero(T)
    intervaln = zero(T)
    @inbounds for i in 1:(length(index)-1)
        d = T((index[i+1] - index[i]).value)
        intervalx += values[i] * d
        intervaln += d
    end
    d = T((ub - tN).value + (t0 - lb).value)
    intervalx += xN * d
    intervaln += d    

    # Since we are here we know qstop > tN
    # @assert length(index) == istop

    # Add chunk to tN
    @inbounds for i in istart:(istop-1)
        d = T((index[i+1] - index[i]).value)
        x += values[i] * d
        n += d
    end    

    # Use xN for intervals [lb, t0] and [tN, ub]
    d = T((ub - tstop).value + (t0 - lb).value)
    x += xN * d
    n += d   
    
    # Add whole intervals
    x += (intervalx * numintervals)
    n += (intervaln * numintervals)

    # Do remainders

    # We rotate by updating so that we start at t0
    # Update tstop by subtracting already covered intervals
    tstart = t0
    istart = 1

    tstop = qstop - (ub - qstart) - (t0 - lb) - (Int(numintervals) * (ub - lb)) 
    istop = searchsortedlast(index, tstop)
    
    # Add remainding chunk
    @inbounds for i in istart:(istop-1)
        d = T((index[i+1] - index[i]).value)
        x += values[i] * d
        n += d
    end    

    # Add remainder
    if qstop > tstop
        d = T((qstop - tstop).value)
        x += @inbounds values[istop] * d
        n += d    
    end
    
    return x / n
end

function _isdifferent(index, values)
    try
        return length(index) == length(values)
    catch
        return length(collect(index)) == length(values)
    end
end
# TODO: Probably move checks to constructor

# More effective searching for special types
# - When Vector is a StepRange we can calculate the index
# - searchsortedlastlo does not search through the the whole Vector, but starts from istart
# - TODO: Test different search algorithms

using Base.Order
import Base.searchsortedlast

function searchsortedlastlo(v::AbstractVector, x, lo::T, hi::T, o::Ordering)::keytype(v) where T<:Integer
    u = T(1)
    lo = lo - u
    hi = hi + u
    @inbounds while lo < hi - u
        m = midpoint(lo, hi)
        if lt(o, x, v[m])
            hi = m
        else
            lo = m
        end
    end
    return lo
end

midpoint(lo::T, hi::T) where T<:Integer = lo + ((hi - lo) >>> 0x01)
searchsortedlastlo(v::AbstractVector, x, lo, o::Ordering) = searchsortedlastlo(v,x,lo,lastindex(v),o)
searchsortedlastlo(v::AbstractVector, x, lo;
    lt=isless, by=identity, rev::Union{Bool,Nothing}=nothing, order::Ordering=Forward) = searchsortedlastlo(v,x,lo,ord(lt,by,rev,order))

function searchsortedlastlo(v::StepRange, x, lo)::keytype(v)
    if x > last(v)
        return lastindex(v)
    else
        return floor((x-v.start)/v.step) + 1
    end
end

function searchsortedlast(v::StepRange, x)::keytype(v)
    if x > last(v)
        return lastindex(v)
    else   
        return max(floor((x-v.start)/v.step) + 1, 0)
    end
end

"""
Here we register functions to include data elements relating to TimeVector
"""

# --- VectorTimeIndex ---
# TimeIndex described by a Vector
function includeVectorTimeIndex!(::Dict, lowlevel::Dict, elkey::ElementKey, value::AbstractVector{DateTime})::Bool
    checkkey(lowlevel, elkey)
    length(value) > 0  || error("Vector has no elements for $elkey")
    issorted(value)    || error(     "Vector not sorted for $elkey")
    lowlevel[getobjkey(elkey)] = value
    return true
end

function includeVectorTimeIndex!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    vector = getdictvalue(value, "Vector", AbstractVector{DateTime}, elkey)
    includeVectorTimeIndex!(toplevel, lowlevel, elkey, vector)
end

# --- RangeTimeIndex ---
# TimeIndex described by a StepRange.
function includeRangeTimeIndex!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    start  = getdictvalue(value, "Start", DateTime, elkey)
    steps  = getdictvalue(value, "Steps", Int,      elkey) 
    delta  = getdictvalue(value, "Delta", Union{Period, String},   elkey)

    if delta isa String 
        deltakey = Id(TIMEDELTA_CONCEPT, delta)
        haskey(lowlevel, deltakey) || return false
        delta = getduration(lowlevel[deltakey])
    end
    
    delta = Millisecond(delta)
    
    steps > 0              || error(             "Steps <= 0 for $elkey")
    delta > Millisecond(0) || error("Delta <= Millisecond(0) for $elkey")
    
    lowlevel[getobjkey(elkey)] = StepRange(start, delta, start + delta * (steps-1))
    return true
end

function includeRangeTimeIndex!(::Dict, lowlevel::Dict, elkey::ElementKey, value::StepRange{DateTime, Millisecond})::Bool
    checkkey(lowlevel, elkey)
    value.step > Millisecond(0) || error("Delta <= Millisecond(0) for $elkey")
    lowlevel[getobjkey(elkey)] = value
    return true
end

# --- VectorTimeValues ---
# TimeValues described by a Vector
function includeVectorTimeValues!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    vector = getdictvalue(value, "Vector", AbstractVector{<:AbstractFloat}, elkey)
    
    length(vector) > 0  || error("Vector has no elements for $elkey")
    
    lowlevel[getobjkey(elkey)] = vector
    return true
end

# ----- BaseTable -----
# Stores multiple VectorTimeValues together
# Dictionary with a matrix and a list of column names
# Rows in the matrix represents a TimeIndex and the columns are connected 
# to the name list (each representing a VectorTimeValues)
function includeBaseTable!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    matrix = getdictvalue(value, "Matrix", AbstractMatrix{<:AbstractFloat}, elkey)
    names  = getdictvalue(value, "Names",  Vector{String},                  elkey)
    
    length(names) > 0                  || error(                         "No names for $elkey")
    length(names) > last(size(matrix)) && error("More names than columns in matrix for $elkey")
    length(names) < last(size(matrix)) && error("More columns in matrix than names for $elkey")
    length(names) > length(Set(names)) && error(                  "Duplicate names for $elkey")
    
    lowlevel[getobjkey(elkey)] = value
    return true
end

# --- ColumnTimeValues ---
# VectorTimeValues that gets its data from a BaseTable
function includeColumnTimeValues!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    columnname = getdictvalue(value, "Name",        String, elkey)
    tablename  = getdictvalue(value, TABLE_CONCEPT, String, elkey)
    
    tablekey = Id(TABLE_CONCEPT, tablename)
    haskey(lowlevel, tablekey) || return false
    
    table = lowlevel[tablekey]
    
    matrix = table["Matrix"]
    names  = table["Names"]
    
    columnname in names || error("Name $columnname not in table $table for $elkey")
    
    columnindex = findfirst(x -> x == columnname, names)
    
    lowlevel[getobjkey(elkey)] = view(matrix, :, columnindex)

    return true
end


# --- RotatingTimeVector ---
function includeRotatingTimeVector!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    indexname  = getdictvalue(value, TIMEINDEX_CONCEPT,  String, elkey)
    valuesname = getdictvalue(value, TIMEVALUES_CONCEPT, String, elkey)
    
    indexkey  = Id(TIMEINDEX_CONCEPT,  indexname)
    valueskey = Id(TIMEVALUES_CONCEPT, valuesname)

    # Assumes typename == instancename
    periodkey = Id(TIMEPERIOD_CONCEPT, "ScenarioTimePeriod")
    
    haskey(lowlevel, indexkey)   || return false
    haskey(lowlevel, valueskey)  || return false
    haskey(lowlevel, periodkey)  || return false
    
    index  = lowlevel[indexkey]
    values = lowlevel[valueskey]
    period = lowlevel[periodkey]

    _isdifferent(index, values) || error("Different length for index and values for $elkey")
    
    start = period["Start"]
    stop  = period["Stop"]
    
    # TODO: Use view into values and index if first(ix) < Start or last(ix) > Stop
    # TODO: Validate that index cover the period
    
    lowlevel[getobjkey(elkey)] = RotatingTimeVector(index, values, start, stop)
    return true
end

# --- OneYearTimeVector ---
# A RotatingTimeVector with one year of data
function includeOneYearTimeVector!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    indexname  = getdictvalue(value, TIMEINDEX_CONCEPT,  String, elkey)
    valuesname = getdictvalue(value, TIMEVALUES_CONCEPT, String, elkey)
    
    indexkey  = Id(TIMEINDEX_CONCEPT,  indexname)
    valueskey = Id(TIMEVALUES_CONCEPT, valuesname)

    haskey(lowlevel, indexkey)   || return false
    haskey(lowlevel, valueskey)  || return false
    
    index  = lowlevel[indexkey]
    values = lowlevel[valueskey]

    isoyear = getisoyear(first(index))

    issameisoyear = isoyear == getisoyear(last(index))
    issameisoyear || error("More than one year in index for $elkey")
    
    _isdifferent(index, values) || error("Different length for index and values for $elkey")

    start = getisoyearstart(isoyear)
    stop  = getisoyearstart(isoyear + 1)
    
    lowlevel[getobjkey(elkey)] = RotatingTimeVector(index, values, start, stop)
    return true
end

# --- InfiniteTimeVector ---
function includeInfiniteTimeVector!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    indexname  = getdictvalue(value, TIMEINDEX_CONCEPT,  String, elkey)
    valuesname = getdictvalue(value, TIMEVALUES_CONCEPT, String, elkey)
    
    indexkey  = Id(TIMEINDEX_CONCEPT,  indexname)
    valueskey = Id(TIMEVALUES_CONCEPT, valuesname)
    
    haskey(lowlevel, indexkey)   || return false
    haskey(lowlevel, valueskey)  || return false
    
    index  = lowlevel[indexkey]
    values = lowlevel[valueskey]

    _isdifferent(index, values) || error("Different length for index and values for $elkey")
    
    lowlevel[getobjkey(elkey)] = InfiniteTimeVector(index, values)
    
    return true
end

# --- ConstantTimeVector ---
function includeConstantTimeVector!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    constant = getdictvalue(value, "Value",  AbstractFloat, elkey)
    lowlevel[getobjkey(elkey)] = ConstantTimeVector(constant)
    return true
end

function includeConstantTimeVector!(::Dict, lowlevel::Dict, elkey::ElementKey, value::AbstractFloat)::Bool
    checkkey(lowlevel, elkey)
    lowlevel[getobjkey(elkey)] = ConstantTimeVector(value)
    return true
end

function includeConstantTimeVector!(::Dict, lowlevel::Dict, elkey::ElementKey, value::ConstantTimeVector)::Bool
    checkkey(lowlevel, elkey)
    lowlevel[getobjkey(elkey)] = value
    return true
end

INCLUDEELEMENT[TypeKey(TIMEINDEX_CONCEPT, "RangeTimeIndex")] = includeRangeTimeIndex!
INCLUDEELEMENT[TypeKey(TIMEINDEX_CONCEPT, "VectorTimeIndex")] = includeVectorTimeIndex!

INCLUDEELEMENT[TypeKey(TABLE_CONCEPT, "BaseTable")] = includeBaseTable!

INCLUDEELEMENT[TypeKey(TIMEVALUES_CONCEPT, "VectorTimeValues")] = includeVectorTimeValues!
INCLUDEELEMENT[TypeKey(TIMEVALUES_CONCEPT, "ColumnTimeValues")] = includeColumnTimeValues!

INCLUDEELEMENT[TypeKey(TIMEVECTOR_CONCEPT, "RotatingTimeVector")] = includeRotatingTimeVector!
INCLUDEELEMENT[TypeKey(TIMEVECTOR_CONCEPT, "InfiniteTimeVector")] = includeInfiniteTimeVector!
INCLUDEELEMENT[TypeKey(TIMEVECTOR_CONCEPT, "ConstantTimeVector")] = includeConstantTimeVector!
INCLUDEELEMENT[TypeKey(TIMEVECTOR_CONCEPT, "OneYearTimeVector")]  = includeOneYearTimeVector!

