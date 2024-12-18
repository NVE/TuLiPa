function create_elements(network_info, df_flowbased_grid)
    df_flowbased_grid[!, "border"] = occursin.("BORDER", df_flowbased_grid.CnecName)
    print(network_info)
    elements = DataElement[]

    for area in keys(network_info)
        elements = vcat(elements, create_price_area(area, network_info))   
    end
    
    # Create flow-parameters for the rows where border == true, in both direction
    flow_parameters_1 = [make_connection(df_flowbased_grid.emps_area0[i], df_flowbased_grid.emps_area1[i]) for i in 1:nrow(df_flowbased_grid) if df_flowbased_grid.border[i]]
    flow_parameters_2 = [make_connection(df_flowbased_grid.emps_area1[i], df_flowbased_grid.emps_area0[i]) for i in 1:nrow(df_flowbased_grid) if df_flowbased_grid.border[i]]

    flow_parameters = vcat(flow_parameters_1..., flow_parameters_2...)  # Merge and flatten
    
    elements = vcat(elements, flow_parameters)

    power_horizon = SequentialHorizon(1, Day(1))
    push!(elements, getelement(COMMODITY_CONCEPT, "BaseCommodity", "Power", (HORIZON_CONCEPT, power_horizon)))
    addscenariotimeperiod!(elements, "ScenarioTimePeriod", getisoyearstart(1981), getisoyearstart(1983));
    
    return elements
end

function create_price_area(area, network_info) 
    elem = [
                    DataElement("Balance", "BaseBalance", "$area", Dict{Any, Any}("Commodity" => "Power")),    
                    DataElement("Flow", "BaseFlow", "Power$(area)", Dict{Any, Any}()),
                    DataElement("Arrow", "BaseArrow", "Arrow$area", Dict{Any, Any}("Balance" => area, "Flow" => "Power$(area)", "Conversion" => 1.0, "Direction" => "In")),
                    DataElement("Cost", "CostTerm", "Power$(area)", Dict{Any, Any}("Param" => network_info[area]["Power"], "WhichInstance" => "Power$(area)", "WhichConcept" => "Flow", "Direction" => "In")),
                    DataElement("Capacity", "PositiveCapacity", "Power$(area)_cap", Dict{Any, Any}("Param" => "Power$(area)_cap", "WhichInstance" => "Power$(area)", "WhichConcept" => "Flow", "Bound" => "Upper")),
                    DataElement("Param", "MWToGWhSeriesParam", "Power$(area)_cap", Dict{Any, Any}("Level" => network_info[area]["Power_cap"], "Profile" => 1.0)),
                    DataElement("Param", "MWToGWhSeriesParam", "Demand$(area)", Dict("Level" => network_info[area]["Demand"] , "Profile" => 1.0)),
                    DataElement("RHSTerm", "BaseRHSTerm", "Demand$(area)", Dict{Any, Any}("Balance" => area, "Param" => "Demand$(area)", "Direction" => "Out")),
            ]
    return elem
end

function process_ptdf_matrix(df, remove_nonexisting_emps)
    function _fix_col_names(df)
        df[!, "border"] = occursin.("BORDER", df.CnecName);

        df[!, "CnecName"] .= ifelse.(df.border,"Transm_" .* df[!, :emps_area0] .* "->" .* df[!, :emps_area1],
        df[!, :CnecName])

        df = select(df, Not([:emps_area0, :emps_area1]))
        return df
    end

    df_new = copy(df)
    df_new= _fix_col_names(df_new)

    if remove_nonexisting_emps
        # removes the lines that are connected in N490-model, but not connected in EMPS.
        is_in(x) = x in ["Transm_NORGEMIDT->OSTLAND", "Transm_MOERE->VESTMIDT", "Transm_OSTLAND->SVER-SE3", "Transm_HALLINGDAL->SORLAND"]
        df_new = df_new[is_in.(df_new.CnecName) .== false, :]
    end

    return df_new
end

function make_connection(from, to, prefix = "")  
    transm_from = replace(from, ("PowerBalance_" => ""))
    transm_to = replace(to, ("PowerBalance_" => ""))
    
    flow_name = "Transm_$(transm_from)->$(transm_to)" * prefix
    arrow_name_from = "arrow_from$(from)$(to)" * prefix
    arrow_name_to = "arrow_to$(from)$(to)" * prefix
    balance_from = "$(from)"
    balance_to = "$(to)"
    #cap_name = "$(flow_name)_cap"
    elem = [
        DataElement("Flow", "BaseFlow", flow_name, Dict()),    
        DataElement("Arrow", "BaseArrow", arrow_name_from, Dict("Balance" => String(balance_from), "Flow" => flow_name, "Conversion" => 1.0, "Direction" => "Out")),
        DataElement("Arrow", "BaseArrow", arrow_name_to, Dict("Balance" => String(balance_to), "Flow" => flow_name, "Conversion" => 1.0, "Direction" => "In")),
    ]    
    return elem
end

