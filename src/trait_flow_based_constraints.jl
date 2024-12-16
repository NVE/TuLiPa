"""
Flow based constraints for power transfer between price areas
"""


struct BaseFlowBased{T <: Real} <: FlowBased
	id::Id
	flow::Union{Flow, Balance, Nothing} # not needed anymore?
	max_cap::Any
	ptdfs::Array{T}
	ptdfs_names::Vector{Id}
	line_in_dict::Any
	line_out_dict::Any
	is_flow::Bool
    horizon

	function BaseFlowBased(
		id::Id,
		flow::Union{Flow, Balance, Nothing},
		max_cap::Any,
		ptdfs::Array{T},
		ptdfs_names::Vector{Id},
		line_in_dict,
		line_out_dict,
		is_flow::Bool,
        horizon,
	) where {T <: Real}
		new{T}(id, flow, max_cap, ptdfs, ptdfs_names, line_in_dict, line_out_dict, is_flow, horizon)
	end
end

getid(trait::BaseFlowBased) = trait.id
#getvar(trait::BaseFlowBased) = trait.flow
getparent(trait::BaseFlowBased) = trait.flow
get_ptdfs(trait::BaseFlowBased) = trait.ptdfs
setconstants!(p::Prob, trait::BaseFlowBased) = nothing
assemble!(trait::BaseFlowBased)::Bool = true
replacebalance!(x::BaseFlowBased, coupling, modelobjects) = nothing # ?
gethorizon(trait::BaseFlowBased) = trait.horizon

#TODO better solution
# Need id for both direction for the flow (FlowBased are connected to a flow)
# Can be done by modifying the name, only works for a specific naming convention
function get_right_hand_side_flows(line_id)
	function reverse_transm_name(name)

		postfix_split = split(name, "|")
		name = postfix_split[1]

		if length(postfix_split) > 1
			postfix = "|$(postfix_split[2])"
		else
			postfix = ""
		end

		name = replace(name, "Transm_" => "")
		name = split(name, "->")
		return "Transm_$(name[2])->$(name[1])$(postfix)"
	end

	line_flow_in = Id("Flow", line_id.instancename)
	line_flow_out = Id("Flow", reverse_transm_name(line_id.instancename))

	return (line_flow_in, line_flow_out)
end

# Create one constraint like this for the line_id

# FlowA_B - Flow_B_A == ptdf[1]*NP_A + ptdf[2]*NP_B + ptdf[3]*NP_C
# Move everything to left hand side:
# FlowA_B - Flow_B_A - ptdf[1]*NP_A - ptdf[2]*NP_B - ptdf[3]*NP_C == 0

# Netposition NP calculation
# NP is defined as the excess flow going out from the area which is FlowA_B and FlowA_C for area A
# but also need to subtract the flow going into the area which is Flow_B_A and Flow_C_A.
# NP_A is then
# NP_A = (Flow_A_B + Flow_A_C) - (Flow_B_A + Flow_C_A)
# TODO use @expression instead?

function create_rhs_of_constraints(line_id)
    coeffs_dict = Dict()
    line_flow_in, line_flow_out = get_right_hand_side_flows(line_id)
    coeffs_dict[line_flow_out] = -1 # Flow_B_A
    coeffs_dict[line_flow_in] = 1 # Flow_A_B
    return coeffs_dict
end

function calc_coeffs(line_id, ptdfs_names, ptdfs, trait)

    coeffs_dict = trait.is_flow ? create_rhs_of_constraints(line_id) : Dict()

	for (area, ptdf) in zip(ptdfs_names, ptdfs)

		ptdf == 0 && continue

		for flow_obj in trait.line_out_dict[area.instancename] # i.e. (Flow_A_B + Flow_A_C)
			flow = flow_obj.id
			ptdf_val = -1 * ptdf # Moved to left hand side of eq so flipped sign
			if flow in keys(coeffs_dict)
				ptdf_val = coeffs_dict[flow] + ptdf_val
			end
			coeffs_dict[flow] = ptdf_val
		end

		for flow_obj in trait.line_in_dict[area.instancename]# i.e. (Flow_B_A + Flow_C_A)

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

function non_flow_setconcoeff_from_ptdf(p::Prob, T::Int64, trait::BaseFlowBased, sign, id)
	line_id = id
	ptdfs_names = trait.ptdfs_names
	ptdfs = trait.ptdfs
	ram = trait.max_cap
    coeffs_dict = calc_coeffs(line_id, ptdfs_names, ptdfs, trait)
	for t in 1:T
		for flow in keys(coeffs_dict)
			setconcoeff!(p, line_id, flow, t, t, sign * Float64(coeffs_dict[flow]))
		end
        setrhsterm!(p, line_id, line_id, t, ram)
	end
end

function setconcoeff_from_ptdf(p::Prob, T::Int64, trait::BaseFlowBased)
	line_id = trait.id
	ptdfs_names = trait.ptdfs_names
	ptdfs = trait.ptdfs
	coeffs_dict = calc_coeffs(line_id, ptdfs_names, ptdfs, trait)
	for t in 1:T
		for flow in keys(coeffs_dict)
			setconcoeff!(p, line_id, flow, t, t, Float64(coeffs_dict[flow]))
		end
	end
end

function build!(p::Prob, trait::BaseFlowBased)
	T = getnumperiods(gethorizon(trait))
    if trait.is_flow
        addeq!(p, trait.id, T)
    else
		addle!(p, Id(trait.id.conceptname, trait.id.instancename * "in"), T)
		addle!(p, Id(trait.id.conceptname, trait.id.instancename * "out"), T)
    end
end

function update!(p::Prob, trait::BaseFlowBased, start::ProbTime)
	T = getnumperiods(gethorizon(trait))

    if trait.is_flow
        setconcoeff_from_ptdf(p, T, trait)
    
	else
		non_flow_setconcoeff_from_ptdf(p, T, trait, 1,  Id(trait.id.conceptname, trait.id.instancename * "in"))
		non_flow_setconcoeff_from_ptdf(p, T, trait, -1, Id(trait.id.conceptname, trait.id.instancename * "out"))
    end
end




function includeBaseFlowBased!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
	checkkey(toplevel, elkey)
	deps = Id[]
    is_flow = getdictvalue(value, "border", Any, elkey)
    ptdfs = getdictvalue(value, "ptdfs", Array, elkey)
	ptdfs_names = getdictvalue(value, "ptdfs_names", Array{String}, elkey)
	max_cap = getdictvalue(value, "max_cap", Any, elkey)	
	np_lookup = getdictvalue(value, "np_lookup", Dict, elkey)

	#ptdfs_names = ["PowerBalance_" * area for area in ptdfs_names] # TODO not depending on naming conventions
	price_area_balances = Vector{Id}([])
	for area_name in ptdfs_names
		area_id = Id(BALANCE_CONCEPT, area_name)
		push!(deps, area_id)
		haskey(toplevel, area_id) || return (false, deps)
		push!(price_area_balances, area_id)
	end

	line_in_dict = Dict(zip(ptdfs_names, [[] for area in ptdfs_names]))
	line_out_dict = Dict(zip(ptdfs_names, [[] for area in ptdfs_names]))
	for area in ptdfs_names
		for flowkey in np_lookup[area*"_in"]
			push!(deps, flowkey)
			haskey(toplevel, flowkey) || return (false, deps)
			push!(line_in_dict[area], toplevel[flowkey])
		end
	end

	for area in ptdfs_names
		for flowkey in np_lookup[area*"_out"]
			push!(deps, flowkey)
			haskey(toplevel, flowkey) || return (false, deps)
			push!(line_out_dict[area], toplevel[flowkey])
		end
	end

    # Better way to get horizon when transm line is not connected to a flow?
    balances = [toplevel[balance_id] for balance_id in price_area_balances] 
    @assert(length(Set([gethorizon(balance) for balance in balances])) == 1)
    horizon = gethorizon(balances[1].commodity)

    objkey = getobjkey(elkey)


	toplevel[objkey] = BaseFlowBased(objkey, balances[1], max_cap, ptdfs, price_area_balances, line_in_dict, line_out_dict, is_flow, horizon)
	return (true, deps)
end

FLOW_BASED_CONCEPT = "FlowBased" # TODO: move
INCLUDEELEMENT[TypeKey(FLOW_BASED_CONCEPT, "BaseFlowBased")] = includeBaseFlowBased!
