fix_names = Dict([
    "SE1" => "SVER-SE1", 
    "SE2" => "SVER-SE2",
    "SE3" => "SVER-SE3",
    "SE4" => "SVER-SE4",
    "DK2" => "DANM-DK2",
    "FI" => "FINLAND",
]
)

non_value_cols = ["line", "RAM", "border"]

is_transmission(e) = split(e.instancename, "_")[1] == "Transm"
#istransmissionvariable(x)

function add_powerbalance_postfix(df)
    return rename(df, 
                Dict(
                    zip(
                        names(select(df, Not(non_value_cols))), 
                        "PowerBalance_" .* names(select(df, Not(non_value_cols)))
                    )
                )
            )
end

function reverse_transm_name(name) # also in flowbased

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

function add_postfix(name, postfix)
    return "$(name)|$(postfix)" 
 end

function get_reverse_flow(elements, flow_name)
    flow_name = reverse_transm_name(flow_name)
    return [f for f in elements if f.instancename == flow_name]
end

function fix_name(a)
    a = strip(a)
    b = get(fix_names, a, a)
    return b
end

function format_name(a, b)
    return "Transm_$(a)->$(b)" # Needs the same name as the flow name in JulES
end

function correct_line_direction(df)
    
    col_correct_line = [:Column1, :emps_area0, :emps_area1, :RAM]

    
    df[!, "fix_order"] = vcat.(df.emps_area0, df.emps_area1)
    negated_check(x) = sort(x) == x ? 1 : -1
    negated = negated_check.(df.fix_order)
    negated_values = df[!, Not(col_correct_line..., :fix_order)] .* negated

    sort!.(df[!, "fix_order"])
    df[!, "emps_area0"] = get.(df[!, "fix_order"], 1, nothing)
    df[!, "emps_area1"] = get.(df[!, "fix_order"], 2, nothing)
    df = hcat(df[!, col_correct_line], negated_values) # flipped dir gets negated
    return df
end

function fix_col_names(df)
    df[!, "border"] = occursin.("BORDER", df.Column1);
    df[df.border, "Column1"] .= ""
    df[!, "line"] = df[!, "Column1"] .* format_name.(fix_name.(df[!, "emps_area0"]), fix_name.(df[!, "emps_area1"])) 
    df = select(df, Not([:emps_area0, :emps_area1, :Column1]))
    df = select(df, :line, Not(:line))
    df = rename(df, fix_names)
    df = add_powerbalance_postfix(df)
    return df
end

function round_ptdf_values(df)
    float_thres(f) = abs(f) < 0.01 ? 0 : f # NOTE: removes less than 0.01 values
    #remove_one(f) = round(f) == -1.0 ? 0 : f
    for col in names(df)
        col in non_value_cols && continue
        df[!, col] = float_thres.(df[!, col])
    end
    return df
end

function proc_ptdf_csv(df)
    df = correct_line_direction(df)
    df = fix_col_names(df)
    
    df = select(df, non_value_cols, Not(non_value_cols))
    
    df = round_ptdf_values(df)

    #df.RAM = df.RAM * 100000 # for testing

    # removes missing instead
    is_in(x) = x in ["Transm_NORGEMIDT->OSTLAND", "Transm_MOERE->VESTMIDT", "Transm_OSTLAND->SVER-SE3", "Transm_HALLINGDAL->SORLAND"]
    df = df[is_in.(df.line) .== false, :]

    return df
end

function get_values_from_ptdf_df(ptdfs, ptdfs_names)
    ptdfs_names = ptdfs_names[3:end]
    max_cap = ptdfs[2]
    ptdfs = ptdfs[3:end]
    ptdfs = convert(Array{Float64}, ptdfs)
    return ptdfs, ptdfs_names, max_cap
end

function _make_flowbased(ptdfs, np_lookup)
    elem = Array{T}([])
    
    for row in eachrow(ptdfs)
        line = row["line"] # Flow variable used for transfer, i.e AB
        border = row["border"]
                
        areas = row[Not(["line", "border", "RAM"])]
        max_cap = row["RAM"]
        ptdfs_names = names(areas)

        ptdfs_val = Array(areas)

   
        e = T("FlowBased", "BaseFlowBased", line, Dict(
                "Flow" => line,
                "ptdfs_names" => ptdfs_names,
                "ptdfs" => ptdfs_val,
                "max_cap" => max_cap, 
                "np_lookup" => np_lookup,
                "border" => border)
            )
        push!(elem, e)

    end
    return elem
end

function get_transm_connected_to_balance(net_elements, price_area, direction)
    transm_flows = []
    for e in [e for e in net_elements if e.conceptname == "Flow" && is_transmission(e)]
        f = split(e.instancename, "|")[1]
        f = split(replace(f, ("Transm_" => "") ), "->")
        @assert(direction == "Out" || direction == "In")
        idx = direction == "Out" ? 1 : 2
        if f[idx] == price_area
            push!(transm_flows, Id(e.conceptname, e.instancename))
        end
    end
    return transm_flows
end

function get_np_lookup(net_elements, areas::Vector{String})
    np_lookup = Dict()
    for area in areas
        area_name = replace(area, ("PowerBalance_" => "") )
        np_lookup[area * "_in"] = get_transm_connected_to_balance(net_elements, area_name, "In")
        np_lookup[area * "_out"] = get_transm_connected_to_balance(net_elements, area_name, "Out")
    end
    return np_lookup
end

function make_flowbased(df, transm)
    balances = names(df[!, Not(non_value_cols)])
    np_lookup = get_np_lookup(transm, balances)
    flow_based_elem = _make_flowbased(df, np_lookup)
    return flow_based_elem
end

function get_capacity(elements, transm)
    return [f for f in elements if f.conceptname == "Capacity" && f.value["WhichInstance"] == transm]
end

function remove_cap_for_flowbased_transm(elements, df)
    function remove_capacity(elements, list_of_transm)
        remove = []
        for e in list_of_transm
            push!(remove, get_capacity(elements, e)[1].instancename)
            push!(remove, get_capacity(elements, get_reverse_flow(elements, e)[1].instancename)[1].instancename)
        end
        return [e for e in elements if !(e.instancename in remove)]   
    end

    transm_names = Set([e.instancename for e in elements if is_transmission(e)])
    df_lines = Set(df.line)
    in_df = intersect(df_lines, transm_names)

    filtered = remove_capacity(elements, in_df)
    return filtered
end

