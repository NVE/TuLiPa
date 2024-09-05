struct ElasticDemand{B, P, T} <: Demand
    id::Id
    balance::B
    firm_demand::P
    normal_price::T
    price_elasticity::T
    min_price::T 
    max_price::T
    N::Int64
    segment_capacities::Vector{Float64}
    reserve_prices::Vector{Float64}
    
    function ElasticDemand(
            id::Id, 
            balance::B, 
            firm_demand_param::P, 
            price_elasticity::T, 
            normal_price::T, 
            max_price::T, 
            min_price::T,
            threshold::T
        ) where {B <: Balance, P <: Param, T <: Real} 

        min_relative_demand = price_to_relative_demand(normal_price, price_elasticity, max_price)
        max_relative_demand = price_to_relative_demand(normal_price, price_elasticity, min_price)

        L, reserve_prices, N = optimize_segments(
            normal_price, 
            price_elasticity, 
            min_relative_demand, 
            max_relative_demand, 
            threshold
        ) 

        reserve_prices = adjust_prices_for_demand_curve_area(
            normal_price, 
            price_elasticity, 
            min_relative_demand, 
            max_relative_demand,
            L, 
            reserve_prices
        )

        segment_capacities = [first(L), diff(L)...]

        new{B, P, Real}(
            id, 
            balance, 
            firm_demand_param, 
            normal_price, 
            price_elasticity, 
            min_price, 
            max_price, 
            N,
            segment_capacities, 
            reserve_prices
        )
    end
end

getid(var::ElasticDemand) = var.id
getbalance(var::ElasticDemand) = var.balance
getparent(var::ElasticDemand) = var.balance

function getdemand(p::Prob, var::ElasticDemand, timeix::Int64)
    total_demand = 0
    for seg_no in 1:var.N
        seg_id = create_segment_id(var, seg_no)
        total_demand += getvarvalue(p, seg_id, timeix)
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

function create_segment_id(var::ElasticDemand, seg_no::Int)
    return Id(var.id.conceptname, string(var.id.instancename, seg_no))
end

function adjust_prices_for_demand_curve_area(
        normal_price, 
        price_elasticity, 
        min_relative_demand, 
        max_relative_demand,
        L, 
        reserve_prices
    )
    max_price = reserve_prices[1]
    demand_integral = (p_normal, e, f) -> (p_normal .* e .* f.^(1 + 1/e))/(1 + e)
    demand_area = (p_normal, e, f1, f2) -> demand_integral(p_normal, e, f2) - demand_integral(p_normal, e, f1)
    demand_approx_area = (p, seg) -> sum(p .* seg)
    factor = (p_normal, e, f1, f2, p, seg) -> demand_area(p_normal, e, f1, f2) / demand_approx_area(p, seg)
    reserve = reserve_prices[1:end-1]
    seg = diff(L)
    p_factor = factor(
        normal_price, 
        price_elasticity, 
        min_relative_demand, 
        max_relative_demand, 
        reserve, 
        seg
    ) 
    reserve_prices = reserve * p_factor
    insert!(reserve_prices, 1, max_price)
    return reserve_prices
end

function optimize_segments(normal_price, price_elasticity, min_relative_demand, max_relative_demand, tolerance; max_depth = 6)
    f = (x) -> relative_demand_to_price(normal_price, price_elasticity, x)
    x_points = adaptive_sampling(f, min_relative_demand, max_relative_demand, tolerance, max_depth)
    y_points = relative_demand_to_price(normal_price, price_elasticity, x_points)
    N = length(x_points)
    @assert N <= 10
    return x_points, y_points, N
end

function adaptive_sampling(f, x_start, x_end, tolerance, max_depth)
    x_points = [x_start, x_end]
    y_points = [f(x_start), f(x_end)]
    tolerance *= abs(y_points[1] - y_points[2])
    function recursive_sampling(x0, x1, y0, y1, depth)
        depth > max_depth && return
        x_mid = (x0 + x1) / 2
        y_mid = f(x_mid)
        y_interp = (y0 + y1) / 2
        if abs(y0 - y_interp) > tolerance
            push!(x_points, x_mid)
            push!(y_points, y_mid)
            recursive_sampling(x0, x_mid, y0, y_mid, depth + 1)
            recursive_sampling(x_mid, x1, y_mid, y1, depth + 1)
        end
    end
    recursive_sampling(x_start, x_end, y_points[1], y_points[2], 0)
    sort!(x_points)
    return x_points
end

function build!(p::Prob, var::ElasticDemand)
    T = getnumperiods(gethorizon(var.balance))
    for i in 1:var.N
        addvar!(p, create_segment_id(var, i), T)
    end
end

function setconstants!(p::Prob, var::ElasticDemand)
    balanceid = getid(var.balance)
    T = getnumperiods(gethorizon(var.balance))
    for i in 1:var.N
        varid = create_segment_id(var, i)
        for t in 1:T
            setconcoeff!(p, balanceid, varid, t, t, 1.0)
            setobjcoeff!(p, varid, t, -var.reserve_prices[i])
            setlb!(p, varid, t, 0.0)
        end
    end
 end

function _update_ub(p, horizon, start, var, varid, t, i)
    querystart = getstarttime(horizon, t, start)
    querydelta = gettimedelta(horizon, t)
    value = getparamvalue(var.firm_demand, querystart, querydelta)
    setub!(p, varid, t, value * var.segment_capacities[i])
end

function stateful_update(p, horizon, start, var, varid, T, i)
    for t in 1:T
        _update_ub(p, horizon, start, var, varid, t, i)
    end
end

function non_stateful_update(p, horizon, start, var, varid, T, i)
    for t in 1:T
        (future_t, ok) = mayshiftfrom(horizon, t)
        if ok
            value = getub(p, varid, future_t)
            setub!(p, varid, t, value)
        end
    end
    for t in 1:T
        if mustupdate(horizon, t)
            _update_ub(p, horizon, start, var, varid, t, i)
        end
    end
end

function update!(p::Prob, var::ElasticDemand, start::ProbTime)
    horizon = gethorizon(var.balance)
    T = getnumperiods(horizon)
    update_func = isstateful(var.firm_demand) ? stateful_update : non_stateful_update
    for i in 1:var.N
        varid = create_segment_id(var, i)
        update_func(p, horizon, start, var, varid, T, i)
    end
end

function assemble!(var::ElasticDemand)::Bool   
    return true
end

function includeElasticDemand!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
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
    price_elasticity = getdictvalue(value, "price_elasticity", Real, elkey)
    normal_price = getdictvalue(value, "normal_price", Real, elkey)
    max_price = getdictvalue(value, "max_price", Real, elkey)
    min_price = getdictvalue(value, "min_price", Real, elkey)
    threshold = getdictvalue(value, "threshold", Real, elkey)

    min_price <= normal_price <= max_price || error("Normal price not between max and min price for $(elkey)")

    toplevel[objkey] = ElasticDemand(objkey, toplevel[balancekey], 
        firm_demand_param, price_elasticity, normal_price, max_price, min_price, threshold
    )
    return (true, deps)    
end

INCLUDEELEMENT[TypeKey(DEMAND_CONCEPT, "ElasticDemand")] = includeElasticDemand!
