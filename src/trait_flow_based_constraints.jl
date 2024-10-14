"""
Flow based constraints for power transfer between price areas
"""


struct BaseFlowBased{T <: Real} <: FlowBased
    id::Id
    flow::Flow
    max_cap::Int64
    ptdfs::Array{T}
    ptdfs_names::Vector{Id}
    function BaseFlowBased(
            id::Id,
            flow::Flow,
            max_cap::Int64,
            ptdfs::Array{T},
            ptdfs_names::Vector{Id}
        ) where {T <: Real}
        new{T}(id, flow, max_cap, ptdfs, ptdfs_names)
    end
end

getid(trait::BaseFlowBased) = trait.id
getvar(trait::BaseFlowBased) = trait.flow
getparent(trait::BaseFlowBased) = trait.flow
get_ptdfs(trait::BaseFlowBased) = trait.ptdfs
setconstants!(p::Prob, trait::BaseFlowBased) = nothing
assemble!(trait::BaseFlowBased)::Bool = true

function addle_from_ptdf(p::Prob, T::Int64, line_id::Id)
    addle!(p, line_id, T)
end

function setrhs_from_ptdf(p::Prob, T::Int64, line_id::Id, max_cap::Int64)
    p.rhs[line_id] = []
    for t in 1:T
        push!(p.rhs[line_id], max_cap)
    end
    p.isrhsupdated = true
end

function setconcoeff_from_ptdf(p::Prob, T::Int64, line_id::Id, ptdfs::Array{<:Real,1}, ptdfs_names::Vector{Id})
    for t in 1:T
        for (transfer_flow_id, ptdf) in zip(ptdfs_names, ptdfs)
            setconcoeff!(p, line_id, transfer_flow_id, t, t, ptdf)
        end
    end
end

function build!(p::Prob, trait::BaseFlowBased)
    T = getnumperiods(gethorizon(getvar(trait)))
    addle_from_ptdf(p, T, trait.id)
end

function get_state()
    return 0
end

function update!(p::Prob, trait::BaseFlowBased, start::ProbTime)
    T = getnumperiods(gethorizon(getvar(trait)))

    # TODO
    current_state = 0
    state = 1

    if current_state == state
        nothing
    else
        #ptdfs = get_ptdfs(trait)
        setconcoeff_from_ptdf(p, T, trait.id, trait.ptdfs, trait.ptdfs_names)
        setrhs_from_ptdf(p, T, trait.id, trait.max_cap)
    end

end

function get_values_from_ptdf_df(ptdfs, ptdfs_names)
    ptdfs_names = ptdfs_names[3:end]
    max_cap = ptdfs[2]
    ptdfs = ptdfs[3:end]
    ptdfs = convert(Array{Float64}, ptdfs)
    return ptdfs, ptdfs_names, max_cap
end


function includeBaseFlowBased!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(toplevel, elkey)
    deps = Id[]
    
    varname = getdictvalue(value, FLOW_CONCEPT, String, elkey) 
    varkey = Id(FLOW_CONCEPT, varname)
    push!(deps, varkey)
    haskey(toplevel, varkey) || return (false, deps)

    ptdfs = getdictvalue(value, "ptdfs", Array, elkey)
    ptdfs_names = getdictvalue(value, "ptdfs_names", Array{String}, elkey)
    max_cap = getdictvalue(value, "max_cap", Int64, elkey)

    transfer_flow_ids = Vector{Id}([])
    for flow_name in ptdfs_names
        transfer_flow_id = Id(FLOW_CONCEPT, String(flow_name))
        push!(deps, transfer_flow_id)
        haskey(toplevel, transfer_flow_id) || return (false, deps)
        push!(transfer_flow_ids, transfer_flow_id)
    end

    objkey = getobjkey(elkey)
    toplevel[objkey] = BaseFlowBased(objkey, toplevel[varkey], max_cap, ptdfs, transfer_flow_ids) # can be lowlevel?
    
    return (true, deps)
end

FLOW_BASED_CONCEPT = "FlowBased" # TODO: move

INCLUDEELEMENT[TypeKey(FLOW_BASED_CONCEPT, "BaseFlowBased")] = includeBaseFlowBased!

