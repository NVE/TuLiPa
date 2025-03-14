""" 
Implementation of CPLEX_Prob <: Prob
with non-allocating update functions
"""
# TODO: Add better docs
# TODO: Make into module

using CPLEX

const _CPLEX_NOT_UPDATED = 0

# ---- Definition of internal helper objects ----

mutable struct _CPLEXVectorUpdater
    count::Int
    updates::Vector{Int}
    indices::Vector{Cint}
    values::Vector{Cdouble}

    function _CPLEXVectorUpdater(num_objects::Int)
        @assert num_objects > 0
        upd = Vector{Int}(undef, num_objects)
        fill!(upd, _CPLEX_NOT_UPDATED)
        ind = Vector{Cint}(undef, num_objects)
        val = Vector{Cdouble}(undef, num_objects)
        return new(0, upd, ind, val)
    end    
end

function _postsolve_reset!(x::_CPLEXVectorUpdater)
    x.count = 0
    fill!(x.updates, _CPLEX_NOT_UPDATED)
    return
end

function _update!(x::_CPLEXVectorUpdater, object_index::Int, value::Float64)
    @assert 1 <= object_index <= length(x.updates)
    
    updated = @inbounds x.updates[object_index]

    if updated == _CPLEX_NOT_UPDATED
        x.count += 1
        
        # Check bounds in case caller have forgotten to reset between solves
        @assert 1 <= x.count <= length(x.indices)
        
        @inbounds x.updates[object_index] = x.count
        @inbounds x.indices[x.count] = object_index - 1
        @inbounds x.values[x.count] = value
    else
        @inbounds x.values[updated] = value
    end
    
    return
end

mutable struct _CPLEXRHSUpdater
    updater::_CPLEXVectorUpdater
    updated_rhs_mask::Vector{Bool}

    function _CPLEXRHSUpdater(num_objects::Int)
        mask = Vector{Bool}(undef, num_objects)
        fill!(mask, false)
        return new(_CPLEXVectorUpdater(num_objects), mask)
    end    
end

function _postsolve_reset!(x::_CPLEXRHSUpdater)
    _postsolve_reset!(x.updater)
    fill!(x.updated_rhs_mask, false)
    return
end

function _update!(x::_CPLEXRHSUpdater, object_index::Int, value::Float64)
    _update!(x.updater, object_index, value)
    return
end

mutable struct _CPLEXBoundsUpdater
    updater::_CPLEXVectorUpdater
    lu::Vector{Cchar}

    function _CPLEXBoundsUpdater(num_objects::Int, lu::Vector{Cchar})
        @assert num_objects <= length(lu)
        # TODO: @assert lu is all U or all L?
        return new(_CPLEXVectorUpdater(num_objects), lu)
    end    
end

function _postsolve_reset!(x::_CPLEXBoundsUpdater)
    _postsolve_reset!(x.updater)
end

function _update!(x::_CPLEXBoundsUpdater, object_index::Int, value::Float64)
    _update!(x.updater, object_index, value)
end



mutable struct _CPLEXMatrixUpdater
    numcoefs::Cint
    updates::Dict{Tuple{Int, Int}, Int}
    rowlist::Vector{Cint}
    collist::Vector{Cint}
    vallist::Vector{Cdouble}

    function _CPLEXMatrixUpdater()
        return new(0, Dict{Tuple{Int, Int}, Int}(), Cint[], Cint[], Cdouble[])
    end    
end

function _postsolve_reset!(x::_CPLEXMatrixUpdater)
    x.numcoefs = 0
    for k in keys(x.updates)
        x.updates[k] = _CPLEX_NOT_UPDATED
    end
    return
end


function _update!(x::_CPLEXMatrixUpdater, rowix::Int, colix::Int, value::Float64)
    k = (rowix, colix)

    if haskey(x.updates, k)
        updated = x.updates[k]
        
        if updated == _CPLEX_NOT_UPDATED
            # Key seen before, but not in this update cycle, then just store the value.
            x.numcoefs += 1
            x.updates[k] = x.numcoefs
            @assert x.numcoefs <= length(x.rowlist)
            @inbounds x.rowlist[x.numcoefs] = rowix - 1
            @inbounds x.collist[x.numcoefs] = colix - 1
            @inbounds x.vallist[x.numcoefs] = value
        else
            # Key seen before and already updated at least once this update cycle, then overwrite value
            @inbounds x.vallist[updated] = value
        end
    else
        # Key never been updated before, then grow lists and store row, column and value
        push!(x.rowlist, rowix - 1)
        push!(x.collist, colix - 1)
        push!(x.vallist, value)
        x.numcoefs += 1
        x.updates[k] = x.numcoefs
        if x.numcoefs < length(x.rowlist)
            @inbounds x.rowlist[x.numcoefs] = rowix - 1
            @inbounds x.collist[x.numcoefs] = colix - 1
            @inbounds x.vallist[x.numcoefs] = value
        end
    end
    
    return
end


mutable struct _CPLEXVarInfo
    start::Int
    num::Int
    function _CPLEXVarInfo()
        new(0, 0)
    end
end

mutable struct _CPLEXConInfo
    start::Int
    num::Int
    contype::Cchar
    rhsterms::Vector{Dict{Id, Float64}}
    function _CPLEXConInfo()
        new(0, 0, 'A', [])
    end
end

# Modification of Env struct from: https://github.com/jump-dev/CPLEX.jl/blob/master/src/MOI/MOI_wrapper.jl
mutable struct _CPLEXEnv
    ptr::Ptr{Cvoid}    # (same as CPLEX.CPXENVptr)

    function _CPLEXEnv()
        status_p = Ref{Cint}()
        ptr = CPLEX.CPXopenCPLEX(status_p)
        
        if status_p[] != 0
            error("CPLEX Error $(status_p[]): Unable to create CPLEX environment.")
        end
        
        env = new(ptr)
        
        # finalizer(env) do e
        #     CPLEX.CPXcloseCPLEX(Ref(e.ptr))
        #     e.ptr = C_NULL
        # end
        
        return env
    end

    function _CPLEXEnv(ptr)
        return new(ptr)
    end
end

Base.cconvert(::Type{Ptr{Cvoid}}, x::_CPLEXEnv) = x
Base.unsafe_convert(::Type{Ptr{Cvoid}}, env::_CPLEXEnv) = env.ptr::Ptr{Cvoid}


# ---- Definition of some internal helper functions ------

# copied from https://github.com/jump-dev/CPLEX.jl/blob/master/src/MOI/MOI_wrapper.jl
function _cplex_get_error_string(env::Union{_CPLEXEnv,CPLEX.CPXENVptr}, ret::Cint)
    buffer = Array{Cchar}(undef, CPLEX.CPXMESSAGEBUFSIZE)
    p = pointer(buffer)
    return GC.@preserve buffer begin
        errstr = CPLEX.CPXgeterrorstring(env, ret, p)
        if errstr == C_NULL
            "CPLEX Error $(ret): Unknown error code."
        else
            unsafe_string(p)
        end
    end
end

# copied from https://github.com/jump-dev/CPLEX.jl/blob/master/src/MOI/MOI_wrapper.jl
function _cplex_check_ret(env::Union{_CPLEXEnv,CPLEX.CPXENVptr}, ret::Cint)
    if ret == 0
        return
    end
    return error(_cplex_get_error_string(env, ret))
end

function _cplex_create_lp(env::_CPLEXEnv)
    stat = Ref{Cint}()
    ptr = CPLEX.CPXcreateprob(env, stat, "")
    if ptr == C_NULL
        _cplex_check_ret(env, stat[])
    end
    return ptr
end

# inspiration from https://github.com/jump-dev/CPLEX.jl/blob/master/src/MOI/MOI_wrapper.jl
@inline function _cplex_returnfloat(f::Float64)
    if f >= CPLEX.CPX_INFBOUND
        return Inf
    elseif f <= -CPLEX.CPX_INFBOUND
        return -Inf
    end
    return f
 end

# ---- Definition of CPLEX_Prob (the exported object of this file) -----------

mutable struct CPLEX_Prob <: Prob
    objects::Vector{Any}
    
    horizons::Vector{Horizon}
    
    env::_CPLEXEnv
    lp::Ptr{Cvoid} # (same as CPLEX.CPXLPptr)

    num_row::Int
    num_col::Int
    
    vars::Dict{Id, _CPLEXVarInfo}
    cons::Dict{Id, _CPLEXConInfo}
    fixable_vars::Dict{Tuple{Id, Int}, Tuple{Id, Id}}
    
    lb_updater::Union{Nothing, _CPLEXBoundsUpdater}
    ub_updater::Union{Nothing, _CPLEXBoundsUpdater}

    obj_updater::Union{Nothing, _CPLEXVectorUpdater}
    rhs_updater::Union{Nothing, _CPLEXRHSUpdater}
    
    A_updater::Union{Nothing, _CPLEXMatrixUpdater}

    varvalues::Vector{Float64}
    conduals::Vector{Float64}

    isvarvaluesupdated::Bool
    iscondualsupdated::Bool

    function CPLEX_Prob(modelobjects::Dict)
        return CPLEX_Prob(collect(values(modelobjects)))
    end
    
    function CPLEX_Prob(modelobjects::Vector{Any})
        # Create CPLEX objects
        env = _CPLEXEnv()
        lp = _cplex_create_lp(env)

        # Create data structures
        vars = Dict{Id, _CPLEXVarInfo}()
        cons = Dict{Id, _CPLEXConInfo}()
        fixable_vars = Dict{Tuple{Id, Int}, Tuple{Id, Id}}()

        # Create CPLEX_Prob instance
        prob = new(modelobjects, [], env, lp, 0, 0, vars, cons, fixable_vars, 
                   nothing, nothing, nothing, nothing, nothing, [], [], false, false)

        # --- Initialize data in the prob object -----
        CPLEX.CPXchgobjsen(prob.env, prob.lp, CPLEX.CPX_MIN)
        # setsilent!(prob) # already default

        # TODO: set objective offset to 0

        buildhorizons!(prob)
        build!(prob)

        # Set updaters

        lb = Vector{Cchar}(undef, prob.num_col)
        ub = Vector{Cchar}(undef, prob.num_col)
        fill!(lb, 'L')
        fill!(ub, 'U')
        prob.lb_updater = _CPLEXBoundsUpdater(prob.num_col, lb)
        prob.ub_updater = _CPLEXBoundsUpdater(prob.num_col, ub)

        prob.obj_updater = _CPLEXVectorUpdater(prob.num_col)
        prob.rhs_updater = _CPLEXRHSUpdater(prob.num_row)
        
        prob.A_updater = _CPLEXMatrixUpdater()

        prob.varvalues = zeros(Float64, prob.num_col)
        prob.conduals = zeros(Float64, prob.num_row)

        # Update fixable vars
        for ((varid, varix), (leid, geid)) in prob.fixable_vars
            ix_le = prob.cons[leid].start + 1
            ix_ge = prob.cons[geid].start + 1
            setconcoeff!(prob, leid, varid, 1, varix, 1.0)
            setconcoeff!(prob, geid, varid, 1, varix, 1.0)
            _update!(prob.rhs_updater, ix_le, CPLEX.CPX_INFBOUND)
            _update!(prob.rhs_updater, ix_ge, -CPLEX.CPX_INFBOUND)  
         end

        _cplex_add_vars!(prob)
        _cplex_add_cons!(prob)

        setconstants!(prob)

        _cplex_presolve_update!(prob)
        _cplex_postsolve_reset_updaters!(prob)
        
        finalizer(prob) do p
            ret = CPLEX.CPXfreeprob(p.env, Ref(p.lp))
            _cplex_check_ret(p.env, ret)
            CPLEX.CPXcloseCPLEX(Ref(p.env.ptr))
            p.env.ptr = C_NULL
        end        
        
        return prob
    end
    function CPLEX_Prob()
        env = _CPLEXEnv(C_NULL)
        vars = Dict{Id, _CPLEXVarInfo}()
        cons = Dict{Id, _CPLEXConInfo}()
        fixable_vars = Dict{Tuple{Id, Int}, Tuple{Id, Id}}()

        prob = new([], [], env, C_NULL, 0, 0, vars, cons, fixable_vars, 
            nothing, nothing, nothing, nothing, nothing, [], [], false, false)     
        return prob
    end
end

Base.cconvert(::Type{Ptr{Cvoid}}, prob::CPLEX_Prob) = prob
Base.unsafe_convert(::Type{Ptr{Cvoid}}, prob::CPLEX_Prob) = prob.lp::Ptr{Cvoid}

# ---- Definition of Prob interface functions for CPLEX_Prob --------

is_CPLEX_Prob(p::CPLEX_Prob) = true  # Used to check if the problem type is cplex without having the cplex package
getobjects(p::CPLEX_Prob) = p.objects
gethorizons(p::CPLEX_Prob) = p.horizons

function addvar!(p::CPLEX_Prob, id::Id, N::Int)
    haskey(p.vars, id) && error("Variable $id already exist")
    info = _CPLEXVarInfo()
    info.start = p.num_col
    info.num = N
    p.vars[id] = info
    p.num_col += N
    return
end

# function body copied from https://github.com/jump-dev/CPLEX.jl/blob/master/src/MOI/MOI_wrapper.jl
function setparam!(p::CPLEX_Prob, paramname::String, value)
    numP, typeP = Ref{Cint}(), Ref{Cint}()
    ret = CPLEX.CPXgetparamnum(p.env, paramname, numP)
    _cplex_check_ret(p.env, ret)
    ret = CPLEX.CPXgetparamtype(p.env, numP[], typeP)
    _cplex_check_ret(p.env, ret)
    ret = if typeP[] == CPLEX.CPX_PARAMTYPE_NONE
        Cint(0)
    elseif typeP[] == CPLEX.CPX_PARAMTYPE_INT
        CPLEX.CPXsetintparam(p.env, numP[], value)
    elseif typeP[] == CPLEX.CPX_PARAMTYPE_DOUBLE
        CPLEX.CPXsetdblparam(p.env, numP[], value)
    elseif typeP[] == CPLEX.CPX_PARAMTYPE_STRING
        CPLEX.CPXsetstrparam(p.env, numP[], value)
    else
        @assert typeP[] == CPLEX.CPX_PARAMTYPE_LONG
        CPLEX.CPXsetlongparam(p.env, numP[], value)
    end
    _cplex_check_ret(p.env, ret)
    return
end

# function body copied from https://github.com/jump-dev/CPLEX.jl/blob/master/src/MOI/MOI_wrapper.jl
function getparam(p::CPLEX_Prob, paramname::String)
    numP, typeP = Ref{Cint}(), Ref{Cint}()
    ret = CPLEX.CPXgetparamnum(p.env, paramname, numP)
    _cplex_check_ret(p.env, ret)
    ret = CPLEX.CPXgetparamtype(p.env, numP[], typeP)
    _cplex_check_ret(p.env, ret)
    ret = if typeP[] == CPLEX.CPX_PARAMTYPE_NONE
        return Cint(0)
    elseif typeP[] == CPLEX.CPX_PARAMTYPE_INT
        valueP = Ref{Cint}()
        ret = CPLEX.CPXgetintparam(p.env, numP[], valueP)
        _cplex_check_ret(p.env, ret)
        return valueP[]
    elseif typeP[] == CPLEX.CPX_PARAMTYPE_DOUBLE
        valueP = Ref{Cdouble}()
        ret = CPLEX.CPXgetdblparam(p.env, numP[], valueP)
        _cplex_check_ret(p.env, ret)
        return valueP[]
    elseif typeP[] == CPLEX.CPX_PARAMTYPE_STRING
        buffer = Array{Cchar}(undef, CPLEX.CPXMESSAGEBUFSIZE)
        valueP = pointer(buffer)
        GC.@preserve buffer begin
            ret = CPLEX.CPXgetstrparam(p.env, numP[], valueP)
            _cplex_check_ret(p.env, ret)
            return unsafe_string(valueP)
        end
    else
        @assert typeP[] == CPLEX.CPX_PARAMTYPE_LONG
        valueP = Ref{CPLEX.CPXLONG}()
        ret = CPLEX.CPXgetlongparam(p.env, numP[], valueP)
        _cplex_check_ret(p.env, ret)
        return valueP[]
    end
end

# Not part of Prob interface (only helper)

function _cplex_addcon!(p::CPLEX_Prob, id::Id, N::Int, contype::Char)
    haskey(p.cons, id) && error("Constraint $id already exist")
    info = _CPLEXConInfo()
    info.start = p.num_row
    info.num = N
    info.contype = contype
    p.cons[id] = info
    p.num_row += N
    return
end

function addeq!(p::CPLEX_Prob, id::Id, N::Int)
     _cplex_addcon!(p, id, N, 'E')
end

function addge!(p::CPLEX_Prob, id::Id, N::Int)
    _cplex_addcon!(p, id, N, 'G')
end

function addle!(p::CPLEX_Prob, id::Id, N::Int)
    _cplex_addcon!(p, id, N, 'L')
end

function solve!(p::CPLEX_Prob)
    _cplex_presolve_update!(p)
    _cplex_solve_lp!(p)
    _cplex_postsolve_reset_updaters!(p)    
    p.isvarvaluesupdated = false
    p.iscondualsupdated = false
    return
end

function setconcoeff!(p::CPLEX_Prob, con::Id, var::Id, ci::Int, vi::Int, value::Float64)
    row = p.cons[con].start + ci
    col = p.vars[var].start + vi
    _update!(p.A_updater, row, col, value)
    return
end

function setub!(p::CPLEX_Prob, var::Id, i::Int, value::Float64)
    col = p.vars[var].start + i
    _update!(p.ub_updater, col, value)
    return
end

function setlb!(p::CPLEX_Prob, var::Id, i::Int, value::Float64)
    col = p.vars[var].start + i
    _update!(p.lb_updater, col, value)
    return
end

function setobjcoeff!(p::CPLEX_Prob, var::Id, i::Int, value::Float64)
    col = p.vars[var].start + i
    _update!(p.obj_updater, col, value)
    return
end

function setrhsterm!(p::CPLEX_Prob, con::Id, trait::Id, i::Int, value::Float64)
    info = p.cons[con]
    if length(info.rhsterms) == 0
        info.rhsterms = [Dict() for __ in 1:info.num]
    end
    info.rhsterms[i][trait] = value

    row = p.cons[con].start + i  # 1-based
    p.rhs_updater.updated_rhs_mask[row] = true
    return
end

function getobjectivevalue(p::CPLEX_Prob)
    objval_p = Ref{Cdouble}()
    ret = CPLEX.CPXgetobjval(p.env, p.lp, objval_p)
    _cplex_check_ret(p.env, ret)
    return Float64(objval_p[])
end

# Not part of Prob interface (only helper)
function setvarvalues!(p::CPLEX_Prob)
    ret = CPLEX.CPXgetx(p.env, p.lp, p.varvalues, 0, length(p.varvalues) - 1)
    for i in 1:length(p.varvalues)
        p.varvalues[i] = _cplex_returnfloat(p.varvalues[i])
    end
    _cplex_check_ret(p.env, ret)
    return
end

# Not part of Prob interface (only helper)
function setconduals!(p::CPLEX_Prob)
    ret = CPLEX.CPXgetpi(p.env, p.lp, p.conduals, 0, length(p.conduals) - 1)
    for i in 1:length(p.conduals)
        p.conduals[i] = _cplex_returnfloat(p.conduals[i])
    end
    _cplex_check_ret(p.env, ret)
    return
end

function getvarvalue(p::CPLEX_Prob, key::Id, t::Int)
    if !p.isvarvaluesupdated
        setvarvalues!(p)
        p.isvarvaluesupdated = true
    end
    info = p.vars[key]
    @assert 1 <= t <= info.num
    col = info.start + t     # To Julia 1-based
    return p.varvalues[col]
end

function getcondual(p::CPLEX_Prob, key::Id, t::Int)
    if !p.iscondualsupdated
        setconduals!(p)
        p.iscondualsupdated = true
    end
    info = p.cons[key]
    @assert 1 <= t <= info.num
    row = info.start + t     # Julia 1-based
    return p.conduals[row]
end

function getrhsterm(p::CPLEX_Prob, con::Id, trait::Id, i::Int)
    return _cplex_returnfloat(p.cons[con].rhsterms[i][trait])
end

function hasrhsterm(p::CPLEX_Prob, con::Id, trait::Id, i::Int)
    return haskey(p.cons[con].rhsterms[i],trait)
end

function getlb(p::CPLEX_Prob, var::Id, i::Int)
    info = p.vars[var]
    col = info.start + i # 1-based
    @assert 1 <= i <= info.num
    out_p = Ref{Cdouble}()
    ix = col - 1
    ret = CPLEX.CPXgetlb(p.env, p.lp, out_p, ix, ix)
    _cplex_check_ret(p.env, ret)
    return _cplex_returnfloat(out_p[])
end


function getub!(p::CPLEX_Prob, var::Id, i::Int)
    info = p.vars[var]
    col = info.start + i # 1-based
    @assert 1 <= i <= info.num
    out_p = Ref{Cdouble}()
    ix = col - 1
    ret = CPLEX.CPXgetub(p.env, p.lp, out_p, ix, ix)
    _cplex_check_ret(p.env, ret)
    return _cplex_returnfloat(out_p[])
end

function getconcoeff(p::CPLEX_Prob, con::Id, var::Id, ci::Int, vi::Int)
    coninfo = p.cons[con]
    varinfo = p.vars[var]
    row = coninfo.start + ci # 1-based
    col = varinfo.start + vi # 1-based
    @assert 1 <= ci <= coninfo.num
    @assert 1 <= vi <= varinfo.num
    out_p = Ref{Cdouble}()
    ret = CPLEX.CPXgetcoef(p.env, p.lp, row - 1, col - 1, out_p)
    _cplex_check_ret(p.env, ret)
    return _cplex_returnfloat(out_p[])
end

function getobjcoeff(p::CPLEX_Prob, var::Id, i::Int)
    info = p.vars[var]
    col = info.start + i # 1-based
    @assert 1 <= i <= info.num
    obj = Ref{Cdouble}()
    ix = col - i
    ret = CPLEX.CPXgetobj(p.env, p.lp, obj, ix, ix)
    _cplex_check_ret(p.env, ret)
    return _cplex_returnfloat(obj[])
end

function getfixvardual(p::CPLEX_Prob, varid::Id, varix::Int)
    (leid, __) = p.fixable_vars[(varid, varix)]
    return getcondual(p, leid, 1)
 end

function makefixable!(p::CPLEX_Prob, varid::Id, varix::Int)
    concept = getconceptname(varid)
    name = getinstancename(varid)
    leid = Id(concept, string("FixLe", name, varix))
    geid = Id(concept, string("FixGe", name, varix))
    p.fixable_vars[(varid, varix)] = (leid, geid)
    addle!(p, leid, 1)
    addge!(p, geid, 1)
    return
end

function fix!(p::CPLEX_Prob, varid::Id, varix::Int, value::Float64)
    (leid, geid) = p.fixable_vars[(varid, varix)]
    ix_le = p.cons[leid].start + 1
    ix_ge = p.cons[geid].start + 1
    _update!(p.rhs_updater, ix_le, value)
    _update!(p.rhs_updater, ix_ge, value)
    return
end

function unfix!(p::CPLEX_Prob, varid::Id, varix::Int)
    (leid, geid) = p.fixable_vars[(varid, varix)]
    ix_le = p.cons[leid].start + 1
    ix_ge = p.cons[geid].start + 1
    _update!(p.rhs_updater, ix_le, CPLEX.CPX_INFBOUND)
    _update!(p.rhs_updater, ix_ge, -CPLEX.CPX_INFBOUND)
    return
end

function setsilent!(p::CPLEX_Prob)
    setparam!(p, "CPXPARAM_ScreenOutput", 0)
    return
end

function unsetsilent!(p::CPLEX_Prob)
    setparam!(p, "CPXPARAM_ScreenOutput", 1)
    return
end

function setwarmstart!(p::CPLEX_Prob, bool::Bool)
    bool == false && setparam!(p, "CPXPARAM_Advance", 0)
    bool == true && setparam!(p, "CPXPARAM_Advance", 1)
    return
end

function getwarmstart(p::CPLEX_Prob)
    param = getparam(p, "CPXPARAM_Advance")
    param == 0 && return false
    param > 0 && return true
    return
end

# More helper functions

function _cplex_presolve_update!(p::CPLEX_Prob)
    _cplex_update_bds!(p, p.lb_updater)
    _cplex_update_bds!(p, p.ub_updater)
    _cplex_update_obj!(p, p.obj_updater)
    _cplex_update_rhs!(p, p.rhs_updater)
    _cplex_update_A!(p, p.A_updater)
end


function _cplex_update_bds!(p::CPLEX_Prob, u::_CPLEXBoundsUpdater)
    if u.updater.count > 0
        ret = CPLEX.CPXchgbds(p.env, p.lp, u.updater.count, u.updater.indices, u.lu, u.updater.values)
        _cplex_check_ret(p.env, ret)
    end
    return
end

function _cplex_update_obj!(p::CPLEX_Prob, u::_CPLEXVectorUpdater)
    if u.count > 0
        ret = CPLEX.CPXchgobj(p.env, p.lp, u.count, u.indices, u.values)
        _cplex_check_ret(p.env, ret)
    end
    return
end

function _cplex_update_rhs!(p::CPLEX_Prob, u::_CPLEXRHSUpdater)
    for info in values(p.cons)
        length(info.rhsterms) > 0 || continue
        for (t, rowix) in enumerate((info.start + 1):(info.start + info.num))
            if u.updated_rhs_mask[rowix] == true
                _update!(u, rowix, sum(values(info.rhsterms[t])))
            end
        end
    end
    if u.updater.count > 0
        ret = CPLEX.CPXchgrhs(p.env, p.lp, u.updater.count, u.updater.indices, u.updater.values)
        _cplex_check_ret(p.env, ret)
    end
    return
end

function _cplex_update_A!(p::CPLEX_Prob, u::_CPLEXMatrixUpdater)
    if u.numcoefs > 0
        ret = CPLEX.CPXchgcoeflist(p.env, p.lp, u.numcoefs, u.rowlist, u.collist, u.vallist)    
        _cplex_check_ret(p.env, ret)
    end
    return
end

function _cplex_non_optimal_try_param!(p::CPLEX_Prob, paramname::String, newparam::Any, message::String)
    if CPLEX.CPXgetstat(p.env, p.lp) != CPLEX.CPX_STAT_OPTIMAL
        oldparam = getparam(p, paramname)
        if oldparam != newparam
            println(message)
            setparam!(p, paramname, newparam)
            ret = CPLEX.CPXlpopt(p.env, p.lp) 
            _cplex_check_ret(p.env, ret)
            setparam!(p, paramname, oldparam)
        end
    end
    return
end

function _cplex_non_optimal_try_barrier!(p::CPLEX_Prob, paramname::String, newparam::Any, message::String) # avoids CPX_STAT_OPTIMAL_INFEAS 
    if CPLEX.CPXgetstat(p.env, p.lp) != CPLEX.CPX_STAT_OPTIMAL
        oldparam = getparam(p, paramname)
        if oldparam != newparam
            println(message)
            setparam!(p, paramname, newparam)
            setparam!(p, "CPXPARAM_SolutionType", 2)
            setparam!(p, "CPXPARAM_Barrier_StartAlg", 4)
            ret = CPLEX.CPXlpopt(p.env, p.lp)
            _cplex_check_ret(p.env, ret)
            setparam!(p, paramname, oldparam)
            setparam!(p, "CPXPARAM_SolutionType", 0)
        end
    end
    return
end

function _cplex_solve_lp!(p::CPLEX_Prob)
    prob_type = CPLEX.CPXgetprobtype(p.env, p.lp)
    @assert prob_type == CPLEX.CPXPROB_LP
    ret = CPLEX.CPXlpopt(p.env, p.lp)    
    _cplex_check_ret(p.env, ret)

    _cplex_non_optimal_try_param!(p, "CPXPARAM_Read_Scale", 1, "Trying with more aggressive scaling")
    _cplex_non_optimal_try_param!(p, "CPXPARAM_LPMethod", 2, "Solving with dual simplex")
    _cplex_non_optimal_try_param!(p, "CPXPARAM_LPMethod", 1, "Solving with primal simplex")
    _cplex_non_optimal_try_barrier!(p, "CPXPARAM_LPMethod", 4, "Solving with IPM/Barrier")

    stat = CPLEX.CPXgetstat(p.env, p.lp)
    if stat != CPLEX.CPX_STAT_OPTIMAL
        try
            threadid = myid()
            CPLEX.CPXwriteprob(p.env, p.lp, "failed_model_$threadid.mps", "MPS")
        catch
            CPLEX.CPXwriteprob(p.env, p.lp, "failed_model.mps", "MPS")
        end
        error("Solve failed with termination status $stat")
        # NB! Read with CPLEX to reproduce error and keep original row/col order
        # env = _CPLEXEnv()
        # lp = _cplex_create_lp(env)
        # CPLEX.CPXreadcopyprob(env, lp, "failed_model.mps", "MPS")
        # CPLEX.CPXsetintparam(env, CPLEX.CPXPARAM_ScreenOutput , 1) # unset silent
        # CPLEX.CPXlpopt(env, lp)  
    end
    return
end

function _cplex_postsolve_reset_updaters!(p::CPLEX_Prob)
    _postsolve_reset!(p.lb_updater)
    _postsolve_reset!(p.ub_updater)
    _postsolve_reset!(p.obj_updater)
    _postsolve_reset!(p.rhs_updater)
    _postsolve_reset!(p.A_updater)
    return
end

function _cplex_add_vars!(p::CPLEX_Prob)
    ret = CPLEX.CPXnewcols(p.env, p.lp, p.num_col, C_NULL,  fill(-CPLEX.CPX_INFBOUND, p.num_col), C_NULL, C_NULL, C_NULL)
    _cplex_check_ret(p.env, ret)
    return
end

function _cplex_add_cons!(p::CPLEX_Prob)
    senses = Vector{Cchar}(undef, p.num_row)
    rhs = Vector{Cdouble}(undef, p.num_row)
    fill!(rhs, 0.0)
    for info in values(p.cons)
        for j in (info.start + 1):(info.start + info.num)
            senses[j] = info.contype
        end
    end
    ret = CPLEX.CPXaddrows(p.env, p.lp, 0, p.num_row, 0, rhs, senses, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL)
    _cplex_check_ret(p.env, ret)
    return
end
