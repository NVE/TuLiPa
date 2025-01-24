"""
Stuff we use in connection with the input system, 
which are not essential parts of the input system.

In this file we define:
- Constants for parsing data elements
- Functions to parse input files containing data elements
- Utility functions for parsing and verification in INCLUDEELEMENT functions
- Functions to add elements programatically (we use these to define datasets in demos)

"""

# ---- Constants for parsing data elements ----

const CONCEPTNAME = "Concept"
const TYPENAME = "Type"
const INSTANCENAME = "Instance"
const WHICHCONCEPT = "WhichConcept"
const WHICHINSTANCE = "WhichInstance"
const DIRECTIONKEY = "Direction"
const DIRECTIONIN = "In"
const DIRECTIONOUT = "Out"
const BOUNDKEY = "Bound"
const BOUNDUPPER = "Upper"
const BOUNDLOWER = "Lower"
const LOSSFACTORKEY = "LossFactor"
const UTILIZATIONKEY = "Utilization"
const PENALTYKEY = "Penalty"
const SOFTCAPKEY = "SoftCap"
const STARTCOSTKEY = "StartCost"
const STORAGEHINTKEY = "Storagehint"
const RESIDUALHINTKEY = "Residualhint"
const RESERVOIRCURVEKEY = "ReservoirCurve"
const PRODUCTIONINFOKEY = "ProductionInfo"
const HYDRAULICHINTKEY = "HydraulicHint"
const GLOBALENEQKEY = "GlobalEneq"
const OUTLETLEVELKEY = "OutletLevel"
const NOMINALHEADKEY = "NominalHead"
const TABLE_CONCEPT = "Table"
const TIMEINDEX_CONCEPT = "TimeIndex"
const TIMEVALUES_CONCEPT = "TimeValues"
const TIMEVECTOR_CONCEPT = "TimeVector"
const TIMEDELTA_CONCEPT = "TimeDelta"
const TIMEPERIOD_CONCEPT = "TimePeriod"
const HORIZON_CONCEPT = "Horizon"
const BALANCE_CONCEPT = "Balance"
const FLOW_CONCEPT = "Flow"
const STORAGE_CONCEPT = "Storage"
const COMMODITY_CONCEPT = "Commodity"
const AGGSUPPLYCURVE_CONCEPT = "AggSupplyCurve"
const STARTUPCOST_CONCEPT = "StartUpCost"
const RAMPING_CONCEPT = "Ramping"
const ARROW_CONCEPT = "Arrow"
const PARAM_CONCEPT = "Param"
const SOFTBOUND_CONCEPT = "SoftBound"
const COST_CONCEPT = "Cost"
const RHSTERM_CONCEPT = "RHSTerm"
const METADATA_CONCEPT = "Metadata" 
const BOUNDARYCONDITION_CONCEPT = "BoundaryCondition"
const CAPACITY_CONCEPT = "Capacity"
const PRICE_CONCEPT = "Price"
const CONVERSION_CONCEPT = "Conversion"
const LOSS_CONCEPT = "Loss"
const DEMAND_CONCEPT = "Demand"
const FLOW_BASED_CONCEPT = "FlowBased"

# ---- Functions to parse input files containing data elements ----

function getelement(elements::Vector{DataElement},instancename::String)
    for element in elements
        element.instancename == instancename && return element
    end
    display(instancename)
    error("Element not in list")
end

function getelements(tupleelements::Vector{Any}, path="")
    elements = DataElement[]
    for element in tupleelements
        push!(elements, getelement(element...; path))
    end
    return elements
end

function getelement(concept, concrete, instance, pairs...; path="") 
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
    # added to support relative paths in dataset
    if concrete in ["TwoStateBucketIfm", "TwoStateNeuralODEIfm"] && d["ModelParams"] isa String
        d["ModelParams"] = joinpath(path, d["ModelParams"])
    end
    if concrete == "TwoStateNeuralODEIfm" && d["Moments"] isa String
        d["Moments"] = joinpath(path, d["Moments"])
    end
    return DataElement(concept, concrete, instance, d)
end

# ---- Utility functions for parsing and verification in INCLUDEELEMENT functions ----

_update_deps(deps::Vector{Id}, id::Nothing, ok::Bool) = @assert ok
_update_deps(deps::Vector{Id}, id::Id, ok::Bool) = push!(deps, id)
function _update_deps(deps::Vector{Id}, ids, ok::Bool)
    for i in ids
        _update_deps(deps, i, ok)
    end
end
_update_deps(deps::Tuple{Vector{String}, Vector{Id}}, id::Nothing, ok::Bool) = @assert ok
_update_deps(deps::Tuple{Vector{String}, Vector{Id}}, id::Id, ok::Bool) = push!(deps[2], id)
function _update_deps(deps::Tuple{Vector{String}, Vector{Id}}, ids, ok::Bool)
    for i in ids
        _update_deps(deps, i, ok)
    end
end

function getdictvalue(dict::Dict, dictkey::String, @nospecialize(TYPES), elkey::ElementKey)
    haskey(dict, dictkey) || error("Key $dictkey missing for $elkey")
    value = dict[dictkey]
    value isa TYPES || error("Value for key $dictkey is not $TYPES for $elkey")
    return value
end

function checkkey(leveldict::Dict, elkey::ElementKey)
    objkey = getobjkey(elkey)
    haskey(leveldict, objkey) && error("Object $objkey already added for $elkey")
    return
end

function getdictisingoing(value::Dict, elkey::ElementKey)
    direction = getdictvalue(value, DIRECTIONKEY, String, elkey)
    direction == DIRECTIONIN && return true
    direction == DIRECTIONOUT && return false
    error("$DIRECTIONKEY must be $DIRECTIONIN or $DIRECTIONOUT for $elkey")
end

function getdictisupper(value::Dict, elkey::ElementKey)
    bound = getdictvalue(value, BOUNDKEY, String, elkey)
    bound == BOUNDUPPER && return true
    bound == BOUNDLOWER && return false
    error("$BOUNDKEY must be $BOUNDUPPER or $BOUNDLOWER for $elkey")
end

function getdictisresidual(value::Dict, elkey::ElementKey)
    residual = getdictvalue(value, RESIDUALHINTKEY, String, elkey)
    residual == "True" && return true
    residual == "False" && return false
    error("$RESIDUALHINTKEY must be True or False for $elkey")
end

const TIMEVECTORPARSETYPES = Union{AbstractFloat, String, TimeVector}
function getdicttimevectorvalue(lowlevel::Dict, value::String)
    objkey = Id(TIMEVECTOR_CONCEPT, value)
    haskey(lowlevel, objkey) && return (objkey, lowlevel[objkey], true)
    return (objkey, value, false)
end
getdicttimevectorvalue(::Dict, value::AbstractFloat) = (nothing, ConstantTimeVector(value), true)
getdicttimevectorvalue(::Dict, value::TimeVector) = (nothing, value, true)

const PARAMPARSETYPES = Union{AbstractFloat, String, Param}
function getdictparamvalue(lowlevel::Dict, elkey::ElementKey, value::Dict, paramname=PARAM_CONCEPT)
    haskey(value, paramname) || error("Missing $paramname for $elkey")
    return getdictparamvalue(lowlevel, elkey, value[paramname])
end
function getdictparamvalue(lowlevel::Dict, ::ElementKey, value::String, paramname=PARAM_CONCEPT)
    objkey = Id(paramname, value)
    haskey(lowlevel, objkey) && return (objkey, lowlevel[objkey], true)
    return (objkey, value, false)
end
getdictparamvalue(::Dict, ::ElementKey, value::AbstractFloat, paramname=PARAM_CONCEPT) = (nothing, ConstantParam(value), true)
getdictparamvalue(::Dict, ::ElementKey, value::Param, paramname=PARAM_CONCEPT) = (nothing, value, true)

function getdictparamlist(lowlevel::Dict, elkey::ElementKey, value::Dict, paramname=PARAM_CONCEPT)
    haskey(value, paramname) || error("Missing $paramname for $elkey")
    paramlist = [getdictparamvalue(lowlevel, elkey, listvalue) for listvalue in value[paramname]]
    paramvaluelist = [p for (id, p, ok) in paramlist]
    parambools = [ok for (id, p, ok) in paramlist]
    ids = [id for (id, p, ok) in paramlist]
    return (ids, paramvaluelist, all(y->y==true, parambools))
end

function getdictconversionvalue(lowlevel::Dict, elkey::ElementKey, value::Dict)
    haskey(value, CONVERSION_CONCEPT) || error("Missing $CONVERSION_CONCEPT for $elkey")
    return getdictconversionvalue(lowlevel, elkey, value[CONVERSION_CONCEPT])
end
function getdictconversionvalue(lowlevel::Dict, elkey::ElementKey, value::String)
    objkey_c = Id(CONVERSION_CONCEPT, value)
    objkey_p = Id(PARAM_CONCEPT, value)
    if haskey(lowlevel, objkey_c)
        return (objkey_c, lowlevel[objkey_c], true)
    end
    if haskey(lowlevel, objkey_p)
        (__, obj, __) = getdictconversionvalue(lowlevel, elkey, lowlevel[objkey_p])
        return (objkey_p, obj, true)
    end
    return ([objkey_c, objkey_p], value, false)
end
getdictconversionvalue(::Dict, ::ElementKey, value::AbstractFloat) = (nothing, BaseConversion(ConstantParam(value)), true)
getdictconversionvalue(::Dict, ::ElementKey, value::Param) = (nothing, BaseConversion(value), true)
getdictconversionvalue(::Dict, ::ElementKey, value::Conversion) = (nothing, value, true)

function getdictpricevalue(lowlevel::Dict, elkey::ElementKey, value::Dict)
    haskey(value, PRICE_CONCEPT) || error("Missing $PRICE_CONCEPT for $elkey")
    return getdictpricevalue(lowlevel, elkey, value[PRICE_CONCEPT])
end
function getdictpricevalue(lowlevel::Dict, elkey::ElementKey, value::String)
    objkey_price = Id(PRICE_CONCEPT, value)
    objkey_param = Id(PARAM_CONCEPT, value)
    if haskey(lowlevel, objkey_price)
        return (objkey_price, lowlevel[objkey_price], true)
    elseif haskey(lowlevel, objkey_param)
        (__, obj, __) = getdictpricevalue(lowlevel, elkey, lowlevel[objkey_param])
        return (objkey_param, obj, true)
    end
    return ([objkey_price, objkey_param], value, false)
end
getdictpricevalue(::Dict, ::ElementKey, value::AbstractFloat) = (nothing, BasePrice(ConstantParam(value)), true)
getdictpricevalue(::Dict, ::ElementKey, value::Param) = (nothing, BasePrice(value), true)
getdictpricevalue(::Dict, ::ElementKey, value::Price) = (nothing, value, true)

# ---- Functions to add elements programatically (we use these to define datasets in demos) ----

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
    push!(elements, getelement(BALANCE_CONCEPT, "BaseBalance", name, 
            (COMMODITY_CONCEPT, commodity)))
    if commodity == "Power"
        slackname = "SlackVar" * name
        addflow!(elements, slackname)
        slackarrowname = "SlackArrow" * name
        addarrow!(elements, slackarrowname, 1.0, slackname, name, DIRECTIONOUT)
    end
end

function addexogenbalance!(elements, name, commodity, price)
    push!(elements, getelement(BALANCE_CONCEPT, "ExogenBalance", name, 
            (COMMODITY_CONCEPT, commodity),
            (PRICE_CONCEPT, price)))
end

function addrhsterm!(elements, name, balance, direction)
    push!(elements, getelement(RHSTERM_CONCEPT, "BaseRHSTerm", name, 
        (BALANCE_CONCEPT, balance), 
        (PARAM_CONCEPT, name),
        (DIRECTIONKEY, direction))) 
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

function addpowertrans!(elements, frombalance, tobalance, cap, eff)
    flowname = frombalance * "->" * tobalance
    addflow!(elements, flowname)
    fromarrowname = flowname * "From"
    addarrow!(elements, fromarrowname, 1.0, flowname, frombalance, DIRECTIONOUT)
    toarrowname = flowname * "To"
    addarrow!(elements, toarrowname, eff, flowname, tobalance, DIRECTIONIN)
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