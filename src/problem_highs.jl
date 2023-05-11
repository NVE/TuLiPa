"""
Implementation of HiGHS_Prob <: Prob 
- see abstracttypes.jl and problem_jump.jl for a description of the framework

Inspiration and also some code snippets gotten from 
https://github.com/jump-dev/HiGHS.jl/blob/master/src/MOI_wrapper.jl

We would like to mainly use JuMP_Prob, but we experienced that 
build! and update! time did not scale well with the version of JuMP with HiGHS 
that we used while testing. This may be fixed soon due to 
https://github.com/ERGO-Code/HiGHS/issues/917, but we needed a workaround right away. 
We therefore implemented HiGHS_Prob, which uses the HiGHS API function Highs_passLp 
whenever constrait coefficients are updated. In our use case, updating coefficients 
usually only occur once in in the setconstants! function. 
We also experimented with different HiGHS API functions for updating other LP parameters,
and found that the class of change-by-mask-functions worked well for our use case.

While implementing HiGHS_Prob, it was very useful to already have JuMP_Prob, 
because then we could use JuMP_Prob to test that HiGHS_Prob 
got the same results as JuMP_Prob.
"""

using HiGHS

# --- Constants ----

const HighsInt = HiGHS.HighsInt

const CONEQ =  0
const CONGE =  1
const CONLE = -1
const CONFIX = -2

# --- Helper types ----

mutable struct HiGHSVarInfo
    start::HighsInt
    num::HighsInt
    function HiGHSVarInfo()
        new(0, 0)
    end
end

mutable struct HiGHSConInfo
    start::HighsInt
    num::HighsInt
    contype::Int
    rhsterms::Vector{Dict{Any, Float64}}
    function HiGHSConInfo()
        new(0, 0, 0, [])
    end
end

# --- Main type ----

mutable struct HiGHS_Prob <: Prob
    objects::Vector
    
    inner::Ptr{Cvoid}
    
    vars::Dict{Any, HiGHSVarInfo}
    cons::Dict{Any, HiGHSConInfo}
    
    num_col::HighsInt
    num_row::HighsInt
    
    col_cost::Vector{Float64}
    col_lower::Vector{Float64}
    col_upper::Vector{Float64}
    
    row_lower::Vector{Float64}
    row_upper::Vector{Float64}
    
    A::Dict{Int, Dict{Int, Float64}} 
    
    col_values::Vector{Float64}
    row_duals::Vector{Float64}
    
    isoptimal::Bool
    
    col_cost_mask::Vector{HighsInt}
    col_bounds_mask::Vector{HighsInt}
    row_bounds_mask::Vector{HighsInt}
    
    isvarvaluesupdated::Bool
    iscondualsupdated::Bool

    is_A_updated::Bool
    
    horizons::Vector{Horizon}

    # TODO: add flag isbuilt and only allow makefixable while building
    fixable_vars::Dict{Tuple{Id, Int}, Id}
    
    function HiGHS_Prob(modelobjects)
        if modelobjects isa Dict
            modelobjects = [o for o in values(modelobjects)]
        end
        p = new(
            modelobjects,
            Highs_create(),
            Dict{Any, HiGHSVarInfo}(),
            Dict{Any, HiGHSConInfo}(),
            0, 0,
            [], [], [], [], [],
            Dict{Int, Dict{Int, Float64}}(),
            [], [],
            false,
            [], [], [],
            false, false, false,
            [],
            Dict()
        )

        setsilent!(p)

        horizons = Set(gethorizon(x) for x in getobjects(p) if x isa Balance)
        for horizon in horizons
            build!(horizon, p)
        end
        horizons = Horizon[i for i in horizons]
        p.horizons = horizons

        for obj in getobjects(p)
            build!(p, obj)
        end

        _init_arrays!(p)

        for obj in getobjects(p)
            setconstants!(p, obj)
        end

        if _is_mask_updated(p.row_bounds_mask)
            _update_row_bounds(p)
        end

        _passLP!(p)
        Highs_setIntOptionValue(p, "simplex_scale_strategy", 5)
        
        finalizer(Highs_destroy, p)
        
        return p
    end
    function HiGHS_Prob()
        p = new(
            [],
            Highs_create(), 
            Dict{Any, HiGHSVarInfo}(),
            Dict{Any, HiGHSConInfo}(),
            0, 0,
            [], [], [], [], [],
            Dict{Int, Dict{Int, Float64}}(),
            [], [],
            false,
            [], [], [],
            false, false, false,
            [],
            Dict()
        )
        finalizer(Highs_destroy, p)
    end    
end

# ----- Update problem ----------
function update!(p::HiGHS_Prob, start::ProbTime)
    for horizon in gethorizons(p)
        update!(horizon, start)
    end
    for obj in getobjects(p)
        update!(p, obj, start)
    end
end

# ---- Utility functions ---

function checkret(ret::HighsInt)
    if ret == kHighsStatusError
        error(
            "Encountered an error in HiGHS (Status $(ret)). Check the log " *
            "for details.",
        )
    end
    return
end

Base.cconvert(::Type{Ptr{Cvoid}}, model::HiGHS_Prob) = model
Base.unsafe_convert(::Type{Ptr{Cvoid}}, model::HiGHS_Prob) = model.inner

# ---- Interface functions for Prob types -----

function setsilent!(p::HiGHS_Prob)
    ret = Highs_setBoolOptionValue(p, "output_flag", 0)
    checkret(ret)    
    return
end

function unsetsilent!(p::HiGHS_Prob)
    ret = Highs_setBoolOptionValue(p, "output_flag", 1)
    checkret(ret)    
    return
end

getobjects(p::HiGHS_Prob) = p.objects
gethorizons(p::HiGHS_Prob) = p.horizons

function addvar!(p::HiGHS_Prob, id::Id, N::Int)
    haskey(p.vars, id) && error("Variable $id already exist")
    info = HiGHSVarInfo()
    info.start = p.num_col
    info.num = N
    p.vars[id] = info
    p.num_col += N
    return
end

function addeq!(p::HiGHS_Prob, id::Id, N::Int)
    haskey(p.cons, id) && error("Constraint $id already exist")
    info = HiGHSConInfo()
    info.start = p.num_row
    info.num = N
    info.contype =  CONEQ
    p.cons[id] = info
    p.num_row += N
    return
end

function addge!(p::HiGHS_Prob, id::Id, N::Int)
    haskey(p.cons, id) && error("Constraint $id already exist")
    info = HiGHSConInfo()
    info.start = p.num_row
    info.num = N
    info.contype =  CONGE
    p.cons[id] = info
    p.num_row += N
    return
end

function addle!(p::HiGHS_Prob, id::Id, N::Int)
    haskey(p.cons, id) && error("Constraint $id already exist")
    info = HiGHSConInfo()
    info.start = p.num_row
    info.num = N
    info.contype =  CONLE
    p.cons[id] = info
    p.num_row += N
    return
end

function _init_arrays!(p::HiGHS_Prob)
    # c = 0
    p.col_cost = zeros(p.num_col)

    # free variables
    p.col_lower = zeros(p.num_col)
    p.col_upper = zeros(p.num_col)
    fill!(p.col_lower, -Inf)
    fill!(p.col_upper,  Inf)
    
    # 0 = 0 constraints to start with
    p.row_lower = zeros(p.num_row)
    p.row_upper = zeros(p.num_row)
    
    p.col_cost_mask = zeros(HighsInt, p.num_col)    
    p.col_bounds_mask = zeros(HighsInt, p.num_col)    
    p.row_bounds_mask = zeros(HighsInt, p.num_row)    
    
    # Initialize row bounds based on contype
    for info in values(p.cons)
        onebasedrange = (info.start + 1):(info.start + info.num)

        if info.contype == CONGE
            for j in onebasedrange
                p.row_upper[j] = Inf
            end

        elseif info.contype == CONLE
            for j in onebasedrange
                p.row_lower[j] = -Inf
            end

        elseif info.contype == CONFIX
            for j in onebasedrange
                p.row_lower[j] = -Inf
                p.row_upper[j] = Inf
            end
        end
    end
    
    p.col_values = zeros(p.num_col)
    p.row_duals = zeros(p.num_row)    
    
    return
end

function _update_row_bounds(p::HiGHS_Prob)
    for info in values(p.cons)
        length(info.rhsterms) > 0 || continue

        onebasedrange = (info.start + 1):(info.start + info.num)

        if info.contype == CONEQ
            for (i, j) in enumerate(onebasedrange)
                value = sum(values(info.rhsterms[i]))
                p.row_lower[j] = value
                p.row_upper[j] = value
            end

        elseif info.contype == CONGE
            for (i, j) in enumerate(onebasedrange)
                value = sum(values(info.rhsterms[i]))
                p.row_lower[j] = value
            end

        elseif info.contype == CONLE
            for (i, j) in enumerate(onebasedrange)
                value = sum(values(info.rhsterms[i]))
                p.row_upper[j] = value
            end
        end
    end
    return
end

function _passLP!(p::HiGHS_Prob)
    sense    = kHighsObjSenseMinimize
    offset   = 0.0
    
    # setup A in expected format
    a_format = kHighsMatrixFormatColwise
    num_nz = sum(length(d) for d in values(p.A))
    a_start = zeros(HighsInt, p.num_col)
    a_index = zeros(HighsInt, num_nz)
    a_value = zeros(Float64, num_nz)
    i = 1
    for col in 1:p.num_col
        a_start[col] = i - 1 # 0-based
        if haskey(p.A, col)
            for (row, value) in p.A[col]
                a_index[i] = row - 1     # 0-based
                a_value[i] = value
                i += 1
            end
        end
    end
    
    ret = Highs_passLp(
        p, 
        p.num_col, 
        p.num_row, 
        num_nz, 
        a_format, 
        sense, 
        offset, 
        p.col_cost, 
        p.col_lower, 
        p.col_upper, 
        p.row_lower, 
        p.row_upper, 
        a_start,
        a_index,
        a_value
    )
    checkret(ret)   
    
    # reset all isupdated flags
    fill!(p.col_bounds_mask, 0)
    fill!(p.col_cost_mask, 0)
    fill!(p.row_bounds_mask, 0)
    p.is_A_updated = false

    return
end

function _changeColsCostByMask!(p::HiGHS_Prob)
    ret = Highs_changeColsCostByMask(p, p.col_cost_mask, p.col_cost)
    checkret(ret)
    fill!(p.col_cost_mask, 0)
    return
end

function _changeColsBoundsByMask!(p::HiGHS_Prob)
    ret = Highs_changeColsBoundsByMask(p, p.col_bounds_mask, p.col_lower, p.col_upper)
    checkret(ret)
    fill!(p.col_bounds_mask, 0)
    return
end

function _changeRowsBoundsByMask!(p::HiGHS_Prob)
    ret = Highs_changeRowsBoundsByMask(p, p.row_bounds_mask, p.row_lower, p.row_upper)
    checkret(ret)    
    fill!(p.row_bounds_mask, 0)
    return
end

function _is_mask_updated(masks::Vector{T}) where {T <: Integer}
    for value in eachindex(masks)
        value == one(T) && return true
    end
    return false
end

function solve!(p::HiGHS_Prob)
    row_bounds_updated = _is_mask_updated(p.row_bounds_mask)
    if row_bounds_updated
        _update_row_bounds(p)
    end

    if p.is_A_updated
        _passLP!(p)
    else
        if _is_mask_updated(p.col_cost_mask)
            _changeColsCostByMask!(p)
        end
    
        if _is_mask_updated(p.col_bounds_mask)
            _changeColsBoundsByMask!(p)
        end

        if row_bounds_updated
            _changeRowsBoundsByMask!(p)
        end
    end

    ret = Highs_run(p)
    checkret(ret)

    if !(kHighsModelStatusOptimal == Highs_getScaledModelStatus(p))
        scale_strategy = 5
        while (scale_strategy > 2) && !(kHighsModelStatusOptimal == Highs_getScaledModelStatus(p))
            scale_strategy -= 1
            println(string("Rescaling LP with scale strategy ", scale_strategy))
            Highs_setIntOptionValue(p, "simplex_scale_strategy", scale_strategy)
            ret = Highs_run(p)
            checkret(ret)

            if (scale_strategy == 2) && !(kHighsModelStatusOptimal == Highs_getScaledModelStatus(p))
                println("Resetting solver: Rebuilding full LP and pass to solver")
                _passLP!(p)
                ret = Highs_run(p)
                checkret(ret)
                scale_strategy = 5
            end
        end
        Highs_setIntOptionValue(p, "simplex_scale_strategy", 5)
    end

    p.isoptimal = kHighsModelStatusOptimal == Highs_getScaledModelStatus(p)

    p.isvarvaluesupdated = false
    p.iscondualsupdated = false

    @assert p.isoptimal

    return
end

function setconcoeff!(p::HiGHS_Prob, con::Id, var::Id, ci::Int, vi::Int, value::Float64)
    row = p.cons[con].start + ci # 1-based
    col = p.vars[var].start + vi # 1-based
    if !haskey(p.A, col)
        p.A[col] = Dict{Int, Float64}()
    end
    p.A[col][row] = value
    if p.isoptimal
        ret = Highs_changeCoeff(p, row-1, col-1, value)
        checkret(ret)
    else
        p.is_A_updated = true
    end
    return
end

function setub!(p::HiGHS_Prob, var::Id, i::Int, value::Float64)
    col = p.vars[var].start + i  # 1-based
    p.col_upper[col] = value
    p.col_bounds_mask[col] = 1
    return
end

function setlb!(p::HiGHS_Prob, var::Id, i::Int, value::Float64)
    col = p.vars[var].start + i  # 1-based
    p.col_lower[col] = value
    p.col_bounds_mask[col] = 1
    return
end

function setobjcoeff!(p::HiGHS_Prob, var::Id, i::Int, value::Float64)
    col = p.vars[var].start + i  # 1-based
    p.col_cost[col] = value
    p.col_cost_mask[col] = 1
    return
end

function setrhsterm!(p::HiGHS_Prob, con::Id, trait::Id, i::Int, value::Float64)
    info = p.cons[con]
    if length(info.rhsterms) == 0
        info.rhsterms = [Dict() for __ in 1:info.num]
    end
    info.rhsterms[i][trait] = value
    
    row = p.cons[con].start + i  # 1-based
    p.row_bounds_mask[row] = 1
    return
end

function _setvarvalues!(p::HiGHS_Prob)
    p.isoptimal || error("No optimal solution available")
    ret = Highs_getSolution(p, p.col_values, C_NULL, C_NULL, C_NULL)
    checkret(ret)
end

function _setconduals!(p::HiGHS_Prob)
    p.isoptimal || error("No optimal solution available") 
    ret = Highs_getSolution(p, C_NULL, C_NULL, C_NULL, p.row_duals)
    checkret(ret)
end

getobjectivevalue(p::HiGHS_Prob) = Highs_getObjectiveValue(p)

function getvarvalue(p::HiGHS_Prob, key::Id, t::Int)
    if !p.isvarvaluesupdated
        _setvarvalues!(p)
        p.isvarvaluesupdated = true
    end
    info = p.vars[key]
    @assert 1 <= t <= info.num
    col = info.start + t     # To Julia 1-based
    return p.col_values[col]
end

function getcondual(p::HiGHS_Prob, key::Id, t::Int)
    if !p.iscondualsupdated
        _setconduals!(p)
        p.iscondualsupdated = true
    end
    info = p.cons[key]
    @assert 1 <= t <= info.num
    row = info.start + t      # Julia 1-based
    return p.row_duals[row]
end

function getconcoeff(p::HiGHS_Prob, con::Id, var::Id, ci::Int, vi::Int)
    row = p.cons[con].start + ci # 1-based
    col = p.vars[var].start + vi # 1-based
    haskey(p.A, col)      || return 0.0
    haskey(p.A[col], row) || return 0.0
    return p.A[col][row]
end

function getub!(p::HiGHS_Prob, var::Id, i::Int)
    col = p.vars[var].start + i  # 1-based
    return p.col_upper[col]
end

function getlb(p::HiGHS_Prob, var::Id, i::Int)
    col = p.vars[var].start + i  # 1-based
    return p.col_lower[col]
end

function getobjcoeff(p::HiGHS_Prob, var::Id, i::Int)
    col = p.vars[var].start + i  # 1-based
    return p.col_cost[col]
end

function getrhsterm(p::HiGHS_Prob, con::Id, trait::Id, i::Int)
    return p.cons[con].rhsterms[i][trait]
end

function hasrhsterm(p::HiGHS_Prob, con::Id, trait::Id, i::Int)
    return haskey(p.cons[con].rhsterms[i],trait)
end

function getfixvardual(p::HiGHS_Prob, varid::Id, varix::Int)
    conid = _getfixeqid(varid, varix)
    return getcondual(p, conid, 1)
end

# --- Fix state variables for boundary conditions ---

_getfixeqid(varid::Id, varix::Int) = Id(getconceptname(varid), string("FixEq", getinstancename(varid), varix))

function makefixable!(p::HiGHS_Prob, varid::Id, varix::Int)
    conid = _getfixeqid(varid, varix)
    N = 1
    info = HiGHSConInfo()
    info.start = p.num_row
    info.num = N
    info.contype =  CONFIX
    p.cons[conid] = info
    p.num_row += N
    setconcoeff!(p, conid, varid, 1, varix, 1.0)
    p.fixable_vars[(varid, varix)] = conid
    return
end

function fix!(p::HiGHS_Prob, varid::Id, varix::Int, value::Float64)
    conid = p.fixable_vars[(varid, varix)]
    row = p.cons[conid].start + 1 # 1-based
    p.row_lower[row] = value
    p.row_upper[row] = value
    p.row_bounds_mask[row] = 1
    return
end

function unfix!(p::HiGHS_Prob, varid::Id, varix::Int)
    conid = p.fixable_vars[(varid, varix)]
    info = p.cons[conid]
    row = info.start + 1 # 1-based
    p.row_lower[row] = -Inf
    p.row_upper[row] = Inf
    p.row_bounds_mask[row] = 1
    return
end

