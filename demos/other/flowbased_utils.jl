fix_names = Dict([
    "SE1" => "SVER-SE1", 
    "SE2" => "SVER-SE2",
    "SE3" => "SVER-SE3",
    "SE4" => "SVER-SE4",
    "DK2" => "DANM-DK2",
    "FI" => "FINLAND",
]
)

is_transmission(e) = split(e.instancename, "_")[1] == "Transm"

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

#function reverse_transm_name(name)
#    name = replace(name, "Transm_" => "")
#    name = split(name, "->")
#    return "Transm_$(name[2])->$(name[1])"
#end

function copy_element(elem, new_name)
    @assert fieldnames(T) == (:conceptname, :typename, :instancename, :value)
    fields_values = [getfield(elem, field) for field in fieldnames(T)]
    value = copy(fields_values[4])
    return T(fields_values[1], fields_values[2], new_name, value)
end

function get_arrows(elements, transm)
    return [f for f in elements if f.conceptname == "Arrow" && f.value["Flow"] == transm]
end

function get_loss(elements, arrow)
    return [f for f in elements if f.conceptname == "Loss" && f.value["WhichInstance"] == arrow]
end

function get_capacity(elements, transm)
    return [f for f in elements if f.conceptname == "Capacity" && f.value["WhichInstance"] == transm]
end

function copy_capacity(cap_elem, name, flow_name)
    e = copy_element(cap_elem, name)
    e.value["WhichInstance"] = flow_name
    return e
end

function copy_loss(loss_elem, name, arrow_name)
    e = copy_element(loss_elem, name)
    e.value["WhichInstance"] = arrow_name
    return e
end

function copy_arrow(arrow_elem, name, flow_name)
    e = copy_element(arrow_elem, name)
    e.value["Flow"] = flow_name
    return e
end

function copy_flow(flow_elem, name)
    return copy_element(flow_elem, name)
end

function add_postfix(name, postfix)
    return "$(name)|$(postfix)" 
 end

function get_reverse_flow(elements, flow_name)
    flow_name = reverse_transm_name(flow_name)
    return [f for f in elements if f.instancename == flow_name]
end

function add_capacity_with_ram(df)
    function add_cap(flow_name, ram = 0.0)
        cap_name = "cap_" * flow_name
        param_cap_name = "param_cap_" * flow_name
        cap_elem = [
            T("Capacity", "PositiveCapacity", cap_name, Dict{Any, Any}("Param" => param_cap_name, "WhichInstance" => flow_name, "WhichConcept" => "Flow", "Bound" => "Upper")),
            T("Param", "MWToGWhSeriesParam", param_cap_name, Dict{Any, Any}("Level" => ram, "Profile" => 1.0))
        ]
        return cap_elem
    end
    cap_ram_elem = []
    for (ram, line) in zip(df.RAM, df.line)
        cap_ram_elem = vcat(cap_ram_elem, add_cap(line, ram))
        rev_name = reverse_transm_name.(line)
        cap_ram_elem = vcat(cap_ram_elem, add_cap(rev_name, ram))
    end
    return cap_ram_elem
end

function deep_copy_flow(elements, flow_elem, postfix)
    
    name = add_postfix(flow_elem.instancename, postfix)
    flow = copy_flow(flow_elem, name)

    arr_1, arr_2 = get_arrows(elements, flow_elem.instancename)
    loss = get_loss(elements, arr_1.instancename)[1]

    arr_name1 = add_postfix(arr_1.instancename, postfix)
    arr_name2 = add_postfix(arr_2.instancename, postfix)
    loss_name = add_postfix(loss.instancename, postfix)
        
    arr1_c = copy_arrow(arr_1, arr_name1, flow.instancename)
    arr2_c = copy_arrow(arr_2, arr_name2, flow.instancename)
    loss_c = copy_loss(loss, loss_name, arr1_c.instancename)
    
    return [flow, arr1_c, arr2_c, loss_c]
end

function add_duplicated_transm(net_elements, count_lookup)
    
    extra_net_elem = []
    
    for e in net_elements
        count = get(count_lookup, e.instancename, 1)
        count <= 1 && continue
        
        for i in range(2, count) # already have 1             
            extra_net_elem = vcat(extra_net_elem, deep_copy_flow(net_elements, e, i))
            rev_flow = get_reverse_flow(net_elements, e.instancename)[1]
            extra_net_elem = vcat(extra_net_elem, deep_copy_flow(net_elements, rev_flow, i))
        end 
    end

    extra_net_elem = Vector{T}(extra_net_elem)
    return extra_net_elem
end

function fix_name(a)
    a = strip(a)
    b = get(fix_names, a, a)
    return b
end

function format_name(a, b)
    return "Transm_$(a)->$(b)"
end

function add_count_col(df, col = "line")
    sort!(df, col)
    counter= []
    function count_occurance(n)
        push!(counter, n)
        len = length([f for f in counter if f == n])
        len <= 1 && return ""
        return add_postfix("", len)
    end    
    df[!, :line] = df[!, :line] .* count_occurance.(df[!, col])
end

function correct_line_direction(df)
    df[!, "fix_order"] = vcat.(df.emps_area0, df.emps_area1)
    negated_check(x) = sort(x) == x ? 1 : -1
    negated = negated_check.(df.fix_order)
    negated_values = df[!, Not(:RAM, :emps_area0, :emps_area1, :fix_order)] .* negated
    sort!.(df[!, "fix_order"])
    df[!, "emps_area0"] = get.(df[!, "fix_order"], 1, nothing)
    df[!, "emps_area1"] = get.(df[!, "fix_order"], 2, nothing)
    df = hcat(df[!, [:emps_area0, :emps_area1, :RAM]], negated_values) # flipped dir gets negated
    return df
end

function fix_col_names_and_add_postfix_to_duplicated(df)
    df[!, "line"] = format_name.(fix_name.(df[!, "emps_area0"]), fix_name.(df[!, "emps_area1"]))
    select!(df, Not([:emps_area0, :emps_area1]))
    rename!(df, fix_names)
    select!(df, :line, Not(:line))
    add_count_col(df)
    return df 
end

function round_ptdf_values(df)
    float_thres(f) = abs(f) < 0.01 ? 0 : f
    remove_one(f) = round(f) == -1.0 ? 0 : f
    for col in names(df)
        col in ["line", "RAM"] && continue
        df[!, col] = float_thres.(df[!, col])
    end
    return df
end

function proc_ptdf_csv(df)
    df = select(df, Not(:Column1, :area0, :area1))
    df = correct_line_direction(df)
    df = fix_col_names_and_add_postfix_to_duplicated(df)
    df = select(df, :line, :RAM, Not(:RAM, :line))
    df = round_ptdf_values(df)

    # removes missing instead
    is_in(x) = x in ["Transm_SVER-SE3->OSTLAND|2", "Transm_OSTLAND->SVER-SE3|2", "Transm_NORGEMIDT->OSTLAND", "Transm_MOERE->VESTMIDT", "Transm_OSTLAND->SVER-SE3", "Transm_HALLINGDAL->SORLAND"]
    df = df[is_in.(df.line) .== false, :]

    # remove dupl lines
    df = df[occursin.("|", df.line) .== false, : ]

    return df
end

function get_values_from_ptdf_df(ptdfs, ptdfs_names)
    ptdfs_names = ptdfs_names[3:end]
    max_cap = ptdfs[2]
    ptdfs = ptdfs[3:end]
    ptdfs = convert(Array{Float64}, ptdfs)
    return ptdfs, ptdfs_names, max_cap
end

function create_count_lookup(df)
    # assumes the df lines no are ascending 
    return Dict([length(f) > 1 ? (f[1], parse(Int, f[2]) ) : (f[1], 1) for f in split.(df.line, "|") ])
end

function create_new_transm_one_dir(name, balanceA_name, balanceB_name, level = 1900.0, loss = 0.001, util = 0.35) "Transm_A->B"
    
    # Note: loss and util are set to default values.
    # Does not add capacity, this is added later with RAM.

    @assert(occursin("Transm_",name) )
    
    base_name = split(name, "_")[2]
    cap_name = "Capcacity" * base_name
    cap_name_param =  "CapacityParam_" * base_name
    arrow_name_in = "InArrow_" * base_name
    arrow_name_out = "OutArrow_" * base_name
    loss_name = "Loss_" * base_name
    
    new_transm_elements = [
        T("Flow", "BaseFlow", name, Dict()),
        T("Arrow", "BaseArrow", arrow_name_in, Dict{Any, Any}("Balance" => balanceB_name, "Flow" => name, "Conversion" => 1.0, "Direction" => "In")),
        T("Arrow", "BaseArrow", arrow_name_out, Dict{Any, Any}("Balance" => balanceA_name, "Flow" => name, "Conversion" => 1.0, "Direction" => "Out")),
        T("Loss", "SimpleLoss", loss_name, Dict{Any, Any}("LossFactor" => loss, "Utilization" => util, "WhichInstance" => arrow_name_in, "WhichConcept" => "Arrow")),
    ]
    return new_transm_elements
end

function create_new_transm(name, balanceA_name, balanceB_name, level = 1900.0, loss = 0.001, util = 0.35)
    e1 = create_new_transm_one_dir(name, balanceA_name, balanceB_name, level)
    name = reverse_transm_name(name)
    e2 = create_new_transm_one_dir(name, balanceB_name ,balanceA_name, level)
    return vcat(e1,e2)
end

function get_balances_from_name(name)
    @assert(occursin("Transm_", name))
    name = split(name, "|")[1]
    name = replace(name, ("Transm_" => ""))
    A = "PowerBalance_"*split(name, "->")[1]
    B = "PowerBalance_"*split(name, "->")[2]
    return (A, B)
end

function add_missing_lines(transm, df)
    transm_names = Set([e.instancename for e in transm if is_transmission(e)])
    df_lines = Set(df.line)
    missing = setdiff(df_lines, transm_names)
    
    elems = []
    for name in missing
        balances = get_balances_from_name(name)
        occursin("|", name) && continue # duplicated lines is fixed later
        new_elems = create_new_transm(name, balances[1], balances[2], 1900.0,  0.001, 0.35)
        elems = vcat(elems, new_elems)
    end 
    return elems
end

function make_flowbased_with_duplicated_transm(df, transm)
    extra_transm = add_duplicated_transm(transm, create_count_lookup(df));
    transm = vcat(transm, extra_transm)
    balances = ["PowerBalance_"*n for n in names(df)[3:end]]
    np_lookup = get_np_lookup2(transm, balances)
    flow_based_elem = _make_flowbased(df, np_lookup)
    return transm, flow_based_elem
end

function make_flowbased_without_duplicated_transm(df, transm)
    #extra_transm = add_duplicated_transm(transm, create_count_lookup(df));
    #transm = vcat(transm, extra_transm)
    balances = ["PowerBalance_"*n for n in names(df)[3:end]]
    np_lookup = get_np_lookup2(transm, balances)
    flow_based_elem = _make_flowbased(df, np_lookup)
    return flow_based_elem
end

function _make_flowbased(ptdfs, np_lookup)
    elem = Array{T}([])
    for row in eachrow(ptdfs)
        line = row["line"] # Flow variable used for transfer, i.e AB        
        ptdfs_names = names(ptdfs)
        ptdfs_val = Array(row)
        ptdfs_val, ptdfs_names, max_cap = get_values_from_ptdf_df(ptdfs_val, ptdfs_names)        
        e = T("FlowBased", "BaseFlowBased", line, Dict(
                "Flow" => line,
                "ptdfs_names" => ptdfs_names,
                "ptdfs" => ptdfs_val,
                "max_cap" => max_cap, 
                "np_lookup" => np_lookup)
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

function get_np_lookup2(net_elements, areas::Vector{String})
    np_lookup = Dict()
    for area in areas      
        area_name = replace(area, ("PowerBalance_" => "") )
        np_lookup[area * "_in"] = get_transm_connected_to_balance(net_elements, area_name, "In")
        np_lookup[area * "_out"] = get_transm_connected_to_balance(net_elements, area_name, "Out")
    end
    return np_lookup
end

function make_flowbased(df, transm)
    balances = ["PowerBalance_"*n for n in names(df)[3:end]]
    np_lookup = get_np_lookup2(transm, balances)
    flow_based_elem = _make_flowbased(df, np_lookup)
    return flow_based_elem
end

# remove?
function remove_cap_for_flowbased_transm_no_duplicate(elements)
    function remove_capacity(elements, list_of_transm)
        remove = []
        for e in list_of_transm
            !(e in [e.instancename for e in elements if e.conceptname != "FlowBased"]) && continue
            push!(remove, get_capacity(elements, e)[1].instancename)
            push!(remove, get_capacity(elements, get_reverse_flow(elements, e)[1].instancename)[1].instancename)
        end
        return [e for e in final_elem if !(e.instancename in remove) || e.conceptname == "FlowBased"]   
    end
    flow_based_names = [e.instancename for e in elements if e.conceptname == "FlowBased"]
    filtered = remove_capacity(elements, flow_based_names)
    return filtered
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

