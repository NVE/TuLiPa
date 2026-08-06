"""
Collect results from a solved LP, and update results with several consequtive simulation runs.

First version very simple:
- Collect prices, supply, demand, hydro storages (Mm3) and battery storages.
- Assumes same time resolution for elements of same technology
- Does not support AdaptiveHorizon (see Demo 2)
- Support PQ-curves (SegmentedArrow) and aggregated plants (BaseAggSupplyCurve)

Two versions, one that preallocates memory and one that does not. The latter is slower.

TODO: 
- Add support for AdaptiveHorizon, customized time resolution per element and show hydro storages in TWh
- Bugfix isexogen/pq and state dependent conversion value
"""

### Common functions -------------------------------------------------

# Order result objects into lists
function order_result_objects(resultobjects, includeexogenprice=true)

    powerbalances = []
    rhsterms = []
    rhstermbalances = []
    plants = []
    plantbalances = []
    plantarrows = Dict()
    demands= []
    demandbalances = []
    demandarrows = Dict()
    hydrostorages = []
    batterystorages = []
    
    power_commodity_id = Id("Commodity", "Power")
    
    for obj in resultobjects
        
        # Powerbalances
        if obj isa Balance
            if getinstancename(getid(getcommodity(obj))) == "Power"
                if isexogen(obj)
                    if includeexogenprice
                        push!(powerbalances, obj)
                    end
                else
                    push!(powerbalances, obj)
                    for rhsterm in getrhsterms(obj)
                        push!(rhsterms,getid(rhsterm))
                        push!(rhstermbalances,getid(obj))
                    end
                end
            end
        end
        
        # Hydrostorages
        if obj isa BaseStorage
            if getinstancename(getid(getcommodity(getbalance(obj)))) == "Hydro"
                push!(hydrostorages,getid(obj))
            end
        end
        
        # Batterystorages
        if obj isa BaseStorage
            if getinstancename(getid(getcommodity(getbalance(obj)))) == "Battery"
                push!(batterystorages,getid(obj))
            end
        end
        
        # Supply and demands
        if obj isa BaseFlow
            # The type of supply or demand can be found based on the arrows
            arrows = getarrows(obj)
            
            # Simple supplies and demands
            powerarrowbool = [(getid(getcommodity(getbalance(arrow))) == power_commodity_id) & !(arrow isa SegmentedArrow) for arrow in arrows]
            powerarrows = arrows[powerarrowbool]
            if sum(powerarrowbool) == 1
                if isingoing(powerarrows[1])
                    push!(plants,getid(obj))
                    push!(plantbalances,getid(getbalance(powerarrows[1])))
                    if isexogen(getbalance(powerarrows[1]))
                        plantarrows[getid(obj)] = powerarrows[1]
                    end
                elseif !isingoing(powerarrows[1])
                    push!(demands,getid(obj))
                    push!(demandbalances,getid(getbalance(powerarrows[1])))
                    if isexogen(getbalance(powerarrows[1]))
                        demandarrows[getid(obj)] = powerarrows[1]
                    end
                end
            end
            
            # Transmissions
            if sum(powerarrowbool) == 2
                for arrow in arrows
                    balance = getbalance(arrow)
                    if getid(getcommodity(balance)) == power_commodity_id
                        if isingoing(arrow) && (balance in resultobjects)
                            push!(plants,getid(obj))
                            push!(plantbalances,getid(balance))
                            if isexogen(balance)
                                plantarrows[getid(obj)] = arrow
                            end
                        elseif !isingoing(arrow) && (balance in resultobjects)
                            push!(demands,getid(obj))
                            push!(demandbalances,getid(balance))
                            if isexogen(balance)
                                demandarrows[getid(obj)] = arrow
                            end
                        end
                    end
                end
            end
                   
            # Supplies with SegmentedArrows (hydropower with PQ-kurves)
            pqarrowbool = [arrow isa SegmentedArrow for arrow in arrows]
            pqarrows = arrows[pqarrowbool]
            if sum(pqarrowbool) == 1
                if isingoing(pqarrows[1])
                    push!(plants,getid(obj))
                    push!(plantbalances,getid(getbalance(pqarrows[1])))
                end
            end
        end
        
        # Aggregated supplies (thermal power plants aggregated into one or more equivalent supplies)
        # TODO: Result should be a sum of all clusters, not separated
        if obj isa BaseAggSupplyCurve
            instance = getinstancename(getid(obj))
            concept = getconceptname(getid(obj))
            balance = getbalance(obj)
            for c in 1:getnumclusters(obj)
                newname = string(instance,"_",c)
                push!(plants,Id(concept,newname))
                push!(plantbalances,getid(balance))
            end
        end
        if obj isa ElasticDemand
            instance = getinstancename(getid(obj))
            concept = getconceptname(getid(obj))
            balance = getbalance(obj)
            for c in 1:obj.N
                push!(demands, create_segment_id(obj, c))
                push!(demandbalances, getid(balance))
            end
        end
    end
    return powerbalances, rhsterms, rhstermbalances, plants, plantbalances, plantarrows, demands, demandbalances, demandarrows, hydrostorages, batterystorages
end

# Collect results for given modelobjects
function get_results!(problem, prices, rhstermvalues, production, consumption, hydrolevels, batterylevels, powerbalances, rhsterms, plants, plantbalances, plantarrows, demands, demandbalances, demandarrows, hydrostorages, batterystorages, modelobjects, powerrange, hydrorange, periodduration_power, t)
    
    # Precompute plant arrow classifications outside the time loop to avoid per-period allocations
    nplants = length(plants)
    # For each plant: :pq, :exogen, :normal, or :aggsupply
    plant_types = Vector{Symbol}(undef, nplants)
    # For PQ plants, store the SegmentedArrow; for exogen plants, store the arrow from plantarrows
    plant_pqarrow = Vector{Any}(undef, nplants)
    plant_is_exogen_balance = Vector{Bool}(undef, nplants)
    
    for i in 1:nplants
        concept = getconceptname(plants[i])
        if concept == AGGSUPPLYCURVE_CONCEPT
            plant_types[i] = :aggsupply
            plant_pqarrow[i] = nothing
            plant_is_exogen_balance[i] = false
        else
            arrows = getarrows(modelobjects[plants[i]])
            pqarrow = nothing
            for arrow in arrows
                if arrow isa SegmentedArrow
                    pqarrow = arrow
                    break
                end
            end
            if pqarrow !== nothing
                plant_types[i] = :pq
                plant_pqarrow[i] = pqarrow
                plant_is_exogen_balance[i] = isexogen(getbalance(pqarrow))
            else
                exogen = isexogen(modelobjects[plantbalances[i]])
                plant_types[i] = exogen ? :exogen : :normal
                plant_pqarrow[i] = nothing
                plant_is_exogen_balance[i] = exogen
            end
        end
    end
    
    # Precompute demand classifications
    ndemands = length(demands)
    demand_is_elastic = Vector{Bool}(undef, ndemands)
    demand_is_exogen_balance = Vector{Bool}(undef, ndemands)
    for i in 1:ndemands
        demand_is_elastic[i] = (getconceptname(demands[i]) == DEMAND_CONCEPT)
        demand_is_exogen_balance[i] = !demand_is_elastic[i] && isexogen(modelobjects[demandbalances[i]])
    end

    for (j,jj) in enumerate(powerrange)
        # For powerbalances collect prices and rhsterms (like inelastic demand, wind, solar and RoR)
        for i in 1:length(powerbalances)
            # if !isexogen(powerbalances[i])
            prices[jj, i] = -getcondual(problem, getid(powerbalances[i]), j)
            # if length(getrhsterms(powerbalances[i])) > 0
            #     for k in 1:length(rhsterms)
            #         if hasrhsterm(problem, getid(powerbalances[i]), rhsterms[k], j)
            #             rhstermvalues[jj, k] = getrhsterm(problem, getid(powerbalances[i]), rhsterms[k], j)
            #         end
            #     end
            # end
            # else
            #     exogenbalance = powerbalances[i]
            #     horizon = gethorizon(exogenbalance)
            #     price = getprice(exogenbalance)
            #     querytime = getstarttime(horizon, j, t)
            #     querydelta = gettimedelta(horizon, j)
            #     prices[jj, i] = getparamvalue(price, querytime, querydelta)
            # end
        end

        # Collect production of all plants
        for i in 1:nplants
            ptype = plant_types[i]
            if ptype == :pq
                arrow = plant_pqarrow[i]
                production[jj, i] = 0
                for (k, conversion) in enumerate(getconversions(arrow))
                    segmentid = getsegmentid(arrow, k)
                    if plant_is_exogen_balance[i]
                        # TODO: Balance and variable can have different horizons
                        horizon = gethorizon(arrow)
                        querystart = getstarttime(horizon, j, t)
                        querydelta = gettimedelta(horizon, j)
                        conversionvalue = getparamvalue(conversion, querystart, querydelta)
                        production[jj, i] += getvarvalue(problem, segmentid, j)*conversionvalue
                    else
                        production[jj, i] += getvarvalue(problem, segmentid, j)*abs(getconcoeff(problem, plantbalances[i], segmentid, j, j))
                    end
                end
            elseif ptype == :exogen
                # TODO: Balance and variable can have different horizons
                arrow = plantarrows[plants[i]]
                horizon = gethorizon(arrow)
                conversionparam = getcontributionparam(arrow)
                querytime = getstarttime(horizon, j, t)
                querydelta = gettimedelta(horizon, j)
                conversionvalue = getparamvalue(conversionparam, querytime, querydelta)
                production[jj, i] = getvarvalue(problem, plants[i], j)*conversionvalue
            else # :normal or :aggsupply
                production[jj, i] = getvarvalue(problem, plants[i], j)*abs(getconcoeff(problem, plantbalances[i], plants[i], j, j))
            end
        end

        # Collect demand of all demands
        for i in 1:ndemands
            if demand_is_elastic[i]
                consumption[jj, i] = getvarvalue(problem, demands[i], j)
            elseif demand_is_exogen_balance[i]
                arrow = demandarrows[demands[i]]
                horizon = gethorizon(arrow)
                conversionparam = getcontributionparam(arrow)
                querytime = getstarttime(horizon, j, t)
                querydelta = gettimedelta(horizon, j)
                conversionvalue = getparamvalue(conversionparam, querytime, querydelta)
                consumption[jj, i] = getvarvalue(problem, demands[i], j)*conversionvalue
            else
                consumption[jj, i] = getvarvalue(problem, demands[i], j)*abs(getconcoeff(problem, demandbalances[i], demands[i], j, j))
            end
        end
        
        # Collect battery storage levels
        for i in 1:length(batterystorages)
            batterylevels[jj, i] = getvarvalue(problem, batterystorages[i], j)
        end
    end
    
    # Collect hydro storage levels
    for (j,jj) in enumerate(hydrorange)
        for i in 1:length(hydrostorages)
            hydrolevels[jj, i] = getvarvalue(problem, hydrostorages[i], j)
        end
    end
end

### Preallocation version -----------------------------------------------------------

# Initialize results objects and collect results
function init_results(steps::Int, problem::Prob, modelobjects, resultobjects, numperiods_powerhorizon, numperiods_hydrohorizon, periodduration_power, t, includeexogenprice=true)
    
    powerbalances, rhsterms, rhstermbalances, plants, plantbalances, plantarrows, demands, demandbalances, demandarrows, hydrostorages, batterystorages = order_result_objects(resultobjects, includeexogenprice)
    
    # Matrices to store results per time period, scenario and object
    prices = zeros(Int(numperiods_powerhorizon*steps), length(powerbalances))
    rhstermvalues = zeros(Int(numperiods_powerhorizon*steps), length(rhsterms))
    production = zeros(Int(numperiods_powerhorizon*steps), length(plants))
    consumption = zeros(Int(numperiods_powerhorizon*steps), length(demands))
    hydrolevels = zeros(Int(numperiods_hydrohorizon*steps), length(hydrostorages))
    batterylevels = zeros(Int(numperiods_powerhorizon*steps), length(batterystorages))

    # Collect results
    get_results!(problem, prices, rhstermvalues, production, consumption, hydrolevels, batterylevels, powerbalances, rhsterms, plants, plantbalances, plantarrows, demands, demandbalances, demandarrows, hydrostorages, batterystorages, modelobjects, 1:numperiods_powerhorizon, 1:numperiods_hydrohorizon, periodduration_power, t)
    
    return prices, rhstermvalues, production, consumption, hydrolevels, batterylevels, powerbalances, rhsterms, rhstermbalances, plants, plantbalances, plantarrows, demands, demandbalances, demandarrows, hydrostorages, batterystorages
end

# Append results to existing results (e.g. next time step)
function update_results!(step, problem, prices, rhstermvalues, production, consumption, hydrolevels, batterylevels, powerbalances, rhsterms, plants, plantbalances, plantarrows, demands, demandbalances, demandarrows, hydrostorages, batterystorages, modelobjects, numperiods_powerhorizon, numperiods_hydrohorizon, periodduration_power, t)

    powerrange = Int(numperiods_powerhorizon*(step-1)+1):Int(numperiods_powerhorizon*(step))
    hydrorange = Int(numperiods_hydrohorizon*(step-1)+1):Int(numperiods_hydrohorizon*(step))
    get_results!(problem, prices, rhstermvalues, production, consumption, hydrolevels, batterylevels, powerbalances, rhsterms, plants, plantbalances, plantarrows, demands, demandbalances, demandarrows, hydrostorages, batterystorages, modelobjects, powerrange, hydrorange, periodduration_power, t)
end

### Append version (slow and lots of garbage collection) -----------------------------------------------------------
# TODO: Remove and from TuLiPa-demos

# Initialize results objects and collect results
function init_results(problem::Prob, modelobjects, resultobjects, numperiods_powerhorizon, numperiods_hydrohorizon, periodduration_power, t, includeexogenprice=true)
    
    powerbalances, rhsterms, rhstermbalances, plants, plantbalances, plantarrows, demands, demandbalances, demandarrows, hydrostorages, batterystorages = order_result_objects(resultobjects, includeexogenprice)
    
    # Matrices to store results per time period, scenario and object
    prices = zeros(numperiods_powerhorizon, length(powerbalances))
    rhstermvalues = zeros(numperiods_powerhorizon, length(rhsterms))
    production = zeros(numperiods_powerhorizon, length(plants))
    consumption = zeros(numperiods_powerhorizon, length(demands))
    hydrolevels = zeros(numperiods_hydrohorizon, length(hydrostorages))
    batterylevels = zeros(numperiods_powerhorizon, length(batterystorages))

    # Collect results
    get_results!(problem, prices, rhstermvalues, production, consumption, hydrolevels, batterylevels, powerbalances, rhsterms, plants, plantbalances, plantarrows, demands, demandbalances, demandarrows, hydrostorages, batterystorages, modelobjects, 1:numperiods_powerhorizon, 1:numperiods_hydrohorizon, periodduration_power, t)
    
    return prices, rhstermvalues, production, consumption, hydrolevels, batterylevels, powerbalances, rhsterms, rhstermbalances, plants, plantbalances, plantarrows, demands, demandbalances, demandarrows, hydrostorages, batterystorages
end

# Append results to existing results (e.g. next time step)
function update_results(problem, oldprices, oldrhstermvalues, oldproduction, oldconsumption, oldhydrolevels, oldbatterylevels, powerbalances, rhsterms, plants, plantbalances, plantarrows, demands, demandbalances, demandarrows, hydrostorages, batterystorages, modelobjects, numperiods_powerhorizon, numperiods_hydrohorizon, periodduration_power, t)

    # Matrices to store results per time period, scenario and object
    prices = zeros(numperiods_powerhorizon, length(powerbalances))
    rhstermvalues = zeros(numperiods_powerhorizon, length(rhsterms))
    production = zeros(numperiods_powerhorizon, length(plants))
    consumption = zeros(numperiods_powerhorizon, length(demands))
    hydrolevels = zeros(numperiods_hydrohorizon, length(hydrostorages))
    batterylevels = zeros(numperiods_powerhorizon, length(batterystorages))

    get_results!(problem, prices, rhstermvalues, production, consumption, hydrolevels, batterylevels, powerbalances, rhsterms, plants, plantbalances, plantarrows, demands, demandbalances, demandarrows, hydrostorages, batterystorages, modelobjects, 1:numperiods_powerhorizon, 1:numperiods_hydrohorizon, periodduration_power, t)

    prices = vcat(oldprices, prices)
    rhstermvalues = vcat(oldrhstermvalues, rhstermvalues)
    production = vcat(oldproduction, production)
    consumption = vcat(oldconsumption, consumption)
    hydrolevels = vcat(oldhydrolevels, hydrolevels)
    batterylevels = vcat(oldbatterylevels, batterylevels)
    
    return prices, rhstermvalues, production, consumption, hydrolevels, batterylevels
end

# Collect other results (variables and rhsterms given commodity and instancenames) ------------------------------------------------------------------
function order_result_objects_other(resultobjects, resultinfo::Dict)
    otherobjects = Dict()
    otherbalances = Dict()

    for key in keys(resultinfo)
        otherobjects[key] = Dict()
        otherbalances[key] = Dict()

        for commodity in keys(resultinfo[key])
            otherobjects[key][commodity] = []
            otherbalances[key][commodity] = []
        end

        if key == "RHSTerms"
            for obj in resultobjects
                if obj isa Balance
                    commodity = getinstancename(getid(getcommodity(obj)))
                    if haskey(resultinfo[key], commodity)
                        patterns = resultinfo[key][commodity]
                        for rhsterm in getrhsterms(obj)
                            rhsterminstancename = getinstancename(getid(rhsterm))
                            if any(pattern -> occursin(pattern, rhsterminstancename), patterns)
                                push!(otherobjects[key][commodity],getid(rhsterm))
                                push!(otherbalances[key][commodity],getid(obj))
                            end
                        end
                    end
                end
            end
        elseif key == "Vars"
            for obj in resultobjects
                if obj isa BaseFlow
                    for commodity in keys(resultinfo[key])
                        varinstancename = getinstancename(getid(obj))
                        patterns = resultinfo[key][commodity]
                        if any(pattern -> occursin(pattern, varinstancename), patterns)
                            push!(otherobjects[key][commodity],getid(obj))
                        end
                    end
                end
            end
        end
    end
    return otherobjects, otherbalances
end

function get_horizon_commodity(modelobjects::Dict, commodity)
    for (id, obj) in modelobjects
        if obj isa Balance
            if getinstancename(getid(getcommodity(obj))) == commodity
                return gethorizon(obj)
            end
        end
    end
end
function get_horizon_commodity(modelobjects::Vector, commodity)
    for obj in modelobjects
        if obj isa Balance
            if getinstancename(getid(getcommodity(obj))) == commodity
                return gethorizon(obj)
            end
        end
    end
end

function get_results!(stepnr, problem, otherobjects, otherbalances, othervalues, modelobjects, t)
    for key in keys(otherobjects)
        for commodity in keys(otherobjects[key])
            horizon = get_horizon_commodity(modelobjects, commodity)
            numperiods = getnumperiods(horizon)
            periodrange = Int(numperiods*(stepnr-1)+1):Int(numperiods*(stepnr))
            valuesmat = othervalues[key][commodity]

            if key == "RHSTerms"
                rhsterms = otherobjects[key][commodity]
                balances = otherbalances[key][commodity]
                for i in eachindex(rhsterms)
                    rhsterm_i = rhsterms[i]
                    balance_i = balances[i]
                    for (j,jj) in enumerate(periodrange)
                        valuesmat[jj, i] = getrhsterm(problem, balance_i, rhsterm_i, j)
                    end
                end
            elseif key == "Vars"
                vars = otherobjects[key][commodity]
                for i in eachindex(vars)
                    var_i = vars[i]
                    for (j,jj) in enumerate(periodrange)
                        valuesmat[jj, i] = getvarvalue(problem, var_i, j)
                    end
                end
            end
        end
    end
end