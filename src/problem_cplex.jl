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
    count::Int
    updates::Vector{Int}
    indices::Vector{Cint}
    values::Vector{Cdouble}
    updated_rhs_mask::Vector{Int}

    function _CPLEXRHSUpdater(num_objects::Int)
        @assert num_objects > 0
        upd = Vector{Int}(undef, num_objects)
        fill!(upd, _CPLEX_NOT_UPDATED)
        ind = Vector{Cint}(undef, num_objects)
        val = Vector{Cdouble}(undef, num_objects)
        mask = Vector{Int}(undef, num_objects)
        return new(0, upd, ind, val, mask)
    end    
end

function _postsolve_reset!(x::_CPLEXRHSUpdater)
    x.count = 0
    fill!(x.updates, _CPLEX_NOT_UPDATED)
    fill!(x.updated_rhs_mask, _CPLEX_NOT_UPDATED)
    return
end

function _update!(x::_CPLEXRHSUpdater, object_index::Int, value::Float64)
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
        
        finalizer(env) do e
            CPLEX.CPXcloseCPLEX(Ref(e.ptr))
            e.ptr = C_NULL
        end
        
        return env    
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
        CPLEX_Prob(collect(values(modelobjects)))
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

        horizons = Set(gethorizon(x) for x in getobjects(prob) if x isa Balance)
        for horizon in horizons
            build!(horizon, prob)
        end
        horizons = Horizon[i for i in horizons]
        prob.horizons = horizons

        for obj in getobjects(prob)
            build!(prob, obj)
        end

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
            _update!(prob.rhs_updater, ix_le, Inf)
            _update!(prob.rhs_updater, ix_ge, -Inf)  
         end

        # add vars and cols in prob
        _cplex_add_vars!(prob)
        _cplex_add_cons!(prob)

        # set constants
        for obj in getobjects(prob)
            setconstants!(prob, obj)
        end

        # put constants in problem 
        _cplex_presolve_update!(prob)
        _cplex_postsolve_reset_updaters!(prob)
        
        finalizer(prob) do p
            ret = CPLEX.CPXfreeprob(p.env, p.lp)
            _cplex_check_ret(p, ret)
            ret = CPLEX.CPXcloseCPLEX(p.env)
            _cplex_check_ret(p, ret)
            @assert p.env.ptr == C_NULL
        end        
        
        return prob
    end
end

Base.cconvert(::Type{Ptr{Cvoid}}, prob::CPLEX_Prob) = prob
Base.unsafe_convert(::Type{Ptr{Cvoid}}, prob::CPLEX_Prob) = prob.lp::Ptr{Cvoid}

# ----- Update problem ----------
function update!(p::CPLEX_Prob, start::ProbTime)
    for horizon in gethorizons(p)
        update!(horizon, start)
    end
    for obj in getobjects(p)
        update!(p, obj, start)
    end
end

# ---- Definition of Prob interface functions for CPLEX_Prob --------

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
    p.rhs_updater.updated_rhs_mask[row] = 1
    return
end

function getobjectivevalue(p::CPLEX_Prob)
    objval_p = Ref{Cdouble}()
    ret = CPLEX.CPXgetobjval(p.env, p.lp, objval_p)
    _cplex_check_ret(p.env, ret)
    return Float64(objval_p[])
end

# Not part of Prob interface (only helper)
function _setvarvalues!(p::CPLEX_Prob)
    ret = CPLEX.CPXgetx(p.env, p.lp, p.varvalues, 0, length(p.varvalues) - 1)
    _cplex_check_ret(p.env, ret)
    return
end

# Not part of Prob interface (only helper)
function _setconduals!(p::CPLEX_Prob)
    proof_p = C_NULL
    ret = CPLEX.CPXgetpi(p.env, p.lp, p.conduals, 0, length(p.conduals) - 1)
    _cplex_check_ret(p.env, ret)
    return
end

function getvarvalue(p::CPLEX_Prob, key::Id, t::Int)
    if !p.isvarvaluesupdated
        _setvarvalues!(p)
        p.isvarvaluesupdated = true
    end
    info = p.vars[key]
    @assert 1 <= t <= info.num
    col = info.start + t     # To Julia 1-based
    return p.varvalues[col]
end

function getcondual(p::CPLEX_Prob, key::Id, t::Int)
    if !p.iscondualsupdated
        _setconduals!(p)
        p.iscondualsupdated = true
    end
    info = p.cons[key]
    @assert 1 <= t <= info.num
    row = info.start + t     # Julia 1-based
    return p.conduals[row]
end

function getrhsterm(p::CPLEX_Prob, con::Id, trait::Id, i::Int)
    return p.cons[con].rhsterms[i][trait]
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
    return out_p[]
end


function getub!(p::CPLEX_Prob, var::Id, i::Int)
    info = p.vars[var]
    col = info.start + i # 1-based
    @assert 1 <= i <= info.num
    out_p = Ref{Cdouble}()
    ix = col - 1
    ret = CPLEX.CPXgetub(p.env, p.lp, out_p, ix, ix)
    _cplex_check_ret(p.env, ret)
    return out_p[]
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
    return out_p[]
end

function getobjcoeff(p::CPLEX_Prob, var::Id, i::Int)
    info = p.vars[var]
    col = info.start + i # 1-based
    @assert 1 <= i <= info.num
    obj = Ref{Cdouble}()
    ix = col - i
    ret = CPLEX.CPXgetobj(p.env, p.lp, obj, ix, ix)
    _cplex_check_ret(p.env, ret)
    return obj[]
end

function getfixvardual(p::CPLEX_Prob, varid::Id, varix::Int)
    if !p.iscondualsupdated
        _setconduals!(p)
        p.iscondualsupdated = true
    end
    ix_le = p.fixable_vars[(varid, varix)]
    return p.conduals[ix_le]    
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
    ix_ge = ix_le + 1
    _update!(p.rhs_updater, ix_le, value)
    _update!(p.rhs_updater, ix_ge, value)
    return
end

function unfix!(p::CPLEX_Prob, varid::Id, varix::Int)
    (leid, geid) = p.fixable_vars[(varid, varix)]
    ix_le = p.cons[leid].start + 1
    ix_ge = ix_le + 1
    _update!(p.rhs_updater, ix_le, Inf)
    _update!(p.rhs_updater, ix_ge, -Inf)
    return
end

function setsilent!(p::CPLEX_Prob)
    setparam!(p::CPLEX_Prob, "CPXPARAM_ScreenOutput", 0)
    return
end

function setunsilent!(p::CPLEX_Prob)
    setparam!(p::CPLEX_Prob, "CPXPARAM_ScreenOutput", 1)
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
            if u.updated_rhs_mask[rowix] == 1
                _update!(u, rowix, sum(values(info.rhsterms[t])))
            end
        end
    end
    if u.count > 0
        ret = CPLEX.CPXchgrhs(p.env, p.lp, u.count, u.indices, u.values)
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

function _cplex_solve_lp!(p::CPLEX_Prob)
    prob_type = CPLEX.CPXgetprobtype(p.env, p.lp)
    @assert prob_type == CPLEX.CPXPROB_LP
    ret = CPLEX.CPXlpopt(p.env, p.lp)    
    # TODO: Maybe use different function to check ret here
    _cplex_check_ret(p.env, ret)

    # Had to do this check to get objective value
    status_p = Ref{Cint}()
    ret = CPLEX.CPXchecksoln(p.env, p.lp, status_p)
    _cplex_check_ret(p.env, ret)
    @assert status_p[] == 1 # https://www.tu-chemnitz.de/mathematik/discrete/manuals/cplex/doc/refman/html/appendixB.html
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
    ret = CPLEX.CPXnewcols(p.env, p.lp, p.num_col, C_NULL,  fill(-Inf, p.num_col), C_NULL, C_NULL, C_NULL)
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
