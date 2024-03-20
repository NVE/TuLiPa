"""
The DataElement type we use has:
- Conceptname which is the abstract type of the element
- Typename which is the concrete type of the element
- Instancename which is the unique name of the element
- Value which is the information the element holds. A dictionary in our datasets

The data elements are stored in a flat structure where each data element
holds its information and possibly references to other dataelements 
they are linked to (for example can an upper capacity hold references 
to its parameter (stored in another data element), and references to 
the variable this upper capacity should apply to 
(see data_elements_to_objects.jl)).
"""

struct DataElement
    conceptname::String
    typename::String
    instancename::String
    value::Any
end

# Different keys
struct ElementKey
    conceptname::String
    typename::String
    instancename::String
end

struct TypeKey
    conceptname::String
    typename::String
end

struct Id
    conceptname::String
    instancename::String
end

getinstancename(x::Id) = x.instancename
getconceptname(x::Id) = x.conceptname
getname(x::Id) = "$(x.conceptname)$(x.instancename)"

getobjkey(x::ElementKey) = Id(x.conceptname, x.instancename)
gettypekey(x::ElementKey) = TypeKey(x.conceptname, x.typename)

getelkey(x::DataElement) = ElementKey(x.conceptname, x.typename, x.instancename)
getelvalue(x::DataElement) = x.value
getobjkey(x::DataElement) = Id(x.conceptname, x.instancename)
gettypekey(x::DataElement) = TypeKey(x.conceptname, x.typename)

function getelement(elements::Vector{DataElement},instancename::String)
    for element in elements
        element.instancename == instancename && return element
    end
    display(instancename)
    error("Element not in list")
end

# Functions to read dataset stored in JSON as a list of tuples (after JSON.parsefile())
# TODO: Each user should have their own version of this based on their data
# TODO: Assumes datetime format...
function getelements(tupleelements::Vector{Any}, path="")
    elements = DataElement[]
    for element in tupleelements
        push!(elements, getelement(element...; path))
    end
    return elements
end

function getelement(concept, concrete, instance, pairs...; path="") # should be adapted to dataset
    d = Dict()
    for (k, v) in pairs
        if concrete == "VectorTimeIndex"
            v = [DateTime(i,dateformat"yyyy-mm-dd HH:MM:SS") for i in v]
        elseif (concrete == "RangeTimeIndex") & (k == "Start")
            v = DateTime(v,dateformat"yyyy-mm-dd HH:MM:SS")
        elseif concrete == "VectorTimeValues"
            v = v |> Vector{Float64}
            ~all(isfinite, v) && error("Nonfinite values in type $concrete with name $instance") # move these checks to includeelement?
        elseif (concrete == "BaseTable") & (k == "Matrix")
            v = CSV.read(joinpath(path, v), header=0, DataFrame) |> Matrix{Float64} # read csv
            ~all(isfinite, v) && error("Nonfinite values in type $concrete with name $instance")
        elseif (concrete == "BaseTable") & (k == "Names")
            v = v |> Vector{String}
        elseif (k == "Period") | (k == "NumPeriods") | (k == "Steps") # BaseHorizon and MsTimeDelta and RangeTimeIndex and storagehint and PrognosisMeanSeries
            v = v |> Int64    
        elseif v isa Int
            v = v |> Float64
            ~isfinite(v) && error("Nonfinite values in type $concrete with name $instance")
        elseif concrete == "ReservoirCurve" && ((k == "Res") || (k == "Head"))
            v = v |> Vector{Float64}
            ~all(isfinite, v) && error("Nonfinite values in type $concrete with name $instance")
        end
        d[k] = v
    end
    return DataElement(concept, concrete, instance, d)
end

# -------------- Add primitive dataelements ---------------
function addflow!(elements, instance)
    push!(elements, getelement(FLOW_CONCEPT,"BaseFlow",instance))
end
        
function addstorage!(elements, instance, balance)
    push!(elements, getelement(STORAGE_CONCEPT,"BaseStorage",instance,
          (BALANCE_CONCEPT,balance)))
end

function addarrow!(elements, instance, conversion, flow, balance, direction)
    push!(elements, getelement(ARROW_CONCEPT,"BaseArrow",instance,
          (CONVERSION_CONCEPT,conversion),
          (FLOW_CONCEPT,flow),
          (BALANCE_CONCEPT,balance),
          (DIRECTIONKEY,direction)))
end
        
function addcapacity!(elements, instance, uplow, param, whichinstance, whichconcept)
    push!(elements, getelement(CAPACITY_CONCEPT, "PositiveCapacity", instance,
            (WHICHCONCEPT, whichconcept),
            (WHICHINSTANCE, whichinstance),
            (PARAM_CONCEPT, param),
            (BOUNDKEY, uplow)))
end

function addbalance!(elements, name, commodity)
    # Power markets or water balances are represented with a Balance equation
    # - They have a commodity which will decide the horizon (time-resolution) of the Balance
    push!(elements, getelement(BALANCE_CONCEPT, "BaseBalance", name, 
            (COMMODITY_CONCEPT, commodity)))
    # Power Balances needs a slack variable if inelastic wind, solar, or run-of-river is higher than the inelastic demand
    if commodity == "Power"
        slackname = "SlackVar" * name
        addflow!(elements, slackname)
        
        slackarrowname = "SlackArrow" * name
        addarrow!(elements, slackarrowname, 1.0, slackname, name, DIRECTIONOUT)
    end
end

function addexogenbalance!(elements, name, commodity, price)
    # Add an exogenous price area that the plants and pumps can interact with. All units are in NO5.
    push!(elements, getelement(BALANCE_CONCEPT, "ExogenBalance", name, 
            (COMMODITY_CONCEPT, commodity),
            (PRICE_CONCEPT, price)))
end

# Rhsterms contribute to the right hand side of a Balance equation
function addrhsterm!(elements, name, balance, direction)
    push!(elements, getelement(RHSTERM_CONCEPT, "BaseRHSTerm", name, 
        (BALANCE_CONCEPT, balance), 
        (PARAM_CONCEPT, name), # constant or time-series data
        (DIRECTIONKEY, direction))) # positive or negative contriution to the balance
end

function addparam!(elements, concrete, instance, level, profile)
    push!(elements, getelement(PARAM_CONCEPT,concrete,instance,
          ("Level", level),
          ("Profile", profile)))
end

function addscenariotimeperiod!(elements, instance, start, stop)
    push!(elements, getelement(TIMEPERIOD_CONCEPT, "ScenarioTimePeriod", instance, 
    ("Start", start), ("Stop", stop)))
end

# -------------- Add composed dataelements ---------------
# DataElements for transmission between areas
function addpowertrans!(elements, frombalance, tobalance, cap, eff)
    
    # Transmission variable
    flowname = frombalance * "->" * tobalance
    addflow!(elements, flowname)
    
    # Variable out from one Balance
    fromarrowname = flowname * "From"
    addarrow!(elements, fromarrowname, 1.0, flowname, frombalance, DIRECTIONOUT)
    
    toarrowname = flowname * "To"
    addarrow!(elements, toarrowname, eff, flowname, tobalance, DIRECTIONIN)
    
    # Transmission capacity
    capname = flowname * "Cap"
    addparam!(elements, "MWToGWhSeriesParam", capname * "Param", cap, 1.0)
    addcapacity!(elements, capname, BOUNDUPPER, capname * "Param", flowname, FLOW_CONCEPT)
end

function addbattery!(elements, name, powerbalance, storagecap, lossbattery, chargecap)
    balancename = "BatteryBalance_" * name
    addbalance!(elements, balancename, "Battery")
    
    storagename = "BatteryStorage_" * name
    addstorage!(elements, storagename, balancename)
    addcapacity!(elements, "BatteryStorageCap_" * name, BOUNDUPPER, storagecap, storagename, STORAGE_CONCEPT)
    
    chargename = "PlantCharge_" * name
    addflow!(elements, chargename)
    addarrow!(elements, "ChargePowerArrow_" * name, 1, chargename, powerbalance, "Out")
    addarrow!(elements,"ChargeBatteryArrow_" * name, 1-lossbattery, chargename, balancename, "In")
    addcapacity!(elements, "ChargeCapacity_" * name, "Upper", chargecap, chargename, FLOW_CONCEPT)
    
    dischargename = "PlantDischarge_" * name
    addflow!(elements,dischargename)
    addarrow!(elements, "DischargePowerArrow_" * name, 1, dischargename, powerbalance, "In")
    addarrow!(elements,"DischargeBatteryArrow_" * name, 1, dischargename, balancename, "Out")
    addcapacity!(elements, "DischargeCapacity_" * name, "Upper", chargecap, dischargename, FLOW_CONCEPT)
end

