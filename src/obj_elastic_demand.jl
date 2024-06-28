mutable struct ElasticPowerDemand
    id::Id
    balance::Balance
    firm_demand::Union{Param, Nothing} # demand from input used today?
    normal_price::Float64 # new input data?
    price_elasticity::Float64 # new input data?

    segment_capacities::Vector{Float64}
    reserve_prices::Vector{Float64}
    
    function ElasticPowerDemand(id::Id, balance::Balance)  

        segment_capacities = [i for i in range(1,10)]
        reserve_prices = [i for i in range(1,10)]

        new(id, balance, nothing, 0, 0, segment_capacities, reserve_prices)
    end
end

function calc_price_demand(f_ref = 10, p_ref = 5)
    e = -0.025
    granularity = 10
    f = [i for i in range(1, granularity)]
    p  = p_ref .* (f./f_ref).^e
    return p
end

getid(var::ElasticPowerDemand) = var.id
getbalance(var::ElasticPowerDemand) = var.balance


function build!(p::Prob, var::ElasticPowerDemand)
    
    balance = getbalance(var)
    
    for seg in var.segment_capacities
        addvar!(p, var.id, getnumperiods(balance.horizon))
    end
    return
    
end

function setconstants!(p::Prob, var::ElasticPowerDemand)
    #!isnothing(var.sumcost) && setconstants!(p, var, var.sumcost)

    #setconstants!(p, var, var.lb)
    #isnothing(var.ub) || setconstants!(p, var, var.ub)

    #for a in var.arrows
    #   setconstants!(p, var, a)
    #end
    return
end

function update!(p::Prob, var::ElasticPowerDemand, start::ProbTime)
    #!isnothing(var.sumcost) && update!(p, var, var.sumcost, start)

    #update!(p, var, var.lb, start)

    #isnothing(var.ub) || update!(p, var, var.ub, start)

    #for a in var.arrows
    #    update!(p, var, a, start)
    #end

    return
end

function assemble!(var::ElasticPowerDemand)::Bool   
	#var.balance
    return true
end

# ------ Include dataelements -------
function includeBaseElasticDemand!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)
    checkkey(toplevel, elkey)
    
    deps = Id[]
    
    balancename = getdictvalue(value, BALANCE_CONCEPT, String, elkey)
    balancekey = Id(BALANCE_CONCEPT, balancename)

    push!(deps, balancekey)
	haskey(toplevel, balancekey) || return (false, deps)
    
	objkey = getobjkey(elkey)
	
    toplevel[objkey] = ElasticPowerDemand(objkey, toplevel[balancekey])
    
    return (true, deps)    
end

ELASTIC_DEMAND_CONCEPT = "Elastic_demand_concept"

INCLUDEELEMENT[TypeKey(ELASTIC_DEMAND_CONCEPT, "ElasticPowerDemand")] = includeBaseElasticDemand!