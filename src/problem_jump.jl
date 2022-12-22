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
            objects = [o for o in values(objects)]
        end

        p = new(objects, model, Dict(), false)

        setsilent!(p)

        @objective(p.model, Min, 0)

        # Initialize/build all horizons and model objects
        # (mostly creating variables, constraints and objective function)
        # The generic function build! has different methods depending on the inputed object
        # Some objects will again call build! on its internal traits
        horizons = Set(gethorizon(x) for x in getobjects(p) if x isa Balance)
        for horizon in horizons
            build!(horizon, p)
        end
        horizons = Horizon[i for i in horizons]
        p.horizons = horizons

        for obj in getobjects(p)
            build!(p, obj)
        end

        # Set all parameters and coefficients that will be the same 
        # regardless of the problem time and period in the horizon. 
        # These only need to be updated once
        # The generic function setconstants! has different methods depending on the inputed object
        # Some objects will again call setconstants! on its internal traits
        for obj in getobjects(p)
            setconstants!(p, obj)
        end

        return p
    end
end

getobjects(p::JuMP_Prob) = p.objects
gethorizons(p::JuMP_Prob) = p.horizons

# -------- Update problem for given problem time --------------
function update!(p::JuMP_Prob, start::ProbTime)
    # Update horizons that need to dynamically update
    for horizon in gethorizons(p)
        update!(horizon, start)
    end
    
    # Loop through all model objects. Set parameters and coefficients that
    # depend on the problem time and period in the horizon.
    # The generic function update! has different methods depending on the inputed object
    # Some objects will again call update! on its internal traits
    for obj in getobjects(p)
        update!(p, obj, start)
    end
end

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

    @assert termination_status(p.model) == MOI.OPTIMAL
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
    return objective_coefficient(p.model, var[i], value)
end

function getrhsterm(p::JuMP_Prob, conid::Id, traitid::Id, i::Int)
    return p.rhs[conid][i][traitid]
end

getobjectivevalue(p::JuMP_Prob) = objective_value(p.model) 

getvarvalue(p::JuMP_Prob, id::Id, i::Int) = value(p.model[Symbol(getname(id))][i])

getcondual(p::JuMP_Prob, id::Id, i::Int)  = dual(p.model[Symbol(getname(id))][i])

getfixvardual(p::JuMP_Prob, varid::Id, varix::Int)  = dual(FixRef(p.model[Symbol(getname(varid))][varix]))

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



