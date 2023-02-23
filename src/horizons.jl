"""
We implement SequentialHorizon and AdaptiveHorizon 
(see abstracttypes.jl for general description)

SequentialHorizon --------------------------
Consist of two main elements:
- SequentialPeriods: A list of (N, timedelta) pairs, so a simple 
SequentialPeriods could have N periods of duration timedelta. A more 
complex SequentialPeriods could have first N1 periods of duration 
timedelta1 and then N2 periods of duration timedelta2. One usecase 
for this is if the desired total problem time cant be divided by 
the desired timedelta1. Then we could have N1 periods of timedelta1 
and 1 period of timedelta2 = total time - timedelta1*N1.
- Offset: An optional element that shifts where the Horizon starts. 
Can consist of a isoyear the starttime should be shifted to, and/or
a TimeDelta. Can be used to combine datasets in time (e.g. adding 
future scenarios). See timeoffset.jl

AdaptiveHorizon ----------------------------
Horizon with two dimensions. The overlying dimension is a 
SequentialHorizon consisting of SequentialPeriods and Offset. In the 
second dimension we want to group hours (or time periods) in every 
macro period into blocks based on their characteristics (e.g. hours 
with similar residual load). Every block is a period of 
AdaptiveHorizon consisting of a UnitsTimeDelta.

AdaptiveHorizon is built based on a dataset. We implement 
StaticRHSAHData and DynamicRHSAHData.
AdaptiveHorizon can be built with different methods. We implement 
PercentilesAHMethod and KMeansAHMethod

Heres an example if we split the hours in every week, into 2 blocks 
by high load (day), and low load (night):
macro_periods: weekly resolution
num_block: 2 blocks per macro period
unit_duration: 1 hour

Macro period 1:
Period/UnitsTimeDelta 1: [7:20, 32:40, 56:68, 80:92, 104:116, 128:140, 152:164] - first week high load
Period/UnitsTimeDelta 2: [1:6, 20:31, 41:55 etc...] - first week low load
Macro period 2:
Period/UnitsTimeDelta 3: [175:188, etc...] - second week high load
Period/UnitsTimeDelta 4: [169:174, etc...] - second week low load
Macro period 3:
Period/UnitsTimeDelta 5: [...] - third week high load
Period/UnitsTimeDelta 6: [...] - third week low load

Horizon interface functions ---------------------
    getnumperiods(::Horizon) -> Int

    # To relate the Horizon and problem starting time to TimeVector data
    getstarttime(h::Horizon, t::Int, start::ProbTime) -> ProbTime
    getduration(h::Horizon) -> Millisecond
    getstartduration(::Horizon, ::Int) -> Millisecond
    gettimedelta(::Horizon, ::Int) -> TimeDelta
    
    # To support different Horizons between variables (Flow and Storage) and Balances
    # Return subperiods from the fine Horizon that are inside period s in the coarse Horizon.
    # The two Horizons must be compatible
    getsubperiods(coarse::Horizon, fine::Horizon, s::Int) -> UnitRange{Int}

    # To support AdaptiveHorizon which has to be built and possibly updated dynamically 
    build!(horizon::Horizon, prob::Prob)
    update!(horizon::Horizon, t::ProbTime)

    # To check if constant parameters in Prob can be updated only once
    isadaptive(horizon::Horizon) -> Bool
    hasconstantdurations(horizon::Horizon) -> Bool

    # To combine datasets in time (e.g. adding future scenarios)
    hasoffset(horizon::Horizon) -> Bool
    getoffset(horizon::Horizon) -> Offset
"""

using Clustering, Random

# --------- Generic fallback Horizon interface -----------------
# We want to update the problem efficiently, so we check if 
# problem values must be updated dynamically
# If the value is the same for all scenarios and time periods, 
# it should only be updated once using setconstants! instead of update!
function _must_dynamic_update(paramlike::Any, horizon::Horizon) 
    isconstant(paramlike) || return true

    if isdurational(paramlike) && !hasconstantdurations(horizon)
        return true
    end

    return false
end

# ------ SequentialPeriods -----------
# Component in SequentialHorizon and AdaptiveHorizon
struct SequentialPeriods
    data::Vector{Tuple{Int, Millisecond}}

    function SequentialPeriods(data::Vector{Tuple{Int, Millisecond}}) 
        for (n, ms) in data
            @assert n > 0
            @assert ms > Millisecond(0)
        end
        new(data)
    end
end

function parse_int_period_args(int_period...)
    n = length(int_period)

    n == 0 && error("Must have at least Int and Period as input")
    n % 2 != 0 && error("Must have even number of Int, Period arguments")

    num_tuples = n ÷ 2

    list = Vector{Tuple{Int, Millisecond}}(undef, num_tuples)
    for (i, ev) in enumerate(2:2:(n+1))
        od = ev - 1
        n = int_period[od]
        p = int_period[ev]

        n isa Int || error("Argument $od must be Int")
        p isa Period || error("Argument $ev must be Period")

        p = Millisecond(p)

        list[i] = (n, p)
    end

    return list
end

function parse_timeperiod_args(start::DateTime, stop::DateTime, delta::Period)
    delta = Millisecond(delta)

    if (stop - start) < delta
        error("(stop - start) < delta")
    end

    if delta < Millisecond(1)
        error("delta < Millisecond(1)")
    end

    up = (stop-start).value
    lo = delta.value
    n = Int(floor(up / lo))
    rest = stop - (start + delta * n)

    return (n, rest)
end

SequentialPeriods(int_period...) = SequentialPeriods(parse_int_period_args(int_period...))

function SequentialPeriods(start::DateTime, stop::DateTime, delta::Period)
    (n, rest) = parse_timeperiod_args(start, stop, delta)
    t1 = (n, Millisecond(delta))
    if rest > Millisecond(0)
        t2 = (1, Millisecond(rest))
        return SequentialPeriods([t1, t2])
    else
        return SequentialPeriods([t1])
    end
end

function getXs(x::SequentialPeriods, unit_duration::Millisecond)
    Xs = Dict{Millisecond, Vector{Float64}}()
    for (__, ms) in x.data
        if !haskey(Xs, ms)
            num_col = Int(ms.value / unit_duration.value)
            Xs[ms] = zeros(num_col)
        end
    end
    return Xs
end

function getduration(x::SequentialPeriods)
    acc = Millisecond(0)
    for (n, ms) in x.data
        acc += ms * n 
    end
    return acc
end

getnumperiods(x::SequentialPeriods) = sum(n for (n, __) in x.data)

function getstartduration(x::SequentialPeriods, t::Int)
    t < 1 && error("t < 1")
    step = 1
    acc = Millisecond(0)
    for (n, ms) in x.data
        to_next_step = step + n
        if t > to_next_step
            step = to_next_step
            acc += ms * n
        else
            m = t - step
            acc += ms * m
            return acc
        end
    end
    error("t > getnumperiods(horizon)")
end

function gettimedelta(x::SequentialPeriods, t::Int)
    t < 1 && error("t < 1")
    start = 1
    for (n, ms) in x.data
        stop = start + n - 1
        if t >= start && t <= stop
            return MsTimeDelta(ms)
        end
        start = stop + 1
    end
    error("t > getnumperiods(horizon)")
end

function getsubperiods(coarse::SequentialPeriods, fine::SequentialPeriods, coarse_t::Int)
    # Most common case
    if coarse.data == fine.data
        return coarse_t:coarse_t
    end

    # Other cases
    startduration = getstartduration(coarse, coarse_t)
    stopduration  = getstartduration(coarse, coarse_t + 1)
    
    list_ix = 1
    fine_start = 0
    acc = Millisecond(0)

    (list_ix, fine_start, acc) = accumulate_duration(fine, acc, startduration, list_ix, fine_start)

    # fine_stop = (fine_start - 1)
    
    (list_ix, fine_stop, acc) = accumulate_duration(fine, acc, stopduration, list_ix, fine_start-1)
    # (list_ix, fine_stop, acc) = accumulate_duration(fine, acc, stopduration, list_ix, fine_stop)

    fine_start += 1
    fine_stop += 1

    return fine_start:fine_stop
end

function accumulate_duration(x::SequentialPeriods, acc::Millisecond, target::Millisecond, list_ix::Int, t::Int)
    for i in list_ix:lastindex(x.data)
        (n, ms) = x.data[i]

        to_next_duration = acc + ms * n

        if target > to_next_duration
            t += n
            acc = to_next_duration
        else
            up = (target - acc).value
            lo = ms.value
            if up % lo != 0
                error("Fine periods does not fit in coarse periods")
            else
                m = up ÷ lo
                t += m
                acc += ms * m
                return (i, t, acc)
            end
        end
    end
    if acc < target
        error("Fine periods have shorther duration than coarse periods")
    end
end

# --------- SequentialHorizon ------------------
struct SequentialHorizon <: Horizon
    periods::SequentialPeriods
    offset::Union{Offset, Nothing}

    function SequentialHorizon(int_period...; offset::Union{Offset, Nothing} = nothing)
        periods = SequentialPeriods(int_period...)
        new(periods, offset)
    end

    function SequentialHorizon(start::DateTime, stop::DateTime, duration::Period; 
                                offset::Union{Offset, Nothing} = nothing)
        periods = SequentialPeriods(start, stop, duration)
        new(periods, offset)
    end
end

isadaptive(::SequentialHorizon) = false
hasconstantdurations(::SequentialHorizon) = true
build!(::SequentialHorizon, ::Prob) = nothing
update!(::SequentialHorizon, ::ProbTime) = nothing
getnumperiods(h::SequentialHorizon) = getnumperiods(h.periods)
getstartduration(h::SequentialHorizon, t::Int) = getstartduration(h.periods, t)
getduration(h::SequentialHorizon) = getduration(h.periods)
gettimedelta(h::SequentialHorizon, t::Int) = gettimedelta(h.periods, t)
hasoffset(h::SequentialHorizon) = h.offset !== nothing
getoffset(h::SequentialHorizon) = h.offset

function getstarttime(h::SequentialHorizon, t::Int, start::ProbTime)
    if hasoffset(h)
        starttime = getoffsettime(start, getoffset(h))
        starttime += getstartduration(h.periods, t)
    else
        starttime = start + getstartduration(h.periods, t)
    end
    return starttime
end

function getsubperiods(coarse::SequentialHorizon, fine::SequentialHorizon, coarse_t::Int)
    return getsubperiods(coarse.periods, fine.periods, coarse_t)
end


# ------------- AdaptiveHorizon ---------------- 

abstract type AdaptiveHorizonData end
abstract type AdaptiveHorizonMethod end

struct AdaptiveHorizon{D <: AdaptiveHorizonData, M <: AdaptiveHorizonMethod} <: Horizon
    macro_periods::SequentialPeriods
    num_block::Int
    unit_duration::Millisecond
    data::D
    method::M
    periods::Vector{UnitsTimeDelta}
    Xs::Dict{Millisecond, Vector{Float64}}
    offset::Union{Offset, Nothing}

    function AdaptiveHorizon(macro_periods::SequentialPeriods, num_block::Int, unit_duration::Period, 
                            data, method; offset::Union{Offset, Nothing} = nothing)
        unit_duration = Millisecond(unit_duration)
        @assert num_block > 0
        @assert unit_duration > Millisecond(0)
        init!(data, macro_periods, num_block, unit_duration)
        init!(method, macro_periods, num_block, unit_duration)
        Xs = getXs(macro_periods, unit_duration)
        num_periods = getnumperiods(macro_periods) * num_block
        if hasconstantdurations(method)
            # setconstants!(prob) may be called (if AdaptiveHorizonData is dynamic and dataset has constant values)
            # in this case, setconstants! needs to know the amount of units in each timedelta. Which units are not important, only the number
            periods = [UnitsTimeDelta([1:Int(mp_duration/unit_duration/num_block)], unit_duration) for (num_mp, mp_duration) in macro_periods.data for __ in 1:num_mp*num_block]
        else
            periods = [UnitsTimeDelta([], unit_duration) for __ in 1:num_periods]
        end
        new{typeof(data), typeof(method)}(macro_periods, num_block, unit_duration, 
                                        data, method, periods, Xs, offset)
    end

    function AdaptiveHorizon(num_block::Int, unit_duration::Period, 
                            data, method, int_period...; offset::Union{Offset, Nothing} = nothing)
        macro_periods = SequentialPeriods(int_period...)
        AdaptiveHorizon(macro_periods, num_block, unit_duration, data, method; offset=offset)
    end

    function AdaptiveHorizon(num_block::Int, unit_duration::Period, data, method, 
                            start::DateTime, stop::DateTime, macro_duration::Period; 
                            offset::Union{Offset, Nothing} = nothing)
        macro_periods = SequentialPeriods(start, stop, macro_duration)
        AdaptiveHorizon(macro_periods, num_block, unit_duration, data, method; offset=offset)
    end
end

isadaptive(::AdaptiveHorizon) = true
hasconstantdurations(horizon::AdaptiveHorizon) = hasconstantdurations(horizon.method)

build!(horizon::AdaptiveHorizon, prob::Prob) = build!(horizon.data, prob)

function update!(horizon::AdaptiveHorizon, start::ProbTime)
    period_ix = 0
    acc = Millisecond(0)
    for (num_mp, mp_duration) in horizon.macro_periods.data
        X = horizon.Xs[mp_duration]
        for __ in 1:num_mp
            update_X!(X, horizon.data, start, acc, horizon.unit_duration)
            acc += mp_duration

            assignments = assign_blocks!(horizon.method, X)

            units_per_block = _get_units_per_block(assignments, horizon.num_block)

            for units in units_per_block
                period_ix += 1
                horizon.periods[period_ix].units = units
            end
        end
    end
    return 
end

function _get_units_per_block(assignments::Vector{T}, num_block::Int) where {T <: Real}
    units_per_block = [UnitRange{Int}[] for __ in 1:num_block]
    current_block = first(assignments)
    start = 1
    prev = start
    for (unit, block) in enumerate(assignments)
        if (block == current_block) && ((unit == prev + 1) || unit == prev)
            prev = unit
        else
            push!(units_per_block[Int(current_block)], start:prev)
            current_block = block
            start = unit
            prev = unit
        end
        if unit == length(assignments)
            push!(units_per_block[Int(current_block)], start:prev)
        end
    end

    @assert all(length(y) > 0 for y in units_per_block)
    y = []
    for b in eachindex(units_per_block)
        for ur in units_per_block[b]
            for j in ur
                push!(y, j)
            end
        end
    end
    sort!(y)
    @assert y == collect(eachindex(assignments))

    return units_per_block
end

getnumperiods(h::AdaptiveHorizon) = length(h.periods)

getduration(h::AdaptiveHorizon) = getduration(h.macro_periods)

hasoffset(h::AdaptiveHorizon) = h.offset !== nothing
getoffset(h::AdaptiveHorizon) = h.offset

function getstarttime(h::AdaptiveHorizon, t::Int, start::ProbTime)
    if hasoffset(h)
        starttime = getoffsettime(start, getoffset(h))
        starttime += getstartduration(h, t)
    else
        starttime = start + getstartduration(h, t)
    end
    return starttime
end

getstartduration(h::AdaptiveHorizon, t::Int) = getstartduration(h.macro_periods, (t-1) ÷ h.num_block + 1)

gettimedelta(h::AdaptiveHorizon, t::Int) = h.periods[t]

function getsubperiods(coarse::AdaptiveHorizon, fine::AdaptiveHorizon, coarse_t::Int)
    if fine === coarse
        return coarse_t:coarse_t
    else
        error("Not possible")
    end
end

# To interact with SequentialHorizon
function getsubperiods(coarse::SequentialHorizon, fine::AdaptiveHorizon, coarse_t::Int)
    macro_subperiods = getsubperiods(coarse.periods, fine.macro_periods, coarse_t)
    s1 = first(macro_subperiods)
    sN = last(macro_subperiods)
    t1 = (s1 - 1) * fine.num_block + 1
    tN = sN * fine.num_block
    return t1:tN
end

function getsubperiods(coarse::AdaptiveHorizon, fine::SequentialHorizon, coarse_t::Int)
    return getsubperiods(coarse.macro_periods, fine.periods, coarse_t)
end

# ------ AdaptiveHorizonData types --------

# internal utility functions
function _get_rhs_terms_from_prob(prob::Prob, commodity::String)
    rhs_terms = []
    for obj in getobjects(prob)
        obj isa Balance || continue
        isexogen(obj) && continue
        commodity == getinstancename(getid(getcommodity(obj))) || continue
        for rhs_term in getrhsterms(obj)
            isconstant(rhs_term) && continue
            getresidualhint(rhs_term) == false && continue
            push!(rhs_terms, rhs_term)
        end
    end
    @assert length(rhs_terms) > 0
    return rhs_terms
end

function _get_residual_load(rhs_terms::Vector, datatime::DateTime, start::DateTime, 
                            stop::DateTime, unit_duration::Millisecond)
    num_values = Int((stop - start).value / unit_duration.value)
    x = zeros(num_values)
    index = StepRange(start, unit_duration, stop - unit_duration)
    @assert length(index) == length(x)
    delta = MsTimeDelta(unit_duration)
    for rhs_term in rhs_terms
        t = FixedDataTwoTime(datatime, start)
        for i in eachindex(x)
            value = getparamvalue(rhs_term, t, delta)::Float64
            if isingoing(rhs_term)
                value = -value
            end
            x[i] += value
            t += delta
        end
    end
    residual_load = RotatingTimeVector(index, x, start, stop)
    return residual_load
end

# StaticRHSData -------------
mutable struct StaticRHSAHData <: AdaptiveHorizonData
    commodity::String
    datatime::DateTime
    start::DateTime
    stop::DateTime
    unit_duration::Union{Nothing, Millisecond}
    residual_load::Union{Nothing, RotatingTimeVector}

    function StaticRHSAHData(commodity::String, datatime::DateTime, start::DateTime, stop::DateTime)
        new(commodity, datatime, start, stop, nothing, nothing)
    end

    function StaticRHSAHData(commodity::String, datayear::Int, startyear::Int, stopyear::Int)
        datatime = getisoyearstart(datayear)
        start = getisoyearstart(startyear)
        stop = getisoyearstart(stopyear)
        new(commodity, datatime, start, stop, nothing, nothing)
    end
end

function init!(data::StaticRHSAHData, ::SequentialPeriods, ::Int, unit_duration::Millisecond)
    data.unit_duration = unit_duration
    return
end

function build!(data::StaticRHSAHData, prob::Prob)
    rhs_terms = _get_rhs_terms_from_prob(prob, data.commodity)
    residual_load = _get_residual_load(rhs_terms, data.datatime, data.start, data.stop, data.unit_duration)
    data.residual_load = residual_load
    return
end

function update_X!(X::Vector{Float64}, data::StaticRHSAHData, start::ProbTime, 
                   acc::Millisecond, unit_duration::Millisecond)
    fill!(X, 0.0)
    unit_delta = MsTimeDelta(unit_duration)
    scenariotime = getscenariotime(start)
    for col in eachindex(X)
        querystart = scenariotime + acc + (col - 1) * unit_duration
        X[col] += getweightedaverage(data.residual_load, querystart, unit_delta)::Float64
    end
    return
end

# DynamicRHSData ----------------
mutable struct DynamicRHSAHData <: AdaptiveHorizonData
    commodity::String
    rhs_terms::Vector{Any}
    DynamicRHSAHData(commodity) = new(commodity, [])
end

init!(::DynamicRHSAHData, ::SequentialPeriods, ::Int, ::Millisecond) = nothing

function build!(data::DynamicRHSAHData, prob::Prob)
    data.rhs_terms = _get_rhs_terms_from_prob(prob, data.commodity)
    return
end

function update_X!(X::Vector{Float64}, data::DynamicRHSAHData, start::ProbTime, 
                   acc::Millisecond, unit_duration::Millisecond)
    fill!(X, 0.0)
    unit_delta = MsTimeDelta(unit_duration)

    for rhs_term in data.rhs_terms
        for col in eachindex(X)
            querystart = start + acc + (col - 1) * unit_duration
            value = getparamvalue(rhs_term, querystart, unit_delta)::Float64
            if isingoing(rhs_term)
                value = -value
            end
            X[col] += value
        end
    end
    return
end

# ------- AdaptiveHorizonMethod types -------

# PercentilesAHMethod -----------------
mutable struct PercentilesAHMethod <: AdaptiveHorizonMethod
    percentiles::Vector{Float64}

    PercentilesAHMethod() = new([])

    function PercentilesAHMethod(x::Vector{Float64})
        x = copy(x)
        sort!(x)
        n = length(x)

        @assert n > 1
        @assert all(0 < i < 1 for i in x)
        @assert all(x[i-1] < x[i] for i in 2:lastindex(x))

        new(x)
    end
end

hasconstantdurations(::PercentilesAHMethod) = true

function init!(x::PercentilesAHMethod, ::SequentialPeriods, num_blocks::Int, ::Millisecond)
    if length(x.percentiles) == 0
        n = num_blocks
        x.percentiles = [i/n for i in 1:(n-1)]
    else
        @assert length(x.percentiles) == (num_blocks + 1)
    end
    return
end

function assign_blocks!(method::PercentilesAHMethod, X::Vector{Float64})
    x = [(v, i) for (i, v) in enumerate(view(X, :))]
    sort!(x)
    n = length(x)
    assignments = Vector{Int}(undef, n)
    block = 1
    limit = first(method.percentiles)
    # loop over col ix and calc percentage
    for (i, (__, unit)) in enumerate(x)
        percent = i / n
        @assert percent <= 1.0

        if percent > limit
            block += 1
            
            if block > length(method.percentiles)
                limit = 1.0
            else
                limit = method.percentiles[block]
            end
        end
        assignments[unit] = block
    end

    @assert length(Set(assignments)) == (length(method.percentiles) + 1)
    return assignments
end

# ---------- KMeansAHMethod ---------------
mutable struct KMeansAHMethod <: AdaptiveHorizonMethod
    num_cluster::Int
    KMeansAHMethod() = new(-1)
end

hasconstantdurations(::KMeansAHMethod) = false

function init!(method::KMeansAHMethod, ::SequentialPeriods, num_block::Int, ::Millisecond)
    method.num_cluster = num_block
    return
end

function assign_blocks!(method::KMeansAHMethod, X::Vector{Float64})
    Random.seed!(1000) # NB!!! for consistent results in testing-------------------------------
    result = kmeans(reshape(X, 1, length(X)), method.num_cluster)
    return result.assignments
end

# ------ Include dataelements -------
function includeBaseHorizon!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    numperiods = getdictvalue(value, "NumPeriods",      Int,                      elkey)
    timedelta  = getdictvalue(value, TIMEDELTA_CONCEPT, Union{String, TimeDelta}, elkey)
    
    if timedelta isa String
        timedeltakey = BaseId(TIMEDELTA_CONCEPT, timedelta)
        haskey(lowlevel, timedeltakey) || return false
        timedelta = lowlevel[timedelta]
    end
    
    lowlevel[getobjkey(elkey)] = BaseHorizon(numperiods, timedelta)
    return true
end

INCLUDEELEMENT[TypeKey(HORIZON_CONCEPT, "BaseHorizon")] = includeBaseHorizon!






