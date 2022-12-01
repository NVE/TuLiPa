# ------- Boundary conditions -----------------------------------------------------------------------------------------------
#
# We want to have a modular system for boundary conditions that work 
# with different types of model objects that have one or more state variables. 
# 
# Different objects could be 
#    Storage       - One state variable representing storage content at end of period
#    RampUp        - One state variable representing flow in previous period
#    TimeDelayFlow - Many state variables representing flow in previous periods
#
# We assume that if an object that have state variables support a few functions,
# which can give sufficient information about variables and constraints related to its states, 
# then we should be able to use this interface to define general boundary conditions.
#
# We want to implement different types of boundary conditions
#    StartEqualStop - Ingoing state equal to outgoing state for each state variable
#    SingleCuts     - Future cost variable constrained by optimality cuts 
#    MultiCuts      - Future cost variables for scenarios with probability weights constrained by optimality cuts
#    ValueTerms     - sum vi * xi where xi are segments of state space of outgoing state variable x, 
#                     and vi is marginal value at each segment
#
# Simplifying assumptions:
#   We always use variables for incoming states, even though we sometimes could have used constant rhs terms.
#   We always represent problems as minimization problems. 
#
# Possible challanges:
#   What to do if time delay and hourly master problem and 2-hourly subproblem? 
#   Then time indexes for state variables does not have the same meaning in the two problems. 
#   Similar issue if subproblem use non-sequential horizon.
#
# ----------------------------------------------------------------------------------------------------------------------------

# Interface for objects that are boundary condition types
isboundarycondition(obj) = isinitialcondition(obj) || isterminalcondition(obj)

# A boundary condition can be one or both, but not none
isinitialcondition(::Any) = false
isterminalcondition(::Any) = false

# So we can find which objects have boundary conditions
# E.g. we want to be able to group all objects not already having a 
# boundary condition and use optimality cuts for these
getobjects(::BoundaryCondition) = error("Must implement")


# Some simple types for turning off requirement that all objects with 
# state variables should have boundary conditions

struct NoInitialCondition <: BoundaryCondition
    id::Id
    object::Any
end

struct NoTerminalCondition <: BoundaryCondition
    id::Id
    object::Any
end

struct NoBoundaryCondition <: BoundaryCondition
    id::Id
    object::Any
end

const _NoBoundaryConditionTypes = Union{NoInitialCondition, NoTerminalCondition, NoBoundaryCondition}

getid(x::_NoBoundaryConditionTypes) = x.id
getobjects(x::_NoBoundaryConditionTypes) = [x.object]
build!(::Prob, ::_NoBoundaryConditionTypes) = nothing
setconstants!(::Prob, ::_NoBoundaryConditionTypes) = nothing
update!(::Prob, ::_NoBoundaryConditionTypes, ::ProbTime) = nothing

isinitialcondition(::NoInitialCondition)  = true
isterminalcondition(::NoTerminalCondition) = true
isinitialcondition(::NoBoundaryCondition)  = true
isterminalcondition(::NoBoundaryCondition) = true


# ---- StartEqualStop <: BoundaryCondition ---

struct StartEqualStop <: BoundaryCondition
    id::Id
    object::Any
    function StartEqualStop(object)
        @assert length(getstatevariables(object)) > 0
        id = Id(STARTEQUALSTOP_CONCEPT, getinstancename(getid(object)))
        return new(id, object)
    end
end

getid(x::StartEqualStop) = x.id
geteqid(x::StartEqualStop) = Id(STARTEQUALSTOP_CONCEPT, string("Eq", getinstancename(getid(x))))

getobjects(x::StartEqualStop) = [x.object]

isinitialcondition(::StartEqualStop)  = true
isterminalcondition(::StartEqualStop) = true

function build!(p::Prob, x::StartEqualStop)
    N = length(getstatevariables(x.object))
    addeq!(p, geteqid(x), N)
    return
end

function setconstants!(p::Prob, x::StartEqualStop)
    for (eq_ix, var) in enumerate(getstatevariables(x.object))
        (id_out, ix_out) = getvarout(var)
        (id_in, ix_in) = getvarin(var)
        setconcoeff!(p, geteqid(x), id_out, eq_ix, ix_out,  1.0)
        setconcoeff!(p, geteqid(x),  id_in, eq_ix,  ix_in, -1.0)
    end
    return 
end

update!(::Prob, ::StartEqualStop, ::ProbTime) = nothing

# TODO: Replace with getobjects 
getmainmodelobject(x::StartEqualStop) = x.object


# TODO: Decleare interface for cut-style boundary conditions?

# ------- SimpleSingleCuts -------
# (Simple because we don't have any cut selection, and because we allocate and use a fixed number of cuts)

mutable struct SimpleSingleCuts <: BoundaryCondition
    id::Id
    objects::Vector{Any}
    probabilities::Vector{Float64}
    constants::Vector{Float64}
    slopes::Vector{Dict{StateVariableInfo, Float64}}
    maxcuts::Int
    numcuts::Int
    cutix::Int

    function SimpleSingleCuts(id::Id, objects::Vector{Any}, probabilities::Vector{Float64}, maxcuts::Int)
        # sanity checks
        @assert maxcuts > 0
        @assert length(objects) > 0
        for object in objects
            @assert length(getstatevariables(object)) > 0 
        end
        @assert length(probabilities) > 0
        @assert sum(probabilities) == 1.0
        for probability in probabilities
            @assert probability >= 0.0
        end
        
        # allocate internal storage
        constants = Float64[-Inf for __ in 1:maxcuts]
        slopes = Vector{Dict{StateVariableInfo, Float64}}(undef, maxcuts)
        for i in 1:maxcuts
            d = Dict{StateVariableInfo, Float64}()
            for object in objects
                for var in getstatevariables(object)
                    d[var] = 0.0
                end
            end
            slopes[i] = d
        end       

        # set initial counters
        numcuts = 0
        cutix = 0

        return new(id, objects, probabilities, constants, slopes, maxcuts, numcuts, cutix)
    end
end

isinitialcondition(::SimpleSingleCuts)  = false
isterminalcondition(::SimpleSingleCuts) = true

setnumcuts!(x::SimpleSingleCuts, n::Int) = x.numcuts = n
setcutix!(x::SimpleSingleCuts, i::Int) = x.cutix = i

getobjects(x::SimpleSingleCuts) = x.objects
getprobabilities(x::SimpleSingleCuts) = x.probabilities
getconstants(x::SimpleSingleCuts) = x.constants
getslopes(x::SimpleSingleCuts) = x.slopes
getmaxcuts(x::SimpleSingleCuts) = x.maxcuts
getnumcuts(x::SimpleSingleCuts) = x.numcuts
getcutix(x::SimpleSingleCuts) = x.cutix

function getfuturecostvarid(x::SimpleSingleCuts)
    return Id(getconceptname(getid(x)), string(getinstancename(getid(x)), "FutureCost"))
end

function getcutconid(x::SimpleSingleCuts)
    return Id(getconceptname(x), string(getinstancename(x), "CutConstraint"))
end

function build!(p::Prob, x::SimpleSingleCuts)
    # add single future cost variable
    addvar!(p, getfuturecostvarid(x), 1)

    # add cut constraints
    addge!(p, getcutconid(x), getmaxcuts(x))

    return
end

# Needed to use setrhsterm! in setconstants!
# TODO: Extend Prob interface to allow setrhs!(prob, conid, value) instead of setrhsterms!
getcutconstantid(::SimpleSingleCuts) = Id("CutConstant", "CutConstant")

function setconstants!(p::Prob, x::SimpleSingleCuts)
    # set future cost variable objective function
    setobjcoeff!(p, getfuturecostvarid(x), 1, 1.0)

    for cutix in 1:getmaxcuts(x)
        # set future cost variable in lhs of cut constraints
        setconcoeff!(p, getcutconid(x), getfuturecostvarid(x), cutix, 1, 1.0)

        # inactivate cut constant
        setrhsterm!(p, getcutconid(x), getcutconstantid(x), cutix, -Inf)

        # inactivate cut slopes
        for object in getobjects(x)
            for statevar in getstatevariables(object)
                (varid, varix) = getvarin(statevar)
                setconcoeff!(p, getcutconid(x), varid, cutix, varix, 0.0)
            end
        end
    end
    return
end

update!(::Prob, ::SimpleSingleCuts, ::ProbTime) = nothing

function _set_values_to_zero!(d::Dict)
    for (k, v) in d
        d[k] = zero(typeof(v))
    end
    return nothing
end

function updatecuts!(p::Prob, x::SimpleSingleCuts, 
                     scenarioparameters::Vector{Tuple{Float64, Dict{StateVariableInfo, Float64}}})
    @assert length(scenarioparameters) == length(x.probabilities)
    
    # update cutix
    cutix = getnumcuts(x) + 1
    if cutix > getmaxcuts(x)
        cutix = 1
        setcutix(x, cutix)
    else
        setnumcuts!(x, cutix)
    end
    
    # get internal storage for cut parameters
    avgconstants = getconstants(x)
    avgslopes = getslopes(x)

    # calculate average cut parameters
    avgconstant = 0.0
    avgslopes = avgslopes[cutix]
    _set_values_to_zero!(avgslopes)
    for (i, probability) in enumerate(getprobabilities(x))
        (constant, slopes) = scenarioparameters[i]
        avgconstant += constant * probability
        for (var, value) in slopes
            avgslopes[var] += value * probability
        end
    end

    # store updated cut internally
    avgconstants[cutix] = avgconstant
    avgslopes[cutix] = avgslopes

    # set the newly updated cut in the problem
    setrhsterm!(p, getcutconid(x), getcutconstantid(x), cutix, avgconstant)
    for (var, slope) in avgslopes
        (varid, varix) = getvarin(var)
        setconcoeff!(p, getcutconid(x), varid, cutix, varix, slope)
    end

    return
end

function clearcuts!(p::Prob, x::SimpleSingleCuts)
    # get internal storage for cut parameters
    avgconstants = getconstants(x)
    avgslopes = getslopes(x)
    
    # inactivate cut parameters in internal storage
    fill!(avgconstants, -Inf)
    for slopes in avgslopes
        _set_values_to_zero!(slopes)
    end

    # set counters to 0
    setnumcuts!(x, 0)
    setcutix!(x, 0)

    # inactivate cuts in problem
    for cutix in eachindex(avgconstants)
        setrhsterm!(p, getcutconid(x), getcutconstantid(x), cutix, avgconstants[cutix])
        for (var, slope) in avgslopes[cutix]
            (varid, varix) = getvarin(var)
            setconcoeff!(p, getcutconid(x), varid, cutix, varix, slope)
        end
    end
    return
end




