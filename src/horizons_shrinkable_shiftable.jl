"""
We define ShrinkableHorizon and ShiftableHorizon, and add support for these for SequentialHorizon or AdaptiveHorizon. 
The system can be extended to support other Horizon types as well.

This file extends the Horizon interface with two new functions (mayshiftfrom and mustupdate) which
can be used to significantly reduce update time in certain cases, when used with ShrinkableHorizon and ShiftableHorizon.

ShrinkableHorizon wraps another Horizon and modifies it through updates in a way that keeps most of 
the horizon (except a few periods in the front) unchanged for several updates. This is done by shrinking 
the duration of certain periods on each update. The unchanged periods does not need updating, thus saving update time. 
Warm starting with simplex methods may also improve because only a fraction of the parameters have changed. 
Periodically, the shrinked periods must be reset, and all periods of the horizon must be updated. 
In this case, fast shift updates (described in more detail below) are used if applicable. This horizon type is useful 
for long horizons (e.g. 6 years) with long periods (e.g. 6 weeks) for which parameter values are expensive to compute. 

ShiftableHorizon wraps another Horizon and can enable fast updates by saying that a period t can use data from period future_t. 
This way, one can reuse stored data to update Horizon or LP problem. This can be much faster than computing the parameter value 
from a Param object.

Below is ShrinkableHorizon exemplified in a forward simulation model. The Horizon is a SequentialHorizon with 6 periods of 4 weeks.
When the simulation moves 2 weeks forward to the second step, the duration of the first period is halved (to the duration of 
the minperiod, which is also 2 weeks). Parameters in periods 2-6 does not need to be updated, and can be reused from the previous 
simulation step. In step 3 periods 3-6 does not need to be updated, and in step 4 periods 4-6 does not need to be updated.
At step 4 we have reached the limit of how much we wanted to shrink the horizon (shrinkatleast, which is 6 weeks). In step 5 we
therefore reset the period duration of steps 1-3. We also take advantage of fast shift updates since periods 4-6 in step 4
corresponds to periods 2-4 in step 5. 

Step = 1
Periods:     1         2         3         4         5         6
        |---- ----|---- ----|---- ----|---- ----|---- ----|---- ----|
Step = 2
Periods:       1       2         3         4         5         6
             |----|---- ----|---- ----|---- ----|---- ----|---- ----|
Step = 3
Periods:            1    2       3         4         5         6
                  |----|----|---- ----|---- ----|---- ----|---- ----|
Step = 4
Periods:                 1    2    3       4         5         6
                       |----|----|----|---- ----|---- ----|---- ----|
Step = 5                      
Periods:                         1         2         3         4         5         6
                            |---- ----|---- ----|---- ----|---- ----|---- ----|---- ----|
Step = 6                      
Periods:                           1       2         3         4         5         6
                                 |----|---- ----|---- ----|---- ----|---- ----|---- ----|

The way to use the mayshiftfrom and mustupdate functions, which must be used together, is to do two passes 
over all periods in the horizon. In the first pass you use shift updates if mayshiftfrom says ok.
In the second pass you use mustupdate to tell which remaining periods to update. Below is an example for a cost parameter.

T = getnumperiods(horizon)
for t in 1:T
    (future_t, ok) = mayshiftfrom(horizon, t)
    if ok
        value = getobjcoeff(prob, id, future_t)
        setobjcoeff!(prob, id, t, value)
    end
end
for t in 1:T
    if mustupdate(horizon, t)
        querystart = getstarttime(horizon, t, start)
        querydelta = gettimedelta(horizon, t)
        value = getparamvalue(cost, querystart, querydelta)
        setobjcoeff!(prob, id, t, value)
    end
end

We have added generic fallbacks for mayshiftfrom and mustupdate, so the example code should work for any Horizon. 
However, horizons not supporting ShrinkableHorizon or ShiftableHorizon will not get any performance improvements. 

Warning! The example may be too simple for certain applications. E.g. some parameters may be stateful and thus change at every update. 
In this case, one should update all periods with getparamvalue. 
"""

const HORIZON_NOSHIFT = -1

# ---- Generic fallbacks ----

mayshiftfrom(::Horizon, ::Int) = (HORIZON_NOSHIFT, false)
mustupdate(::Horizon, ::Int) = true

# ---- ShrinkableHorizon and ShiftableHorizon ----

struct ShrinkableHorizon{H <: Horizon, S} <: Horizon
    subhorizon::H
    handler::S

    function ShrinkableHorizon(subhorizon::Horizon, startafter::Millisecond, shrinkatleast::Millisecond, minperiod::Millisecond)
        @assert !(subhorizon isa ShrinkableHorizon)
        @assert !(subhorizon isa ShiftableHorizon)
        handler = gethorizonshrinker(subhorizon, startafter, shrinkatleast, minperiod)
        makeshrinkable!(subhorizon, handler)
        new{typeof(subhorizon), typeof(handler)}(subhorizon, handler)
    end
end

struct ShiftableHorizon{H <: Horizon, S} <: Horizon
    subhorizon::H
    handler::S

    function ShiftableHorizon(subhorizon::Horizon)
        @assert !(subhorizon isa ShrinkableHorizon)
        @assert !(subhorizon isa ShiftableHorizon)
        handler = gethorizonshifter(subhorizon)
        new{typeof(subhorizon), typeof(handler)}(subhorizon, handler)
    end
end

const _SHorizons = Union{ShrinkableHorizon, ShiftableHorizon}

isadaptive(h::_SHorizons) = isadaptive(h.subhorizon)
getnumperiods(h::_SHorizons) = getnumperiods(h.subhorizon)
getstartduration(h::_SHorizons, t::Int) = getstartduration(h.subhorizon, t)
getendperiodfromduration(h::_SHorizons, d::Millisecond) = getendperiodfromduration(h.subhorizon, d)
getduration(h::_SHorizons) = getduration(h.subhorizon)
gettimedelta(h::_SHorizons, t::Int) = gettimedelta(h.subhorizon, t)
hasoffset(h::_SHorizons) = hasoffset(h.subhorizon)
getoffset(h::_SHorizons) = getoffset(h.subhorizon)
getstarttime(h::_SHorizons, t::Int, start::ProbTime) = getstarttime(h.subhorizon, t, start)
getsubperiods(coarse::_SHorizons, fine::Horizon, coarse_t::Int) = getsubperiods(coarse.subhorizon, fine, coarse_t)
getsubperiods(coarse::Horizon, fine::_SHorizons, coarse_t::Int) = getsubperiods(coarse, fine.subhorizon, coarse_t)
getsubperiods(coarse::_SHorizons, fine::_SHorizons, coarse_t::Int) = getsubperiods(coarse.subhorizon,fine.subhorizon,coarse_t)

hasconstantdurations(::ShrinkableHorizon) = false
hasconstantdurations(h::ShiftableHorizon) = hasconstantdurations(h.subhorizon)

build!(h::_SHorizons, p::Prob) = build!(h.subhorizon, h.handler, p)
function update!(h::_SHorizons, start::ProbTime)
    update!(h.subhorizon, h.handler, start)
end
mayshiftfrom(h::_SHorizons, t::Int)::Int = mayshiftfrom(h.subhorizon, h.handler, t)
mustupdate(h::_SHorizons, t::Int)::Bool = mustupdate(h.subhorizon, h.handler, t)

# Implementation of SequentialPeriodsShrinker and SequentialPeriodsShifter
# and extention of SequentialPeriods with new functions. These will be used
# to implement SequentialHorizonShrinker, AdaptiveHorizonShrinker, 
# SequentialHorizonShifter and AdaptiveHorizonShifter. These will in turn
# be used to make SequentialHorizon and AdaptiveHorizon shiftable and shrinkable.

mutable struct SequentialPeriodsShrinker
    shrinkperiods::UnitRange{Int}
    shrinkperiods_index::UnitRange{Int}
    shrinkperiods_isupdated::Vector{Bool}
    shrinkperiods_maxduration::Vector{Millisecond}
    minperiod::Millisecond
    updates_shift::Vector{Int}
    updates_must::Vector{Bool}
    last_shiftperiod::Int
    prev_start::Union{ProbTime, Nothing}
    remaining_duration::Millisecond
end

mutable struct SequentialPeriodsShifter
    updates_shift::Vector{Int}
    updates_must::Vector{Bool}
    prev_start::Union{ProbTime, Nothing}
end

const _SSequentialPeriods = Union{SequentialPeriodsShrinker, SequentialPeriodsShifter}

getms(p::SequentialPeriods, t) = getduration(gettimedelta(p, t))
getms(h::Horizon, t) = getduration(gettimedelta(p, t))

function gethorizonshrinker(h::SequentialPeriods, startafter::Millisecond, shrinkatleast::Millisecond, minperiod::Millisecond)    
    T = getnumperiods(h)
    
    shrinkperiods = getshrinkperiods(h, startafter, shrinkatleast, minperiod)

    shrinkperiods_index = 0:0    # set by makeshrinkable!
    
    shrinkperiods_isupdated = [false for __ in shrinkperiods]
    shrinkperiods_maxduration = [getms(h, t) for t in shrinkperiods]
    updates_shift = [HORIZON_NOSHIFT for t in 1:T]
    updates_must = [true for t in 1:T]

    last_shiftperiod = getlastshiftperiod(h, last(shrinkperiods))

    prev_start = nothing    # set by update!
    
    remaining_duration = sum(v - minperiod for v in shrinkperiods_maxduration)
    
    return SequentialPeriodsShrinker(
        shrinkperiods,
        shrinkperiods_index,
        shrinkperiods_isupdated,
        shrinkperiods_maxduration,
        minperiod,
        updates_shift,
        updates_must,
        last_shiftperiod,
        prev_start,
        remaining_duration)
end

function gethorizonshifter(h::SequentialPeriods)
    T = getnumperiods(h)
    updates_shift = [HORIZON_NOSHIFT for t in 1:T]
    updates_must = [true for t in 1:T]
    return SequentialPeriodsShifter(updates_shift, updates_must, nothing)
end

function getlastshiftperiod(h::SequentialPeriods, L::Int)
    T = getnumperiods(h)
    @assert 1 <= L <= T
    
    L >= (T - 1) && return HORIZON_NOSHIFT

    d1 = getms(h, L)
    d2 = getms(h, L+1) # only compatible with shift of one
    d1 != d2 && return HORIZON_NOSHIFT
    
    P = L+1
    for t in (L+2):(T-1)
        dt = getms(h, t)
        d1 != dt && return P  # only compatible with shift of one
        P = t
    end
    
    return P
end

function makeshrinkable!(p::SequentialPeriods, handler::SequentialPeriodsShrinker)
    makeshrinkable!(p, handler.shrinkperiods)

    first_shrinkperiod = first(handler.shrinkperiods)
    acc = 0
    for (i, (n, ms)) in enumerate(p.data)
        acc += n
        if acc == first_shrinkperiod
            handler.shrinkperiods_index = i:(i+length(handler.shrinkperiods)-1)
        end
    end

    # TODO: Replace checks with tests
    @assert first(handler.shrinkperiods_index) > 0
    @assert last(handler.shrinkperiods_index) < length(p.data)
    @assert first(handler.shrinkperiods_index) <= last(handler.shrinkperiods_index)
    for i in handler.shrinkperiods_index
        (n, ms) = p.data[i]
        @assert n == 1
    end
    return
end

function makeshrinkable!(periods::SequentialPeriods, shrinkperiods::UnitRange{Int})
    for p in shrinkperiods
        makeshrinkable!(periods, p)
    end
end

makeshrinkable!(periods::SequentialPeriods, shrinkperiod::Int) = _makeshrinkable!(periods.data, shrinkperiod)

function _makeshrinkable!(data::Vector{Tuple{Int, Millisecond}}, shrinkperiod::Int)
    N = length(data)
    
    if shrinkperiod == 1
        (n, ms) = first(data)
        n == 1 && return        # already shrinkable
        push!(data, last(data))
        for i in (N-2):-1:1
            data[i+1] = data[i]
        end
        data[1] = (1, ms)
        data[2] = (n-1, ms)
        return
    end

    T = sum(n for (n, __) in data)

    if shrinkperiod == T
        (n, ms) = last(data)
        n == 1 && return        # already shrinkable
        push!(data, last(data))
        data[N] = (n-1, ms)
        data[N+1] = (1, ms)
        return
    end

    (start, prev, acc) = _shrinkable_find_startpos(data, shrinkperiod)

    (n, ms) = data[start]
    n == 1 && return           # already shrinkable

    if prev == shrinkperiod
        push!(data, last(data))
        for i in (N-2):-1:start
            data[i+1] = data[i]
        end
        data[start] = (1, ms)
        data[start+1] = (n-1, ms)
        return
        
    elseif acc == shrinkperiod
        push!(data, last(data))
        data[start] = (n-1, ms)
        data[start+1] = (1, ms)
        return
        
    else
        push!(data, last(data))
        push!(data, last(data))
        for i in (N-3):-1:start
            data[i+2] = data[i]
        end
        pos = shrinkperiod - prev + 1
        data[start] = (pos-1, ms)
        data[start+1] = (1, ms)
        data[start+2] = (n-pos, ms)
        return
    end
end

function _shrinkable_find_startpos(data, shrinkperiod)
    (start, prev, acc) = (0, 0, 0)
    for (n, ms) in data
        start += 1
        prev = acc + 1
        acc += n
        if shrinkperiod <= acc
            break
        end
    end
    return (start, prev, acc)
end

function getshrinkperiods(p::SequentialPeriods, startafter::Millisecond, shrinkatleast::Millisecond, minperiod::Millisecond)
    @assert startafter >= Millisecond(0)
    @assert minperiod > Millisecond(0)
    @assert shrinkatleast > Millisecond(0)
    
    T = getnumperiods(p)
    
    first_period = -1
    acc = Millisecond(0)
    for t in 1:T
        if acc >= startafter
            first_period = t
            break
        end
        acc += getms(p, t)
    end
    @assert first_period > 0

    acc = Millisecond(0)
    last_period = -1
    for t in first_period:T
        d = getms(p, t)
        @assert d > minperiod
        acc += (d - minperiod)
        if acc >= shrinkatleast
            last_period = t
            break
        end
    end
    @assert last_period > 0

    return first_period:last_period
end

function shrink!(handler::SequentialPeriodsShrinker, p::SequentialPeriods, change::Millisecond)
    subtract = Millisecond(change.value)
    for (i, t) in enumerate(handler.shrinkperiods)
        if subtract <= Millisecond(0)
            @assert subtract == Millisecond(0)
            break
        end
        j = handler.shrinkperiods_index[i]
        (n, ms) = p.data[j]
        if ms > handler.minperiod
            if subtract >= (ms - handler.minperiod)
                p.data[j] = (n, handler.minperiod)
                subtract -= (ms - handler.minperiod)
                handler.shrinkperiods_isupdated[i] = true
            else
                p.data[j] = (n, ms - subtract)
                handler.shrinkperiods_isupdated[i] = true
                subtract = Millisecond(0)
            end
        end
    end
    handler.remaining_duration -= change

    # TODO: Remove or replace with test after initial implementation
    @assert !all(v == false for v in handler.shrinkperiods_isupdated)

    L = maximum(handler.shrinkperiods[i] for (i,isupd) in enumerate(handler.shrinkperiods_isupdated) if isupd)
    fill!(handler.updates_must, false)
    for t in 1:L
        handler.updates_must[t] = true
    end
    return
end

function reset_shift!(handler::SequentialPeriodsShrinker, p::SequentialPeriods, change::Millisecond)
    sumshrink = handler.minperiod # rather have sumshift as a field in handler?
    for (i, t) in enumerate(handler.shrinkperiods)
        j = handler.shrinkperiods_index[i]
        (n, ms) = p.data[j]
        cap = handler.shrinkperiods_maxduration[i]
        p.data[j] = (n, cap)
        sumshrink += cap - handler.minperiod
    end

    shiftperiods = sumshrink.value / sum(handler.shrinkperiods_maxduration).value * length(handler.shrinkperiods)
    if !isinteger(shiftperiods)
        reset_normal!(handler, p, change)
        return
    end
    sp = Int(shiftperiods)

    for t in (last(handler.shrinkperiods)-sp+1):(handler.last_shiftperiod-sp+1)
        if getms(p, t) == getms(p, last(handler.shrinkperiods) + 1)
            handler.updates_shift[t] = t + sp
            handler.updates_must[t] = false
        end
    end

    handler.remaining_duration = sum(v - handler.minperiod for v in handler.shrinkperiods_maxduration)
    return
end

function reset_normal!(handler::SequentialPeriodsShrinker, p::SequentialPeriods, change::Millisecond)
    for (i, t) in enumerate(handler.shrinkperiods)
        j = handler.shrinkperiods_index[i]
        (n, ms) = p.data[j]
        cap = handler.shrinkperiods_maxduration[i]
        p.data[j] = (n, cap)
    end
    handler.remaining_duration = sum(v - handler.minperiod for v in handler.shrinkperiods_maxduration)
    return
end

function reset_state!(handler::SequentialPeriodsShrinker)
    fill!(handler.updates_shift, HORIZON_NOSHIFT)
    fill!(handler.updates_must, true)
    fill!(handler.shrinkperiods_isupdated, false)
    return
end

function reset_state!(handler::SequentialPeriodsShifter)
    fill!(handler.updates_shift, HORIZON_NOSHIFT)
    fill!(handler.updates_must, true)
    return
end

function getchange(handler::_SSequentialPeriods, start::ProbTime)
    c1 = getdatatime(start) - getdatatime(handler.prev_start)
    c2 = getscenariotime(start) - getscenariotime(handler.prev_start)
    return max(c1, c2)
end

# ---- SequentialHorizonShrinker, AdaptiveHorizonShrinker, SequentialHorizonShifter and AdaptiveHorizonShifter ----

struct SequentialHorizonShrinker
    shrinker::SequentialPeriodsShrinker
end

struct AdaptiveHorizonShrinker
    shrinker::SequentialPeriodsShrinker
end

struct SequentialHorizonShifter
    shifter::SequentialPeriodsShifter
end

struct AdaptiveHorizonShifter
    shifter::SequentialPeriodsShifter
end

function gethorizonshrinker(h::SequentialHorizon, startafter::Millisecond, shrinkatleast::Millisecond, minperiod::Millisecond)
    shrinker = gethorizonshrinker(h.periods, startafter, shrinkatleast, minperiod)
    return SequentialHorizonShrinker(shrinker)
end

function gethorizonshrinker(h::AdaptiveHorizon, startafter::Millisecond, shrinkatleast::Millisecond, minperiod::Millisecond)
    shrinker = gethorizonshrinker(h.macro_periods, startafter, shrinkatleast, minperiod)
    return AdaptiveHorizonShrinker(shrinker)
end

function gethorizonshifter(h::Union{SequentialHorizon, AdaptiveHorizon})
    T = getnumperiods(h)
    shift = [HORIZON_NOSHIFT for t in 1:T]
    must = [false for t in 1:T]
    SequentialPeriodsShifter(shift, must, nothing)
end

makeshrinkable!(h::SequentialHorizon, handler::SequentialHorizonShrinker) = makeshrinkable!(h.periods, handler.shrinker)
makeshrinkable!(h::AdaptiveHorizon, handler::AdaptiveHorizonShrinker) = makeshrinkable!(h.macro_periods, handler.shrinker)

build!(h::SequentialHorizon, handler::SequentialHorizonShrinker, p::Prob) = build!(h, p)
build!(h::AdaptiveHorizon, handler::AdaptiveHorizonShrinker, p::Prob) = build!(h, p)
build!(h::SequentialHorizon, handler::SequentialHorizonShifter, p::Prob) = build!(h, p)
build!(h::AdaptiveHorizon, handler::AdaptiveHorizonShifter, p::Prob) = build!(h, p)

mayshiftfrom(h::SequentialHorizon, handler::SequentialHorizonShrinker, t::Int) = _common_mayshiftfrom(h, handler.shrinker, t)
mayshiftfrom(h::SequentialHorizon, handler::SequentialHorizonShifter, t::Int) = _common_mayshiftfrom(h, handler.shifter, t)
mayshiftfrom(h::AdaptiveHorizon, handler::AdaptiveHorizonShrinker, t::Int) = _common_mayshiftfrom(h, handler.shrinker, t)
mayshiftfrom(h::AdaptiveHorizon, handler::AdaptiveHorizonShifter, t::Int) = _common_mayshiftfrom(h, handler.shrinker, t)

function _common_mayshiftfrom(h::SequentialHorizon, shrinker_shifter, t)
    v = shrinker_shifter.updates_shift[t]
    return (v, v != HORIZON_NOSHIFT)
end

function _common_mayshiftfrom(h::AdaptiveHorizon, shrinker_shifter, t)
    s = div(t-1, h.num_block) + 1
    b = (t-1) % h.num_block + 1
    v = shrinker_shifter.updates_shift[s]
    if v == HORIZON_NOSHIFT
        return (HORIZON_NOSHIFT, false)
    end
    return ((v-1) * h.num_block + b, true)
end

mustupdate(h::SequentialHorizon, handler::SequentialHorizonShrinker, t::Int) = _common_mustupdate(h, handler.shrinker, t)
mustupdate(h::SequentialHorizon, handler::SequentialHorizonShifter, t::Int) = _common_mustupdate(h, handler.shifter, t)
mustupdate(h::AdaptiveHorizon, handler::AdaptiveHorizonShrinker, t::Int) = _common_mustupdate(h, handler.shifter, t)
mustupdate(h::AdaptiveHorizon, handler::AdaptiveHorizonShifter, t::Int) = _common_mustupdate(h, handler.shifter, t)

_common_mustupdate(h::SequentialHorizon, shrinker_shifter, t) = shrinker_shifter.updates_must[t]
_common_mustupdate(h::AdaptiveHorizon, shrinker_shifter, t) = shrinker_shifter.updates_must[(t-1) * h.num_block + 1]

function update!(h::SequentialHorizon, handler::SequentialHorizonShrinker, start::ProbTime)
    __ = _common_update_shrinkable!(h, handler, h.periods, start)
    return
end

function update!(h::AdaptiveHorizon, handler::AdaptiveHorizonShrinker, start::ProbTime)
    s = handler.shrinker
    p = h.macro_periods
    
    early_ret = _common_update_shrinkable!(h, handler, p, start)

    early_ret && return

    # First add missing vectors to h.Xs due to shrinked durations
    for (__, ms) in p.data
        if !haskey(h.Xs, ms)
            num_col = Int(ms.value / h.unit_duration.value)
            h.Xs[ms] = zeros(num_col)
        end
    end    
    
    # Then do the shifts
    T = getnumperiods(h)
    for t in (T-1):-1:1
        (future_t, ok) = mayshiftfrom(h, handler, t)
        if ok
            h.periods[t].units = h.periods[future_t].units
        end
    end

    # Finally do the musts
    t = 0
    mp = 0
    acc = Millisecond(0)
    for (num_mp, mp_duration) in p.data
        X = h.Xs[mp_duration]
        for __ in 1:num_mp
            mp += 1
            if s.updates_must[mp]
                update_X!(X, h.data, start, acc, h.unit_duration)
                assignments = assign_blocks!(h.method, X)
                units_per_block = _get_units_per_block(assignments, h.num_block)
                for units in units_per_block
                    t += 1
                    h.periods[t].units = units
                end
            else
                t += h.num_block
            end
            acc += mp_duration
        end
    end

    return
end

update!(h::SequentialHorizon, handler::SequentialHorizonShifter, start::ProbTime) = _common_update_shiftable!(h, handler, start)
update!(h::AdaptiveHorizon, handler::AdaptiveHorizonShifter, start::ProbTime) = _common_update_shiftable!(h, handler, start)

function _common_update_shrinkable!(h, handler, p, start)
    s = handler.shrinker

    reset_state!(s)
    
    if s.prev_start === nothing
        s.prev_start = start
        update!(h, start)
        return true
    end

    change = getchange(s, start)

    s.prev_start = start  

    if change == Millisecond(0)
        fill!(s.updates_must, false)
        return true
    end

    if change <= s.remaining_duration
        shrink!(s, p, change)
    elseif (change == (s.remaining_duration + s.minperiod)) && (s.last_shiftperiod != HORIZON_NOSHIFT)
        reset_shift!(s, p, change)
    else
        reset_normal!(s, p, change)
    end

    return false
end

function _common_update_shiftable!(h, handler, start::ProbTime)
    s = handler.shifter

    reset_state!(s)
    
    if s.prev_start === nothing
        s.prev_start = start
        return
    end

    change = getchange(s, start)

    s.prev_start = start  

    if change == Millisecond(0)
        fill!(s.updates_must, false)
        return
    end

    acc = Millisecond(0)
    for t in 1:getnumperiods(h)
        d = getms(h, t)
        acc += d
        if acc == change
            last_shiftperiod = getlastshiftperiod(h, t)
            for j in t:(last_shiftperiod - 1)
                handler.updates_shift[j] = j + 1 # only shift to next period
                handler.updates_must[j] = false
            end            
            return
        elseif acc > change
            return
        end
    end
end
