"""
Flow based constraints for power transfer between price areas
"""


mutable struct BaseFlowBased{T <: Real} <: FlowBased
	id::Id
	balance::Balance
	ram::Union{Nothing, Param}
	ptdfs::Array{T}
	ptdfs_names::Vector{Id}
	line_in::Dict{String, Vector{Flow} } # Flow
	line_out::Dict{String, Vector{Flow} }
	is_flow::Bool
    horizon::Horizon

	updated_test::Any ###

	function BaseFlowBased(
		id::Id,
		balance::Balance,
		ram::Union{Nothing, Param},
		ptdfs::Array{T},
		ptdfs_names::Vector{Id},
		line_in::Dict{String, Vector{Flow}},
		line_out::Dict{String, Vector{Flow} },
		is_flow::Bool,
        horizon::Horizon
	) where {T <: Real}
		new{T}(id, balance, ram, ptdfs, ptdfs_names, line_in, line_out, is_flow, horizon, false) ###
	end
end

getid(var::BaseFlowBased) = var.id
getparent(var::BaseFlowBased) = var.balance
get_ptdfs(var::BaseFlowBased) = var.ptdfs
setconstants!(p::Prob, var::BaseFlowBased) = nothing
assemble!(var::BaseFlowBased)::Bool = true
replacebalance!(x::BaseFlowBased, coupling, modelobjects) = nothing
gethorizon(var::BaseFlowBased) = var.horizon

#TODO better solution
# Need id for both direction for the flow (FlowBased are connected to a flow)
# Can be done by modifying the name, only works for a specific naming convention
function reverse_transm_name(name)
	name = replace(name, "Transm_" => "")
	name = split(name, "->")
	return "Transm_$(name[2])->$(name[1])"
end

function get_right_hand_side_flows(line_id)
	line_flow_in = Id("Flow", line_id.instancename)
	line_flow_out = Id("Flow", reverse_transm_name(line_id.instancename))
	return (line_flow_in, line_flow_out)
end

# TODO Use @expression instead?

# Create one constraint like this for the line_id
# FlowA_B - Flow_B_A == ptdf[1]*NP_A + ptdf[2]*NP_B + ptdf[3]*NP_C
# Move everything to left hand side:
# FlowA_B - Flow_B_A - ptdf[1]*NP_A - ptdf[2]*NP_B - ptdf[3]*NP_C == 0

# Netposition NP calculation
# NP is defined as the excess flow going out from the area which is FlowA_B and FlowA_C for area A
# but also need to subtract the flow going into the area which is Flow_B_A and Flow_C_A.
# NP_A is then (Flow_A_B + Flow_A_C) - (Flow_B_A + Flow_C_A)

function create_rhs_of_constraints(line_id::Id)
    coeffs_dict = Dict()
    line_flow_in, line_flow_out = get_right_hand_side_flows(line_id)
    coeffs_dict[line_flow_out] = -1 # Flow_B_A
    coeffs_dict[line_flow_in] = 1 # Flow_A_B
    return coeffs_dict
end

function calc_coeffs(line_id::Id, ptdfs_names::Vector{Id}, ptdfs::Vector{Float64}, var::BaseFlowBased)

    coeffs_dict = var.is_flow ? create_rhs_of_constraints(line_id) : Dict()

	for (area, ptdf) in zip(ptdfs_names, ptdfs)

		ptdf == 0 && continue

		for flow_obj in var.line_out[area.instancename] # i.e. (Flow_A_B + Flow_A_C)
			flow = flow_obj.id
			ptdf_val = -1 * ptdf # Moved to left hand side of eq so flipped sign
			if flow in keys(coeffs_dict)
				ptdf_val = coeffs_dict[flow] + ptdf_val
			end
			coeffs_dict[flow] = ptdf_val
		end

		for flow_obj in var.line_in[area.instancename]# i.e. (Flow_B_A + Flow_C_A)

			#@assert(flow_obj.arrows[1].isingoing)
			in_arrow = flow_obj.arrows[1].balance.id.instancename == area.instancename ? flow_obj.arrows[1] : flow_obj.arrows[2]
			#@assert(!in_arrow.isingoing)

			flow = flow_obj.id
			ptdf_val = ptdf
			if flow in keys(coeffs_dict)
				ptdf_val = coeffs_dict[flow] + ptdf_val
			end
			coeffs_dict[flow] = ptdf_val
		end
	end
	return coeffs_dict
end

function non_flow_setconcoeff_from_ptdf(p::Prob, T::Int64, start::ProbTime, var::BaseFlowBased, sign, id)
	line_id = id
	ptdfs_names = var.ptdfs_names
	ptdfs = var.ptdfs
	ram = var.ram
    coeffs_dict = calc_coeffs(line_id, ptdfs_names, ptdfs, var)
	for t in 1:T
		for flow in keys(coeffs_dict)
			setconcoeff!(p, line_id, flow, t, t, sign * Float64(coeffs_dict[flow]))
		end
		querystart = getstarttime(var.horizon, t, start)
		querydelta = gettimedelta(var.horizon, t)
		value = getparamvalue(ram, querystart, querydelta)
		setrhsterm!(p, line_id, line_id, t, value)
	end
end

function setconcoeff_from_ptdf(p::Prob, T::Int64, var::BaseFlowBased)
	line_id = var.id
	ptdfs_names = var.ptdfs_names
	ptdfs = var.ptdfs
	coeffs_dict = calc_coeffs(line_id, ptdfs_names, ptdfs, var)
	for t in 1:T
		for flow in keys(coeffs_dict)
			setconcoeff!(p, line_id, flow, t, t, Float64(coeffs_dict[flow]))
		end
	end
end

function build!(p::Prob, var::BaseFlowBased)
	T = getnumperiods(gethorizon(var))
    if var.is_flow
        addeq!(p, var.id, T)
    else
		addle!(p, Id(var.id.conceptname, var.id.instancename * "in"), T)
		addle!(p, Id(var.id.conceptname, var.id.instancename * "out"), T)
    end
end



function update!(p::Prob, var::BaseFlowBased, start::ProbTime)
	if !var.updated_test
		T = getnumperiods(gethorizon(var))
		if var.is_flow
			setconcoeff_from_ptdf(p, T, var)
		else
			non_flow_setconcoeff_from_ptdf(p, T, start, var, 1,  Id(var.id.conceptname, var.id.instancename * "in"))
			non_flow_setconcoeff_from_ptdf(p, T, start, var, -1, Id(var.id.conceptname, var.id.instancename * "out"))
		end
		var.updated_test = true
	end
end

"""
#function update!(p::Prob, var::BaseFlowBased, start::ProbTime)
#	nothing
#end

function setconstants!(p::Prob, var::BaseFlowBased)
	T = getnumperiods(gethorizon(var))
    if var.is_flow
        setconcoeff_from_ptdf(p, T, var)
	else
		dummytime = ConstantTime()
		non_flow_setconcoeff_from_ptdf(p, T, dummytime, var, 1,  Id(var.id.conceptname, var.id.instancename * "in"))
		non_flow_setconcoeff_from_ptdf(p, T, dummytime, var, -1, Id(var.id.conceptname, var.id.instancename * "out"))
    end
end
"""

function includeBaseFlowBased!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
	checkkey(toplevel, elkey)
	deps = Id[]
    is_flow = getdictvalue(value, "border", Any, elkey)
    ptdfs = getdictvalue(value, "ptdfs", Array, elkey)
	ptdfs_names = getdictvalue(value, "ptdfs_names", Array{String}, elkey)
	np_lookup = getdictvalue(value, "np_lookup", Dict, elkey)
	ramkey = getdictvalue(value, "max_cap", Any, elkey)

	ram = nothing
	if !is_flow
		ram_param_id = Id(PARAM_CONCEPT, ramkey)
		push!(deps, ram_param_id)	
		haskey(lowlevel, ram_param_id) || return (false, deps)
		ram = lowlevel[ram_param_id]
	end

	price_area_balances = Vector{Id}([])
	for area_name in ptdfs_names
		area_id = Id(BALANCE_CONCEPT, area_name)
		push!(deps, area_id)
		haskey(toplevel, area_id) || return (false, deps)
		push!(price_area_balances, area_id)
	end

	line_in = Dict(zip(ptdfs_names, [Vector{Flow}() for area in ptdfs_names]))
	for area in ptdfs_names
		for flowkey in np_lookup["$(area)_in"]
			push!(deps, flowkey)
			haskey(toplevel, flowkey) || return (false, deps)
			push!(line_in[area], toplevel[flowkey])
		end
	end

	line_out = Dict(zip(ptdfs_names, [Vector{Flow}() for area in ptdfs_names]))
	for area in ptdfs_names
		for flowkey in np_lookup["$(area)_out"]
			push!(deps, flowkey)
			haskey(toplevel, flowkey) || return (false, deps)
			push!(line_out[area], toplevel[flowkey])
		end
	end

    # Better way to get horizon when transm line is not connected to a flow?
    balances = [toplevel[balance_id] for balance_id in price_area_balances] 
    @assert(length(Set([gethorizon(balance) for balance in balances])) == 1)
    horizon = gethorizon(balances[1].commodity)

    objkey = getobjkey(elkey)
	toplevel[objkey] = BaseFlowBased(objkey, balances[1], ram, ptdfs, price_area_balances, line_in, line_out, is_flow, horizon)
	return (true, deps)
end

INCLUDEELEMENT[TypeKey(FLOW_BASED_CONCEPT, "BaseFlowBased")] = includeBaseFlowBased!
