using DataFrames, Statistics, Dates, CSV
#using TuLiPa

# DataElements for a Thermal power plant
function addrhsthermal!(elements, name, balance; 
        cost::Union{Real, Nothing}=nothing, # €/GWh
        cap::Union{Real, Nothing}=nothing) # MW
    genname  = "Gen" * name
    costname = "MC"  * name
    capname  = "Cap" * name

    powerarrowname  = "PowerSupply" * name

    # Flows are variables that contribute into Balance equations
    push!(elements, getelement(FLOW_CONCEPT, "BaseFlow", genname))

    # Arrows connect Flows and Balances
    push!(elements, getelement(ARROW_CONCEPT, "BaseArrow", powerarrowname, 
            (BALANCE_CONCEPT, balance),
            (FLOW_CONCEPT, genname),
            (CONVERSION_CONCEPT, 1.0), # Factor to convert Flow into the same commodity as Balance (here Power to Power, so 1)
            (DIRECTIONKEY, DIRECTIONIN))) # Positive or negative contribution

    # Cost is the contribution of the variable into the objective function
    costdata = getelement(COST_CONCEPT, "CostTerm", costname, 
            (WHICHCONCEPT, FLOW_CONCEPT),
            (WHICHINSTANCE, genname),
            (DIRECTIONKEY, DIRECTIONIN)) # positive or negative contribution
    if cost === nothing # Point to a parameter DataElement with time-series data
        costdata.value[PARAM_CONCEPT] = costname   # assume param with same name
    else # If the cost is constant for all scenarios
        cost = float(cost)
        @assert cost >= 0
        costdata.value[PARAM_CONCEPT] = cost
    end
    push!(elements, costdata)

    # Non-negative capacity
    capdata = getelement(CAPACITY_CONCEPT, "PositiveCapacity", capname, 
            (WHICHCONCEPT, FLOW_CONCEPT),
            (WHICHINSTANCE, genname),
            (PARAM_CONCEPT, capname), # Point to a parameter DataElement with time-series data
            (BOUNDKEY, BOUNDUPPER)) # Upper or lower capacity
    push!(elements, capdata)
    if cap != nothing # If the capacity is constant for all scenarios
        cap = float(cap)
        @assert cap >= 0
        # Parameter that converts the capacity in MW to GWh based on the duration of the horizon periods
        push!(elements, getelement(PARAM_CONCEPT,"MWToGWhSeriesParam",capname,
            ("Level",cap),
            ("Profile",1.0)))
    end

    return
end

# DataElements for a simple reservoir hydropower plant
function addhydro!(elements, name, powerbalance; 
        eneq::Union{Real, Nothing}=nothing, # GWh/Mm3 (or kWh/m3)
        releasecap::Union{Real, Nothing}=nothing, # m3/s
        storagecap::Union{Real, Nothing}=nothing) # Mm3
    hydrobalance = name
    
    releasename  = "Release" * name
    spillname    = "Spill"   * name
    storagename  = "Storage" * name
    
    storagecapname = "Cap"     * storagename
    releasecapname = "Cap"     * releasename
    inflowname     = "Inflow"  * hydrobalance
    
    powerarrowname = "PowerSupply" * releasename
    hydroarrowname = "WaterDemand" * releasename
    spillarrowname = "Spill" * releasename
    
    # Water balance
    addbalance!(elements, hydrobalance, "Hydro")
    
    # Inflow is a contribution to the right-hand-side of the water balance
    addrhsterm!(elements, inflowname, hydrobalance, DIRECTIONIN)
    
    # Variables for release and spill
    push!(elements, getelement(FLOW_CONCEPT, "BaseFlow", releasename))
    push!(elements, getelement(FLOW_CONCEPT, "BaseFlow", spillname))
    
    # Release and spill take water out from the hydro balance.
    push!(elements, getelement(ARROW_CONCEPT, "BaseArrow", hydroarrowname, 
            (BALANCE_CONCEPT, hydrobalance),
            (FLOW_CONCEPT, releasename),
            (CONVERSION_CONCEPT, 1.0), 
            (DIRECTIONKEY, DIRECTIONOUT)))
    
    push!(elements, getelement(ARROW_CONCEPT, "BaseArrow", spillarrowname, 
            (BALANCE_CONCEPT, hydrobalance),
            (FLOW_CONCEPT, spillname),
            (CONVERSION_CONCEPT, 1.0), 
            (DIRECTIONKEY, DIRECTIONOUT)))
    
    # Release also contributes to the power market
    powerarrowdata = getelement(ARROW_CONCEPT, "BaseArrow", powerarrowname, 
            (BALANCE_CONCEPT, powerbalance),
            (FLOW_CONCEPT, releasename),
            (DIRECTIONKEY, DIRECTIONIN))
    if eneq === nothing
        powerarrowdata.value[CONVERSION_CONCEPT] = powerarrowname
    else
        eneq = float(eneq)
        @assert eneq >= 0
        powerarrowdata.value[CONVERSION_CONCEPT] = eneq
    end
    push!(elements, powerarrowdata)
    
    # Release capacity
    releasecapdata = getelement(CAPACITY_CONCEPT, "PositiveCapacity", releasecapname,
            (WHICHCONCEPT, FLOW_CONCEPT),
            (WHICHINSTANCE, releasename),
            (PARAM_CONCEPT, releasecapname), # Point to a parameter DataElement with time-series data
            (BOUNDKEY, BOUNDUPPER)) # Upper or lower capacity
    push!(elements, releasecapdata)
    if releasecap != nothing # If the capacity is constant for all scenarios
        releasecap = float(releasecap)
        @assert releasecap >= 0
        # Parameter that converts the capacity in m3/s to Mm3 based on the duration of the horizon periods
        push!(elements, getelement(PARAM_CONCEPT,"M3SToMM3SeriesParam",releasecapname,
              ("Level",releasecap),
              ("Profile",1.0)))
    end
    
    # Variable for storage
    push!(elements, getelement(STORAGE_CONCEPT, "BaseStorage", storagename,
            (BALANCE_CONCEPT, hydrobalance)))
    
    # Storage capacity
    storagecapdata = getelement(CAPACITY_CONCEPT, "PositiveCapacity", storagecapname,
            (WHICHCONCEPT, STORAGE_CONCEPT),
            (WHICHINSTANCE, storagename),
            (BOUNDKEY, BOUNDUPPER))
    if storagecap === nothing
        storagecapdata.value[PARAM_CONCEPT] = storagecapname
    else
        storagecap = float(storagecap)
        @assert storagecap >= 0
        storagecapdata.value[PARAM_CONCEPT] = storagecap
    end
    push!(elements, storagecapdata)
    
    return
end

# DataElements for transmission between areas
function addpowertrans!(elements, frombalance, tobalance; 
        cap::Union{Real, Nothing}=nothing, 
        eff::Union{Real, Nothing}=nothing)
    
    flowname = frombalance * "->" * tobalance
    capname = "Cap" * flowname
    fromarrowname = flowname * "From"
    toarrowname = flowname * "To"
    
    # Transmission variable
    push!(elements, getelement(FLOW_CONCEPT, "BaseFlow", flowname))
    
    # Variable out from one Balance
    fromarrowdata = getelement(ARROW_CONCEPT, "BaseArrow", fromarrowname, 
            (BALANCE_CONCEPT, frombalance),
            (FLOW_CONCEPT, flowname),
            (CONVERSION_CONCEPT, 1.0),
            (DIRECTIONKEY, DIRECTIONOUT))
    push!(elements, fromarrowdata)
    
    # Variable in to another Balance
    toarrowdata = getelement(ARROW_CONCEPT, "BaseArrow", toarrowname, 
            (BALANCE_CONCEPT, tobalance),
            (FLOW_CONCEPT, flowname),
            (DIRECTIONKEY, DIRECTIONIN))
    if eff === nothing
        toarrowdata.value[CONVERSION_CONCEPT] = powerarrowname
    else
        @assert 0 < eff <= 1
        eff = float(eff)
        toarrowdata.value[CONVERSION_CONCEPT] = eff # this could also be modelled as a Loss
    end
    push!(elements, toarrowdata)
    
    # Transmission capacity
    capdata = getelement(CAPACITY_CONCEPT, "PositiveCapacity", capname,
            (WHICHCONCEPT, FLOW_CONCEPT),
            (WHICHINSTANCE, flowname),
            (PARAM_CONCEPT, capname), # Point to a parameter DataElement with time-series data
            (BOUNDKEY, BOUNDUPPER)) # Upper or lower capacity
    push!(elements, capdata)
    if cap != nothing # If the capacity is constant for all scenarios
        cap = float(cap)
        @assert cap >= 0
        # Parameter that converts the capacity in MW to GWh based on the duration of the horizon periods
        push!(elements, getelement(PARAM_CONCEPT,"MWToGWhSeriesParam",capname,
              ("Level",cap),
              ("Profile",1.0)))
    end
end

# Combine the different parts of the dataset into one list of DataElements
function gettestdataset()
    elements = DataElement[]
    
    structure = getteststructure()
    elements = vcat(elements, structure)
    
    params = gettestparams()
    elements = vcat(elements, params)
    
    constants = gettestconstants()
    elements = vcat(elements, constants)
    
    levels = gettestlevels()
    elements = vcat(elements, levels)
    
    profiles = gettestprofiles()
    elements = vcat(elements, profiles)
    
    return elements
end

# The structure consist of the main model objects and how they are connected together
# We also add some of the parameters (like capacities, conversions and costs) if they are constant for all scenarios 
function getteststructure()
    structure = DataElement[]

    addbalance!(structure, "PowerBalance_NO2", "Power")
    addbalance!(structure, "PowerBalance_GER", "Power")

    addpowertrans!(structure, "PowerBalance_NO2", "PowerBalance_GER", cap=1400, eff=0.97)
    addpowertrans!(structure, "PowerBalance_GER", "PowerBalance_NO2", cap=1400, eff=0.97)

    addrhsterm!(structure, "WindNO2",   "PowerBalance_NO2", DIRECTIONIN)
    addrhsterm!(structure, "RoRNO2",    "PowerBalance_NO2", DIRECTIONIN)
    addrhsterm!(structure, "DemandNO2", "PowerBalance_NO2", DIRECTIONOUT)

    addrhsterm!(structure, "WindGER",   "PowerBalance_GER", DIRECTIONIN)
    addrhsterm!(structure, "SolarGER",  "PowerBalance_GER", DIRECTIONIN)
    addrhsterm!(structure, "DemandGER", "PowerBalance_GER", DIRECTIONOUT)

    addrhsthermal!(structure, "BioGER",  "PowerBalance_GER", cap=5000, cost=50000)
    addrhsthermal!(structure, "NucGER",  "PowerBalance_GER", cap=5000, cost=5000)
    addrhsthermal!(structure, "CoalGER", "PowerBalance_GER", cap=15000)
    addrhsthermal!(structure, "GasGER",  "PowerBalance_GER", cap=40000)

    addhydro!(structure, "ResNO2", "PowerBalance_NO2", eneq=1.3, storagecap=16000, releasecap=6000)

    return structure
end

# These parameters are built up with TimeVectors (constants or time-series data), which they point to
function gettestparams()
    params = DataElement[]

    # MWToGWhSeriesParam have a profile and a level stored in other DataElements
    # And convert the value from MW to GWh based on the duration of horizon periods
    for name in ["WindNO2", "DemandNO2", "WindGER", "SolarGER", "DemandGER"]
        push!(params, DataElement(PARAM_CONCEPT, "MWToGWhSeriesParam", name,
            Dict("Profile" => "Profile" * name, "Level" => "Level" * name)))
    end
    
    # M3SToMM3SeriesParam have a profile and a level stored in other DataElements
    # And convert the value from m3/s to Mm3 based on the duration of horizon periods
    for name in ["InflowResNO2", "RoRNO2"]
        push!(params, DataElement(PARAM_CONCEPT, "M3SToMM3SeriesParam", name,
            Dict("Profile" => "Profile" * name, "Level" => "Level" * name)))
    end
    
    # FossilMCParam is calculated from many inputs. Here, most of them are constant, except for the 
    # gas price level and profile that is dependant on chosen scenario
    for fuel in ["Coal", "Gas"]
        name = "MC" * fuel * "GER"
        push!(params, DataElement(PARAM_CONCEPT, "FossilMCParam", name,
            Dict("FuelProfile" => "Profile" * fuel, "FuelLevel" => "Level" * fuel,
                "CO2Factor" => "CO2Factor" * fuel, "CO2Profile" => "CO2Profile", "CO2Level" => "CO2Level",
                "Efficiency" => "Efficiency" * fuel, "VOC" => "VOC" * fuel)))
    end
    params
end

# We define the constant TimeVectors which make up FossilMCParam
function gettestconstants()
    constants = DataElement[]
    push!(constants, DataElement(TIMEVECTOR_CONCEPT, "ConstantTimeVector", "LevelCoal",      Dict("Value" => 30000.0))) # €/GWh
    push!(constants, DataElement(TIMEVECTOR_CONCEPT, "ConstantTimeVector", "ProfileCoal",    Dict("Value" => 1.0)))
    push!(constants, DataElement(TIMEVECTOR_CONCEPT, "ConstantTimeVector", "CO2FactorGas",   Dict("Value" => 0.18)))
    push!(constants, DataElement(TIMEVECTOR_CONCEPT, "ConstantTimeVector", "CO2FactorCoal",  Dict("Value" => 0.36)))
    push!(constants, DataElement(TIMEVECTOR_CONCEPT, "ConstantTimeVector", "VOCGas",         Dict("Value" => 2000.0))) # €/GWh
    push!(constants, DataElement(TIMEVECTOR_CONCEPT, "ConstantTimeVector", "VOCCoal",        Dict("Value" => 4000.0))) # €/GWh
    push!(constants, DataElement(TIMEVECTOR_CONCEPT, "ConstantTimeVector", "CO2Level",       Dict("Value" => 50000.0))) # €/GWh
    push!(constants, DataElement(TIMEVECTOR_CONCEPT, "ConstantTimeVector", "CO2Profile",     Dict("Value" => 1.0)))
    push!(constants, DataElement(TIMEVECTOR_CONCEPT, "ConstantTimeVector", "EfficiencyGas",  Dict("Value" => 0.5)))
    push!(constants, DataElement(TIMEVECTOR_CONCEPT, "ConstantTimeVector", "EfficiencyCoal", Dict("Value" => 0.4)))
    constants
end

# We define TimeVectors that represent the level of different parameters in 2021 and 2025.
function gettestlevels()
    levels = DataElement[]
    
    push!(levels, DataElement(TIMEINDEX_CONCEPT, "VectorTimeIndex", "DataLevelsTimeIndex",
        Dict("Vector" => [getisoyearstart(2021), getisoyearstart(2025)])))
    
    push!(levels, DataElement(TIMEVALUES_CONCEPT, "VectorTimeValues", "LevelWindNO2",
        Dict("Vector" => Float64[1500, 1500]))) # MW
    push!(levels, DataElement(TIMEVALUES_CONCEPT, "VectorTimeValues", "LevelRoRNO2",
        Dict("Vector" => Float64[500, 500]))) # MW
    push!(levels, DataElement(TIMEVALUES_CONCEPT, "VectorTimeValues", "LevelDemandNO2",
        Dict("Vector" => Float64[5000, 5500]))) # MW
    push!(levels, DataElement(TIMEVALUES_CONCEPT, "VectorTimeValues", "LevelDemandGER",
        Dict("Vector" => Float64[50000, 55000]))) # MW
    push!(levels, DataElement(TIMEVALUES_CONCEPT, "VectorTimeValues", "LevelWindGER",
        Dict("Vector" => Float64[30000, 40000]))) # MW
    push!(levels, DataElement(TIMEVALUES_CONCEPT, "VectorTimeValues", "LevelSolarGER",
        Dict("Vector" => Float64[60000, 80000]))) # MW
    push!(levels, DataElement(TIMEVALUES_CONCEPT, "VectorTimeValues", "LevelGas",
        Dict("Vector" => Float64[90000, 50000]))) # €/GWh
    push!(levels, DataElement(TIMEVALUES_CONCEPT, "VectorTimeValues", "LevelInflowResNO2",
        Dict("Vector" => Float64[950, 1000]))) # m3/s
    
    for name in ["LevelWindNO2", "LevelRoRNO2", "LevelDemandNO2", "LevelDemandGER", 
                "LevelWindGER", "LevelSolarGER", "LevelGas", "LevelInflowResNO2"]
        push!(levels, DataElement(TIMEVECTOR_CONCEPT, "InfiniteTimeVector", name,
            Dict(TIMEINDEX_CONCEPT => "DataLevelsTimeIndex", TIMEVALUES_CONCEPT => name)))
    end
    levels
end

# We define TimeVectors that represent the profile of different parameters
function gettestprofiles()
    # Profiles from https://www.nve.no/energi/analyser-og-statistikk/vaerdatasett-for-kraftsystemmodellene/
    path = joinpath(dirname(pathof(TuLiPa)), "..", "data/testprofiles_1981_2010.csv")
    dfmt = dateformat"yyyy-mm-dd HH:MM:SS"
    df = CSV.read(path, DataFrame)
    df.Timestamp = DateTime.(df.Timestamp, dfmt)
    @assert issorted(df.Timestamp)
    start = first(df.Timestamp)
    numperiods = length(df.Timestamp)
    colnames = [n for n in names(df) if n != "Timestamp"]
    matrix = Matrix{Float64}(df[:, colnames])
    elements = DataElement[]
    colnames = ["Profile" * name for name in colnames]
    
    # The time-series data is stored efficiently in two DataElements
    # - RangeTimeIndex is a time series index described by a StepRange
    # - BaseTable stores the data in a matrix, where each column is a different profile, 
    # and each row represent the value at a TimeIndex
    push!(elements, DataElement(TIMEINDEX_CONCEPT, "RangeTimeIndex", "ProfilesTimeIndex", 
            Dict("Start" => start, "Delta" => Hour(1), "Steps" => numperiods)))
    push!(elements, DataElement(TABLE_CONCEPT, "BaseTable", "ProfilesTable", 
            Dict("Matrix" => matrix, "Names" => colnames)))
    for name in colnames
        
        # ColumnTimeValues points to a row in BaseTable in another DataElement
        push!(elements, DataElement(TIMEVALUES_CONCEPT, "ColumnTimeValues", name, 
                Dict(TABLE_CONCEPT => "ProfilesTable", "Name" => name)))
        # RotatingTimeVector points to a index and values pair in other DataElements
        push!(elements, DataElement(TIMEVECTOR_CONCEPT, "RotatingTimeVector", name,
                Dict(TIMEVALUES_CONCEPT => name, TIMEINDEX_CONCEPT => "ProfilesTimeIndex")))
    end
    
    # We make a simple gas price profile for the variation throughout the year
    gasprice = Float64[1.079, 1.037, 0.970, 0.931, 0.915, 0.971, 1.028, 1.070]
    datetimes = DateTime[getisoyearstart(1981) + Hour((i-1) * 1113) for i in 1:8]
    gasprice = gasprice/mean(gasprice)
    push!(elements, DataElement(TIMEINDEX_CONCEPT, "VectorTimeIndex", "IndexProfileGas",
            Dict("Vector" => datetimes)))
    push!(elements, DataElement(TIMEVALUES_CONCEPT, "VectorTimeValues", "ValuesProfileGas",
            Dict("Vector" => gasprice)))
    push!(elements, DataElement(TIMEVECTOR_CONCEPT, "OneYearTimeVector", "ProfileGas",
            Dict(TIMEVALUES_CONCEPT => "ValuesProfileGas", TIMEINDEX_CONCEPT => "IndexProfileGas")))
    return elements
end;

# Insert horizons into commodities. E.g. all batteries will have the power horizon, since they interact with the power market
function set_horizon!(elements, commodity, horizon)
    # If element already exist, replace horizon with new
    for element in elements
        if element.typename == "BaseCommodity"
            if element.instancename == commodity
                element.value[HORIZON_CONCEPT] = horizon
                return
            end
        end
    end
    
    # Else, add commodity to element list
    push!(elements, getelement(COMMODITY_CONCEPT, "BaseCommodity", commodity, 
        (HORIZON_CONCEPT, horizon)))
end
