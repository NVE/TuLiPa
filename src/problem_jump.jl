"""
Implementation of JuMP_Prob <: Prob (see also abstracttypes.jl)
Here we use the JuMP modelling framework
https://github.com/jump-dev/JuMP.jl

JuMP_Prob consist of:
- JuMP Model object with solver, solver settings and problem 
formulation built incrementally from model objects
- Model objects that represent concepts 
(e.g. power plants, power markets, water balances etc...)
They know how they are connected to other model objects
and how to interact with the optimization model
(e.g. add variables and constraints, and update parameters wrt. time input)
- An interface to build, update and solve the problem, add solver 
settings and query results from the solution 
- Horizons can similar to model objects be built and updated 
(needed for more complex horizons). They are therefore collected from 
the model objects and stored in a list to make the updating more efficient. 
- The right hand side (rhs) of constraints can consist of multiple 
parameters. When these parameters are updated they are first put into 
JuMP_Prob. Right before the problem is solved, if any parameters have 
been updated, the rhs (sum of the parameters) is added to the JuMP Model. 
"""

using JuMP

# ------- Concrete type and constructor ----------------
mutable struct JuMP_Prob <: Prob
    model::JuMP.Model
    objects::Vector
    horizons::Vector{Horizon}
    rhs::Dict
    isrhsupdated::Bool

    # Initialize JuMP_Prob
    function JuMP_Prob(objects, model)
        if objects isa Dict
            objects = [o for o in collect(values(objects))]
        end

        p = new(model, objects, [], Dict(), false)

        setsilent!(p)

        @objective(p.model, Min, 0)

        buildhorizons!(p)
        build!(p)
        setconstants!(p)

        return p
    end
    function JuMP_Prob()
        new(JuMP.Model(), [], [], Dict(), false)
    end
end

getobjects(p::JuMP_Prob) = p.objects
gethorizons(p::JuMP_Prob) = p.horizons

# Functions used by objects or traits to update the problem -------------
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

function setconcoeff!(p::JuMP_Prob, conid::Id, 
        varid::Id, conix::Int, varix::Int, value::Float64)
    con = p.model[Symbol(getname(conid))]
    var = p.model[Symbol(getname(varid))]
    set_normalized_coefficient(con[conix], var[varix], value)
    return
end

function setub!(p::JuMP_Prob, varid::Id, i::Int, value::Float64)
    var = p.model[Symbol(getname(varid))]
    if !JuMP._moi_is_fixed(JuMP.backend(p.model), var[i]) # skip updating upper and lower bounds of fixed variables, JuMP gives error, TODO
        set_upper_bound(var[i], value)
    end
    return
end

function setlb!(p::JuMP_Prob, varid::Id, i::Int, value::Float64)
    var = p.model[Symbol(getname(varid))]
    if !JuMP._moi_is_fixed(JuMP.backend(p.model), var[i]) # skip updating upper and lower bounds of fixed variables, JuMP gives error, TODO
        set_lower_bound(var[i], value)
    end
    return
end

function setobjcoeff!(p::JuMP_Prob, varid::Id, i::Int, value::Float64)
    var = p.model[Symbol(getname(varid))]
    set_objective_coefficient(p.model, var[i], value)
    return
end

function hasrhsterm(p::JuMP_Prob, conid::Id, traitid::Id, i::Int)
    return haskey(p.rhs[conid][i], traitid)
end

function setrhsterm!(p::JuMP_Prob, conid::Id, traitid::Id, i::Int, value::Float64)
    p.rhs[conid][i][traitid] = value
    p.isrhsupdated = true
    return
end

# ---------- Solve problem and solver settings -------
function solve!(p::JuMP_Prob)
    # Update RHS of equations
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

    if termination_status(p.model) != MOI.OPTIMAL
        status = termination_status(p.model)
        modelid = rand(1:999)
        try
            threadid = myid()
            write_to_file(p.model, "failed_model_status_$(status)_thread_$(threadid)_$(modelid).mps")
        catch
            write_to_file(p.model, "failed_model_status_$(status)_$(modelid).mps")
        end

        # https://jump.dev/JuMP.jl/stable/tutorials/getting_started/debugging/#Debugging-an-infeasible-model
        if termination_status(p.model) == MOI.INFEASIBLE
            map = TuLiPa.JuMP.relax_with_penalty!(p.model)
            TuLiPa.JuMP.optimize!(p.model)
            for (con, penalty) in map
                violation = TuLiPa.JuMP.value(penalty)
                if violation > 0
                    println("Constraint `$(TuLiPa.JuMP.name(con))` is violated by $violation")
                end
            end
        end
        error("Model $(modelid) failed with status $(status)")
    end

    return
end

function setsilent!(p::JuMP_Prob)
    set_silent(p.model)
    return
end

function unsetsilent!(p::JuMP_Prob)
    unset_silent(p.model)
    return 
end

# --------- Query results from problem ---------------
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
    return get(objective_function(p.model).terms, var[i], 0.0)
end

function getrhsterm(p::JuMP_Prob, conid::Id, traitid::Id, i::Int)
    return p.rhs[conid][i][traitid]
end

getobjectivevalue(p::JuMP_Prob) = objective_value(p.model) 

getvarvalue(p::JuMP_Prob, id::Id, i::Int) = value(p.model[Symbol(getname(id))][i])

getcondual(p::JuMP_Prob, id::Id, i::Int)  = dual(p.model[Symbol(getname(id))][i])

getfixvardual(p::JuMP_Prob, varid::Id, varix::Int)  = dual(FixRef(p.model[Symbol(getname(varid))][varix]))

# TODO: Implement
setwarmstart!(::JuMP_Prob, ::Bool) = nothing
# getwarmstart setwarmstart!(p::JuMP_Prob

# ------- Fix state variables for boundary conditions ------------

function makefixable!(::JuMP_Prob, ::Id, ::Int)
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



