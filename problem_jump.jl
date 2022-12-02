"""
Implementation of JuMP_Prob <: Prob
Here we use the JuMP modelling framework
https://github.com/jump-dev/JuMP.jl
"""

using JuMP

mutable struct JuMP_Prob <: Prob
    ismin::Bool
    objects::Vector
    model::JuMP.Model
    rhs::Dict
    isrhsupdated::Bool
    horizons::Vector{Horizon}
    
    function JuMP_Prob(objects, isminprob::Bool, model)
        if objects isa Dict
            objects = [o for o in values(objects)]
        end

        p = new(isminprob, objects, model, Dict(), false)

        setsilent!(p)

        if ismin(p)
            @objective(p.model, Min, 0)
        else
            @objective(p.model, Max, 0)
        end

        horizons = Set(gethorizon(x) for x in getobjects(p) if x isa Balance)
        for horizon in horizons
            build!(horizon, p)
        end
        horizons = Horizon[i for i in horizons]
        p.horizons = horizons

        for obj in getobjects(p)
            build!(p, obj)
        end

        for obj in getobjects(p)
            setconstants!(p, obj)
        end

        return p
    end
end

function setsilent!(p::JuMP_Prob)
    set_silent(p.model)
    return
end

function unsetsilent!(p::JuMP_Prob)
    unset_silent(p.model)
    return 
end

getobjects(p::JuMP_Prob) = p.objects

gethorizons(p::JuMP_Prob) = p.horizons

ismin(p::JuMP_Prob) = p.ismin

function addvar!(p::JuMP_Prob, id::Id, N::Int)
    name = getname(id)
    p.model[Symbol(name)] = @variable(p.model, [1:N], base_name=name)    
    return
end

function addeq!(p::JuMP_Prob, id::Id, N::Int)
    name = getname(id)
    p.model[Symbol(name)] = @constraint(p.model, [t in 1:N], 0 == 0, base_name=name)
    p.rhs[id] = [Dict{Any, Float64}() for __ in 1:N]
    return
end

function addle!(p::JuMP_Prob, id::Id, N::Int)
    name = getname(id)
    p.model[Symbol(name)] = @constraint(p.model, [t in 1:N], 0 <= 0, base_name=name)
    p.rhs[id] = [Dict{Any, Float64}() for __ in 1:N]
    return
end

function addge!(p::JuMP_Prob, id::Id, N::Int)
    name = getname(id)
    p.model[Symbol(name)] = @constraint(p.model, [t in 1:N], 0 >= 0, base_name=name)
    p.rhs[id] = [Dict{Any, Float64}() for __ in 1:N]
    return
end

function solve!(p::JuMP_Prob)
    if p.isrhsupdated
        for id in keys(p.rhs)
            for i in eachindex(p.rhs[id])
                name = Symbol(getname(id))
                value = sum(values(p.rhs[id][i]))
                set_normalized_rhs(p.model[name][i], value)
            end
        end
        p.isrhsupdated = false
    end

    optimize!(p.model)

    if termination_status(p.model) != MOI.OPTIMAL
        MOI.Utilities.reset_optimizer(p.model)
        optimize!(p.model)
    end

    @assert termination_status(p.model) == MOI.OPTIMAL
    return
end

function setconcoeff!(p::JuMP_Prob, conid::Id, 
        varid::Id, conix::Int, varix::Int, value::Float64)
    con = p.model[Symbol(getname(conid))]
    var = p.model[Symbol(getname(varid))]
    set_normalized_coefficient(con[conix], var[varix], value)
    return
end

function setub!(p::JuMP_Prob, varid::Id, i::Int, value::Float64)
    var = p.model[Symbol(getname(varid))]
    set_upper_bound(var[i], value)
    return
end

function setlb!(p::JuMP_Prob, varid::Id, i::Int, value::Float64)
    var = p.model[Symbol(getname(varid))]
    set_lower_bound(var[i], value)
    return
end

function setobjcoeff!(p::JuMP_Prob, varid::Id, i::Int, value::Float64)
    var = p.model[Symbol(getname(varid))]
    set_objective_coefficient(p.model, var[i], value)
    return
end

function setrhsterm!(p::JuMP_Prob, conid::Id, traitid::Id, i::Int, value::Float64)
    p.rhs[conid][i][traitid] = value
    p.isrhsupdated = true
    return
end

function getconcoeff(p::JuMP_Prob, conid::Id, 
        varid::Id, conix::Int, varix::Int)
    con = p.model[Symbol(getname(conid))]
    var = p.model[Symbol(getname(varid))]
    return normalized_coefficient(con[conix], var[varix])
end

function getub(p::JuMP_Prob, varid::Id, i::Int)
    var = p.model[Symbol(getname(varid))]
    return upper_bound(var[i])
end

function getlb(p::JuMP_Prob, varid::Id, i::Int)
    var = p.model[Symbol(getname(varid))]
    return lower_bound(var[i])
end

function getobjcoeff(p::JuMP_Prob, varid::Id, i::Int)
    var = p.model[Symbol(getname(varid))]
    return objective_coefficient(p.model, var[i], value)
end

function getrhsterm(p::JuMP_Prob, conid::Id, traitid::Id, i::Int)
    return p.rhs[conid][i][traitid]
end

function hasrhsterm(p::JuMP_Prob, conid::Id, traitid::Id, i::Int)
    return haskey(p.rhs[conid][i], traitid)
end

getobjectivevalue(p::JuMP_Prob) = objective_value(p.model) 

getvarvalue(p::JuMP_Prob, id::Id, i::Int) = value(p.model[Symbol(getname(id))][i])

getcondual(p::JuMP_Prob, id::Id, i::Int)  = dual(p.model[Symbol(getname(id))][i])

getfixvardual(p::JuMP_Prob, varid::Id, varix::Int)  = dual(FixRef(p.model[Symbol(getname(varid))][varix]))

# --- Added to fix state variables ---

function makefixable!(p::JuMP_Prob, varid::Id, varix::Int)
    return
end

function fix!(p::JuMP_Prob, varid::Id, varix::Int, value::Float64)
    fix(p.model[Symbol(getname(varid))][varix], value, force=true)
    return
end

function unfix!(p::JuMP_Prob, varid::Id, varix::Int)
    unfix(p.model[Symbol(getname(varid))][varix])
    return
end



