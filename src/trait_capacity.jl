"""
We implement PositiveCapacity and LowerZeroCapacity.

PositiveCapacity is a postive upper or lower bound to a variable.

LowerZeroCapacity is a lower bound set to 0 for a variable (i.e. non-negative)

TODO: Support variables that can be positive and negative. Can be useful 
for net flow on transmission line with no losses.
"""

# ---- Concrete types ----
mutable struct PositiveCapacity <: Capacity
    id::Id
    param::Param
    isupper::Bool
end

struct LowerZeroCapacity <: Capacity end

# --------- Interface functions ------------ ()
isconstant(capacity::PositiveCapacity) = isconstant(capacity.param)
isconstant(::LowerZeroCapacity) = true

iszero(::PositiveCapacity) = false
iszero(::LowerZeroCapacity) = true

isdurational(capacity::PositiveCapacity) = isdurational(capacity.param)
isdurational(capacity::LowerZeroCapacity) = false

isupper(capacity::PositiveCapacity) = capacity.isupper
isupper(::LowerZeroCapacity) = false

isnonnegative(::PositiveCapacity) = true
isnonnegative(::LowerZeroCapacity) = true

isstateful(capacity::PositiveCapacity) = isstateful(capacity.param)
isstateful(capacity::LowerZeroCapacity) = false

getparamvalue(capacity::PositiveCapacity, t::ProbTime, d::TimeDelta) = getparamvalue(capacity.param, t, d)
getparamvalue(capacity::LowerZeroCapacity, t::ProbTime, d::TimeDelta) = 0.0

# -------- build! ---------------
# Only does something for more complex Capacities (e.g. InvestmentProjectCapacity)
build!(::Prob, ::Any, ::PositiveCapacity) = nothing
build!(::Prob, ::Any, ::LowerZeroCapacity) = nothing

# ------- setconstant! and update! ---------------------
# Set LB and UB depending on if the value must be dynamically updated or not

function setconstants!(p::Prob, var::Any, capacity::PositiveCapacity)
    horizon = gethorizon(var)
    _must_dynamic_update(capacity, horizon) && return

    T = getnumperiods(horizon)

    varid = getid(var)

    if isdurational(capacity)
        dummytime = ConstantTime()
        # Q: Why not calculate value only once here?
        # A: Because SequentialHorizon can have two or more sets of (nperiod, duration) pairs
        for t in 1:T
            querydelta = gettimedelta(horizon, t)
            value = getparamvalue(capacity, dummytime, querydelta)
            if capacity.isupper
                setub!(p, varid, t, value)
            else
                setlb!(p, varid, t, value)
            end
        end
    else
        dummytime = ConstantTime()
        dummydelta = MsTimeDelta(Hour(1))
        value = getparamvalue(capacity, dummytime, dummydelta)
        for t in 1:T
            if capacity.isupper
                setub!(p, varid, t, value)
            else
                setlb!(p, varid, t, value)
            end
        end
    end
    return
end

function setconstants!(p::Prob, var::Any, ::LowerZeroCapacity)
    T = getnumperiods(gethorizon(var))

    varid = getid(var)

    for t in 1:T
        setlb!(p, varid, t, 0.0)
    end
    return
end

function update!(p::Prob, var::Any, capacity::PositiveCapacity, start::ProbTime)
    horizon = gethorizon(var)
    _must_dynamic_update(capacity, horizon) || return

    T = getnumperiods(horizon)

    varid = getid(var)

    for t in 1:T
        (future_t, ok) = mayshiftfrom(horizon, t)
        if ok
            if capacity.isupper
                value = getub(p, varid, future_t)
                setub!(p, varid, t, value)
            else
                value = getlb(p, varid, future_t)
                setlb!(p, varid, t, value)
            end
        end
    end

    for t in 1:T
        if mustupdate(horizon, t)
            querystart = getstarttime(horizon, t, start)
            querydelta = gettimedelta(horizon, t)
            value = getparamvalue(capacity, querystart, querydelta)
            if capacity.isupper
                setub!(p, varid, t, value)
            else
                setlb!(p, varid, t, value)
            end
        end
    end
    return
end

update!(::Prob, ::Any, ::LowerZeroCapacity, ::ProbTime) = nothing

# ------ Include dataelements -------
function includePositiveCapacity!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    deps = Id[]

    varname    = getdictvalue(value, WHICHINSTANCE, String, elkey)
    varconcept = getdictvalue(value, WHICHCONCEPT,  String, elkey)
    varkey = Id(varconcept, varname)
    push!(deps, varkey)

    (id, param, ok) = getdictparamvalue(lowlevel, elkey, value)
    _update_deps(deps, id, ok)
    
    ok || return (false, deps)
    haskey(toplevel, varkey) || return (false, deps)

    var = toplevel[varkey]

    isupper = getdictisupper(value, elkey)
    
    id = getobjkey(elkey)

    capacity = PositiveCapacity(id, param, isupper)

    if isupper
        setub!(var, capacity)
    else
        setlb!(var, capacity)
    end
    
    return (true, deps)    
end

function includeLowerZeroCapacity!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)
    deps = Id[]

    varname    = getdictvalue(value, WHICHINSTANCE, String, elkey)
    varconcept = getdictvalue(value, WHICHCONCEPT,  String, elkey)
    varkey = BaseId(varconcept, varname)
    push!(deps, varkey)
    
    haskey(toplevel, varkey) || return (false, deps)

    var = toplevel[varkey]

    capacity = LowerZeroCapacity()

    setlb!(var, capacity)
    
    return (true, deps)    
end

INCLUDEELEMENT[TypeKey(CAPACITY_CONCEPT, "PositiveCapacity")] = includePositiveCapacity!
INCLUDEELEMENT[TypeKey(CAPACITY_CONCEPT, "LowerZeroCapacity")] = includeLowerZeroCapacity!;
