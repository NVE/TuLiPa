mutable struct BaseElasticDemand <: ElasticDemand
    id::Id
    balance::Balance
    firm_demand::Union{Param, Nothing}
    normal_price::Float64
    price_elasticity::Float64
    min_price::Float64 
    max_price::Float64
    N::Int64
    segment_capacities::Vector{Float64}
    reserve_prices::Vector{Float64}
    
    function BaseElasticDemand(id::Id, balance::Balance, 
        firm_demand_param::Param, price_elasticity::Float64, normal_price::Float64, max_price::Float64, min_price::Float64)  

        N = 10 # hardcoded for now, TODO: Find best N (or best segments) to approximate PQ curve.

        min_relative_demand = price_to_relative_demand(normal_price, price_elasticity, max_price) # example 0.95
        max_relative_demand = price_to_relative_demand(normal_price, price_elasticity, min_price) # example 1.05
        L = [i for i in range(min_relative_demand, max_relative_demand, N)]
        reserve_prices = relative_demand_to_price(normal_price, price_elasticity, L) 
        segment_capacities = [first(L), diff(L)...] # the sum of this will the max_relative_demand (example 1.05)

        new(id, 
            balance, 
            firm_demand_param, 
            normal_price, 
            price_elasticity, 
            min_price, 
            max_price, 
            N,
            segment_capacities, 
            reserve_prices)
    end
end

getid(var::BaseElasticDemand) = var.id
getbalance(var::BaseElasticDemand) = var.balance

function getdemand(p::Prob, var::BaseElasticDemand, timeix::Int64)
    total_demand = 0
    for seg_no in 1:var.N
        seg_id = create_segment_id(var, seg_no)
        ref = p.model[Symbol(getname(seg_id))]
        total_demand += value(ref[timeix])
    end
    return total_demand
end

# Expects f divided by f_ref
function relative_demand_to_price(normal_price, price_elasticity, f)
    p_ref = normal_price
    e = price_elasticity
    return p_ref .* f.^(1/e)
end

# Price_to_demand divided by f_ref
function price_to_relative_demand(normal_price, price_elasticity, p)
    p_ref = normal_price
    e = price_elasticity
    return (p./p_ref).^e
end

function create_segment_id(var::BaseElasticDemand, seg_no::Int)
    return Id(var.id.conceptname, string(var.id.instancename, seg_no))
end

function build!(p::Prob, var::BaseElasticDemand)
    T = getnumperiods(gethorizon(var.balance))
    for i in 1:var.N
        addvar!(p, create_segment_id(var, i), T)
    end
end

function setconstants!(p::Prob, var::BaseElasticDemand)
    balanceid = getid(getbalance(var))
    T = getnumperiods(gethorizon(var.balance))
    for i in 1:var.N
        varid = create_segment_id(var, i)
        for t in 1:T
            setconcoeff!(p, balanceid, varid, t, t, 1.0)
        end
    end
    for i in 1:var.N
        varid = create_segment_id(var, i)
        for t in 1:T
            setobjcoeff!(p, varid, t, -var.reserve_prices[i])
        end
    end
end

function update!(p::Prob, var::BaseElasticDemand, start::ProbTime)
    T = getnumperiods(gethorizon(var.balance))
    for i in 1:var.N
        varid = create_segment_id(var, i)
        for t in 1:T
            querystart = getstarttime(var.balance.horizon, t, start)
            querydelta = gettimedelta(var.balance.horizon, t)
            value = getparamvalue(var.firm_demand, querystart, querydelta)
            setub!(p, varid, t, value * var.segment_capacities[i])
            setlb!(p, varid, t, 0.0)
        end
    end
end

function assemble!(var::BaseElasticDemand)::Bool   
    return true
end

function includeBaseElasticDemand!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(toplevel, elkey)
    deps = Id[]
    balancename = getdictvalue(value, BALANCE_CONCEPT, String, elkey)
    balancekey = Id(BALANCE_CONCEPT, balancename)
    push!(deps, balancekey)

    (id, firm_demand_param, ok) = getdictparamvalue(lowlevel, elkey, value)
    push!(deps, id)

    ok || return (false, deps)
    haskey(toplevel, balancekey) || return (false, deps)

    objkey = getobjkey(elkey)
    price_elasticity = getdictvalue(value, "price_elasticity", Float64, elkey)
    normal_price = getdictvalue(value, "normal_price", Float64, elkey)
    max_price = getdictvalue(value, "max_price", Float64, elkey)
    min_price = getdictvalue(value, "min_price", Float64, elkey)

    @assert min_price <= normal_price <= max_price

    toplevel[objkey] = BaseElasticDemand(objkey, toplevel[balancekey], 
        firm_demand_param, price_elasticity, normal_price, max_price, min_price
    )
    return (true, deps)    
end

ELASTIC_DEMAND_CONCEPT = "ElasticDemand"
INCLUDEELEMENT[TypeKey(ELASTIC_DEMAND_CONCEPT, "BaseElasticDemand")] = includeBaseElasticDemand!
