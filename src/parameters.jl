"""
We implement several concrete parameter types (see abstracttypes.jl)
"""

using Interpolations

# ---- Generic fallbacks -----
function isconstant(param::Param)
    for field in fieldnames(typeof(param))
        isconstant(getfield(param, field)) || return false
    end
    return true
end

# ---- Concrete types ----

# Some simple concrete types
struct ZeroParam     <: Param end
struct PlusOneParam  <: Param end
struct MinusOneParam <: Param end
struct ConstantParam{T <: AbstractFloat} <: Param 
    value::T
end
struct TwoProductParam{P1 <: Any, P2 <: Any} <: Param
    param1::P1
    param2::P2
end

# Sometimes we want the contribution of the parameter to be negative
struct FlipSignParam{param <: Param} <: Param
    param::param

    function FlipSignParam(param::Param)
        if param isa FlipSignParam
            return param.param
        else
            new{typeof(param)}(param)
        end
    end
end

# This parameter stores everything needed to calculate the marginal cost of a thermal plant
struct FossilMCParam{FL <: TimeVector, FP <: TimeVector, CF <: TimeVector, 
    CL <: TimeVector, CP <: TimeVector, E <: TimeVector, V <: TimeVector} <: Param
    fuellevel::FL
    fuelprofile::FP
    co2factor::CF
    co2level::CL
    co2profile::CP
    efficiency::E
    voc::V
end

# These parameters are a combination of a level and profile TimeVectors
# The level is often an InfiniteTimeVector (e.g. installed wind power in 2021, 2025, 2030)
# The profile is often a RotatingTimeVector (e.g. a wind profile ranging from 0-1)
# MeanSeriesParam multiplies the two values together, while the
# others also take into account the temporal aspect (e.g. MW to GWh or m3/s to Mm3)
struct MeanSeriesParam{L <: TimeVector, P <: TimeVector} <: Param
    level::L
    profile::P
end

struct M3SToMM3SeriesParam{L <: TimeVector, P <: TimeVector} <: Param
    level::L
    profile::P
end

struct MWToGWhSeriesParam{L <: TimeVector, P <: TimeVector} <: Param
    level::L
    profile::P
end

struct CostPerMWToGWhParam{P <: Param} <: Param
    param::P
end

struct MeanSeriesIgnorePhaseinParam{L <: TimeVector, P <: TimeVector} <: Param # Special case that ignores phasein of scenarios.
    level::L
    profile::P
end

# These concrete types uses Price, Conversion, Loss and Capacity types
struct ExogenCostParam{P <: Price, C <: Conversion, L <: Loss} <: Param
    price::P
    conversion::C
    loss::L
end

struct ExogenIncomeParam{P <: Price, C <: Conversion, L <: Loss} <: Param
    price::P
    conversion::C
    loss::L
end

struct InConversionLossParam{C <: Conversion, L <: Loss} <: Param
    conversion::C
    loss::L
end

struct OutConversionLossParam{C <: Conversion, L <: Loss} <: Param
    conversion::C
    loss::L
end

struct TransmissionLossRHSParam{C <: Capacity} <: Param
    capacity::C
    loss::Float64
    utilisation::Float64
end

function TransmissionLossRHSParam(capacity::Capacity, L::SimpleLoss)
    return TransmissionLossRHSParam(capacity, L.value, L.utilisation)
end

# Other concrete types
struct XYCurve <: Param
    interpolator

    function XYCurve(x::T, y::T) where {T <: AbstractVector{Float64}}
        @assert length(x) == length(y)
        @assert length(y) > 1
        @assert issorted(x)
        @assert issorted(y) || issorted(y, rev=true)
        new(LinearInterpolation(x, y; extrapolation_bc=Flat()))
    end
end

yvalue(xycurve::XYCurve, x::Float64) = xycurve.interpolator(x)

# ------ Interface functions ---------
iszero(param::FlipSignParam) = iszero(param.param)
iszero(param::ZeroParam) = true
iszero(param::PlusOneParam) = false
iszero(param::MinusOneParam) = false
iszero(param::ConstantParam) = param.value == 0
iszero(param::TwoProductParam) = iszero(param.param1) && iszero(param.param2)
iszero(param::FossilMCParam) = false
iszero(param::M3SToMM3SeriesParam) = false
iszero(param::MWToGWhSeriesParam) = false
iszero(param::CostPerMWToGWhParam) = false
iszero(param::MeanSeriesParam) = false
iszero(param::MeanSeriesIgnorePhaseinParam) = false
iszero(param::ExogenCostParam) = iszero(param.price) && iszero(param.conversion)
iszero(param::ExogenIncomeParam) = iszero(param.price) && iszero(param.conversion)
iszero(param::InConversionLossParam) = iszero(param.conversion)
iszero(param::OutConversionLossParam) = iszero(param.conversion)
iszero(param::TransmissionLossRHSParam) = iszero(param.capacity)

isone(param::FlipSignParam) = false
isone(param::ZeroParam) = false
isone(param::PlusOneParam) = true
isone(param::MinusOneParam) = false
isone(param::ConstantParam) = param.value == 1
isone(param::TwoProductParam) = iszero(param.param1) && iszero(param.param2)
isone(param::FossilMCParam) = false
isone(param::M3SToMM3SeriesParam) = false
isone(param::MWToGWhSeriesParam) = false
isone(param::CostPerMWToGWhParam) = false
isone(param::MeanSeriesParam) = false
isone(param::MeanSeriesIgnorePhaseinParam) = false
isone(param::ExogenCostParam) = false
isone(param::ExogenIncomeParam) = false
isone(param::InConversionLossParam) = false
isone(param::OutConversionLossParam) = false
isone(param::TransmissionLossRHSParam) = false

isconstant(::ConstantParam) = true
isconstant(::ZeroParam) = true
isconstant(::PlusOneParam) = true
isconstant(::MinusOneParam) = true
isconstant(param::TransmissionLossRHSParam) = isconstant(param.capacity)

# Is the parameter value dependant on the temporal aspect?
# Example: MWToGWhSeriesParam is durational since the power produced (GWh),
# will depend on how long you produce for
isdurational(param::FlipSignParam) = isdurational(param.param)
isdurational(param::ZeroParam) = false
isdurational(param::PlusOneParam) = false
isdurational(param::MinusOneParam) = false
isdurational(param::ConstantParam) = false
isdurational(param::TwoProductParam) = isdurational(param.param1) && isdurational(param.param2)
isdurational(param::FossilMCParam) = false
isdurational(param::M3SToMM3SeriesParam) = true
isdurational(param::MWToGWhSeriesParam) = true
isdurational(param::CostPerMWToGWhParam) = isdurational(param.param)
isdurational(param::MeanSeriesParam) = false
isdurational(param::MeanSeriesIgnorePhaseinParam) = false
isdurational(param::ExogenCostParam) = isdurational(param.price) && isdurational(param.conversion) && isdurational(param.loss)
isdurational(param::ExogenIncomeParam) = isdurational(param.price) && isdurational(param.conversion) && isdurational(param.loss)
isdurational(param::InConversionLossParam) = isdurational(param.conversion) && isdurational(param.loss)
isdurational(param::OutConversionLossParam) = isdurational(param.conversion) && isdurational(param.loss)
isdurational(param::TransmissionLossRHSParam) = isdurational(param.capacity)

# Calculate the parameter value for a given parameter, problem time and timedelta duration
getparamvalue(::ZeroParam,     ::ProbTime, ::TimeDelta) =  0.0
getparamvalue(::PlusOneParam,  ::ProbTime, ::TimeDelta) =  1.0
getparamvalue(::MinusOneParam, ::ProbTime, ::TimeDelta) = -1.0
getparamvalue(param::ConstantParam, ::ProbTime, ::TimeDelta) = param.value
getparamvalue(param::TwoProductParam, start::ProbTime, d::TimeDelta) = getparamvalue(param.param1, start, d)*getparamvalue(param.param2, start, d)
getparamvalue(param::FlipSignParam, start::ProbTime, d::TimeDelta) = -getparamvalue(param.param, start, d)
getparamvalue(param::ExogenIncomeParam, start::ProbTime, d::TimeDelta) = getparamvalue(param.price, start, d)*getparamvalue(param.conversion, start, d)*(1-getparamvalue(param.loss, start, d))
getparamvalue(param::ExogenCostParam, start::ProbTime, d::TimeDelta) = getparamvalue(param.price, start, d)*getparamvalue(param.conversion, start, d)/(1-getparamvalue(param.loss, start, d))
getparamvalue(param::InConversionLossParam, start::ProbTime, d::TimeDelta) = getparamvalue(param.conversion, start, d)*(1-getparamvalue(param.loss, start, d))
getparamvalue(param::OutConversionLossParam, start::ProbTime, d::TimeDelta) = getparamvalue(param.conversion, start, d)/(1-getparamvalue(param.loss, start, d))
getparamvalue(param::TransmissionLossRHSParam, t::ProbTime, d::TimeDelta) = getparamvalue(param.capacity, t, d)*param.loss*param.utilisation

function getparamvalue(param::FossilMCParam, start::ProbTime, d::TimeDelta)
    datatime = getdatatime(start)
    scenariotime = getscenariotime(start)

    fl = getweightedaverage(param.fuellevel,   datatime, d)
    cf = getweightedaverage(param.co2factor,   datatime, d)
    cl = getweightedaverage(param.co2level,    datatime, d)
    ef = getweightedaverage(param.efficiency,  datatime, d)
    vo = getweightedaverage(param.voc,         datatime, d)

    cp = getweightedaverage(param.co2profile,  scenariotime, d)
    fp = getweightedaverage(param.fuelprofile, scenariotime, d)
    
    return (fl * fp + cf * cl * cp) / ef + vo
end

function getparamvalue(param::MeanSeriesParam, start::ProbTime, d::TimeDelta)
    datatime = getdatatime(start)
    scenariotime = getscenariotime(start)
    level = getweightedaverage(param.level, datatime, d)
    profile = getweightedaverage(param.profile, scenariotime, d)
    value = level * profile
    return value
end

function getparamvalue(param::MeanSeriesIgnorePhaseinParam, start::ProbTime, d::TimeDelta)
    datatime = getdatatime(start)
    scenariotime = getscenariotime(start)
    level = getweightedaverage(param.level, datatime, d)
    profile = getweightedaverage(param.profile, scenariotime, d)
    value = level * profile
    return value
end

function getparamvalue(param::M3SToMM3SeriesParam, start::ProbTime, d::TimeDelta)
    datatime = getdatatime(start)
    scenariotime = getscenariotime(start)
    level_m3s = getweightedaverage(param.level,   datatime, d)
    profile   = getweightedaverage(param.profile, scenariotime, d)
    m3s = level_m3s * profile
    seconds = float(getduration(d).value / 1000)
    return m3s * seconds / 1e6
end

function getparamvalue(param::MWToGWhSeriesParam, start::ProbTime, d::TimeDelta)
    datatime = getdatatime(start)
    scenariotime = getscenariotime(start)
    level_mw = getweightedaverage(param.level,   datatime, d)
    profile  = getweightedaverage(param.profile, scenariotime, d)
    mw = level_mw * profile
    hours = float(getduration(d).value / 3600000)
    return mw * hours / 1e3
end

function getparamvalue(param::CostPerMWToGWhParam, start::ProbTime, d::TimeDelta)
    cost = getparamvalue(param.param, start, d)
    hours = float(getduration(d).value / 3600000)
    return cost / hours * 1e3
end

# Calculate the parameter value if the start value is a PhaseinTwoTime
function getparamvalue(param::FossilMCParam, start::Union{PhaseinTwoTime,PhaseinFixedDataTwoTime}, d::TimeDelta)
    fl = getweightedaverage(param.fuellevel,   start.datatime, d)
    cf = getweightedaverage(param.co2factor,   start.datatime, d)
    cl = getweightedaverage(param.co2level,    start.datatime, d)
    ef = getweightedaverage(param.efficiency,  start.datatime, d)
    vo = getweightedaverage(param.voc,         start.datatime, d)

    phasein = getweightedaverage(start.phaseinvector, start.scenariotime1, d)

    local cp::Float64
    local fp::Float64

    if phasein == 0.0
        cp = getweightedaverage(param.co2profile,  start.scenariotime1, d)
        fp = getweightedaverage(param.fuelprofile, start.scenariotime1, d)
    elseif phasein == 1.0
        cp = getweightedaverage(param.co2profile,  start.scenariotime2, d)
        fp = getweightedaverage(param.fuelprofile, start.scenariotime2, d)
    else
        cp1 = getweightedaverage(param.co2profile,  start.scenariotime1, d)
        fp1 = getweightedaverage(param.fuelprofile, start.scenariotime1, d)
        cp2 = getweightedaverage(param.co2profile,  start.scenariotime2, d)
        fp2 = getweightedaverage(param.fuelprofile, start.scenariotime2, d)
        cp = cp1*(1-phasein) + cp2*phasein
        fp = fp1*(1-phasein) + fp2*phasein
    end
    
    return (fl * fp + cf * cl * cp) / ef + vo
end

function getparamvalue(param::MeanSeriesParam, start::Union{PhaseinTwoTime,PhaseinFixedDataTwoTime}, d::TimeDelta)
    phasein = getweightedaverage(start.phaseinvector, start.scenariotime1, d)

    local profile::Float64

    if phasein == 0.0
        profile = getweightedaverage(param.profile, start.scenariotime1, d)
    elseif phasein == 1.0
        profile = getweightedaverage(param.profile, start.scenariotime2, d)
    else
        profile1 = getweightedaverage(param.profile, start.scenariotime1, d)
        profile2 = getweightedaverage(param.profile, start.scenariotime2, d)
        profile = profile1*(1-phasein) + profile2*phasein
    end

    level = getweightedaverage(param.level, start.datatime, d)
    value = level * profile
    return value
end

function getparamvalue(param::M3SToMM3SeriesParam, start::Union{PhaseinTwoTime,PhaseinFixedDataTwoTime}, d::TimeDelta)
    phasein = getweightedaverage(start.phaseinvector, start.scenariotime1, d)

    local profile::Float64

    if phasein == 0.0
        profile = getweightedaverage(param.profile, start.scenariotime1, d)
    elseif phasein == 1.0
        profile = getweightedaverage(param.profile, start.scenariotime2, d)
    else
        profile1 = getweightedaverage(param.profile, start.scenariotime1, d)
        profile2 = getweightedaverage(param.profile, start.scenariotime2, d)
        profile = profile1*(1-phasein) + profile2*phasein
    end

    level_m3s = getweightedaverage(param.level,   start.datatime, d)
    m3s = level_m3s * profile
    seconds = float(getduration(d).value / 1000)
    return m3s * seconds / 1e6
end

function getparamvalue(param::MWToGWhSeriesParam, start::Union{PhaseinTwoTime,PhaseinFixedDataTwoTime}, d::TimeDelta)
    phasein = getweightedaverage(start.phaseinvector, start.scenariotime1, d)

    local profile::Float64

    if phasein == 0.0
        profile = getweightedaverage(param.profile, start.scenariotime1, d)
    elseif phasein == 1.0
        profile = getweightedaverage(param.profile, start.scenariotime2, d)
    else
        profile1 = getweightedaverage(param.profile, start.scenariotime1, d)
        profile2 = getweightedaverage(param.profile, start.scenariotime2, d)
        profile = profile1*(1-phasein) + profile2*phasein
    end

    level_mw = getweightedaverage(param.level,   start.datatime, d)
    mw = level_mw * profile
    hours = float(getduration(d).value / 3600000)
    return mw * hours / 1e3
end

# ------ Include dataelements -------
function includeFossilMCParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)

    fuellevel   = getdictvalue(value, "FuelLevel",   TIMEVECTORPARSETYPES, elkey)
    fuelprofile = getdictvalue(value, "FuelProfile", TIMEVECTORPARSETYPES, elkey)
    co2factor   = getdictvalue(value, "CO2Factor",   TIMEVECTORPARSETYPES, elkey)
    co2level    = getdictvalue(value, "CO2Level",    TIMEVECTORPARSETYPES, elkey)
    co2profile  = getdictvalue(value, "CO2Profile",  TIMEVECTORPARSETYPES, elkey)
    efficiency  = getdictvalue(value, "Efficiency",  TIMEVECTORPARSETYPES, elkey)
    voc         = getdictvalue(value, "VOC",         TIMEVECTORPARSETYPES, elkey)
    
    (fuellevel,   ok) = getdicttimevectorvalue(lowlevel, fuellevel)   ;  ok || return false
    (fuelprofile, ok) = getdicttimevectorvalue(lowlevel, fuelprofile) ;  ok || return false
    (co2factor,   ok) = getdicttimevectorvalue(lowlevel, co2factor)   ;  ok || return false
    (co2level,    ok) = getdicttimevectorvalue(lowlevel, co2level)    ;  ok || return false
    (co2profile,  ok) = getdicttimevectorvalue(lowlevel, co2profile)  ;  ok || return false
    (efficiency,  ok) = getdicttimevectorvalue(lowlevel, efficiency)  ;  ok || return false
    (voc,         ok) = getdicttimevectorvalue(lowlevel, voc)         ;  ok || return false
    
    obj = FossilMCParam(fuellevel, fuelprofile, co2factor, co2level, co2profile, efficiency, voc)
    
    lowlevel[getobjkey(elkey)] = obj
    return true
end

function includeM3SToMM3SeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    level   = getdictvalue(value, "Level",   TIMEVECTORPARSETYPES, elkey)
    profile = getdictvalue(value, "Profile", TIMEVECTORPARSETYPES, elkey)
    
    (level,   ok) = getdicttimevectorvalue(lowlevel, level)   ;  ok || return false
    (profile, ok) = getdicttimevectorvalue(lowlevel, profile) ;  ok || return false
    
    lowlevel[getobjkey(elkey)] = M3SToMM3SeriesParam(level, profile)
    return true
end

function includeM3SToMM3SeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::M3SToMM3SeriesParam)::Bool
    lowlevel[getobjkey(elkey)] = value
    return true
end

function includeM3SToMM3SeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::AbstractFloat)::Bool
    level = ConstantTimeVector(value)
    profile = ConstantTimeVector(one(typeof(value)))
    lowlevel[getobjkey(elkey)] = M3SToMM3SeriesParam(level, profile)
    return true
end

function includeMWToGWhSeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    level   = getdictvalue(value, "Level",   TIMEVECTORPARSETYPES, elkey)
    profile = getdictvalue(value, "Profile", TIMEVECTORPARSETYPES, elkey)
    
    (level,   ok) = getdicttimevectorvalue(lowlevel, level)    ;  ok || return false
    (profile, ok) = getdicttimevectorvalue(lowlevel, profile)  ;  ok || return false
    
    lowlevel[getobjkey(elkey)] = MWToGWhSeriesParam(level, profile)
    return true
end

function includeMWToGWhSeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::MWToGWhSeriesParam)::Bool
    lowlevel[getobjkey(elkey)] = value
    return true
end

function includeMWToGWhSeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::AbstractFloat)::Bool
    level = ConstantTimeVector(value)
    profile = ConstantTimeVector(one(typeof(value)))
    lowlevel[getobjkey(elkey)] = MWToGWhSeriesParam(level, profile)
    return true
end

function includeCostPerMWToGWhParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)

    if haskey(value, STARTCOSTKEY)
        (startcost, ok) = getdictparamvalue(lowlevel, elkey, value, STARTCOSTKEY)   ;  ok || return false
        lowlevel[getobjkey(elkey)] = CostPerMWToGWhParam(startcost)
    elseif haskey(value, "Level") && haskey(value, "Profile")
        level   = getdictvalue(value, "Level",   TIMEVECTORPARSETYPES, elkey)
        profile = getdictvalue(value, "Profile", TIMEVECTORPARSETYPES, elkey)
        
        (level,   ok) = getdicttimevectorvalue(lowlevel, level)    ;  ok || return false
        (profile, ok) = getdicttimevectorvalue(lowlevel, profile)  ;  ok || return false
        
        lowlevel[getobjkey(elkey)] = CostPerMWToGWhParam(MeanSeriesParam(level, profile))
    else
        return false
    end

    return true
end

function includeCostPerMWToGWhParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::CostPerMWToGWhParam)::Bool
    lowlevel[getobjkey(elkey)] = value
    return true
end

function includeCostPerMWToGWhParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::AbstractFloat)::Bool
    lowlevel[getobjkey(elkey)] = CostPerMWToGWhParam(ConstantParam(value))
    return true
end

function includeMeanSeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    level   = getdictvalue(value, "Level",   TIMEVECTORPARSETYPES, elkey)
    profile = getdictvalue(value, "Profile", TIMEVECTORPARSETYPES, elkey)
    
    (level,   ok) = getdicttimevectorvalue(lowlevel, level)   ;  ok || return false
    (profile, ok) = getdicttimevectorvalue(lowlevel, profile) ;  ok || return false
    
    lowlevel[getobjkey(elkey)] = MeanSeriesParam(level, profile)
    return true
end

function includeMeanSeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::MeanSeriesParam)::Bool
    lowlevel[getobjkey(elkey)] = value
    return true
end

function includeMeanSeriesIgnorePhaseinParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    level   = getdictvalue(value, "Level",   TIMEVECTORPARSETYPES, elkey)
    profile = getdictvalue(value, "Profile", TIMEVECTORPARSETYPES, elkey)
    
    (level,   ok) = getdicttimevectorvalue(lowlevel, level)   ;  ok || return false
    (profile, ok) = getdicttimevectorvalue(lowlevel, profile) ;  ok || return false
    
    lowlevel[getobjkey(elkey)] = MeanSeriesIgnorePhaseinParam(level, profile)
    return true
end

function includeMeanSeriesIgnorePhaseinParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::MeanSeriesIgnorePhaseinParam)::Bool
    lowlevel[getobjkey(elkey)] = value
    return true
end

INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "FossilMCParam")] = includeFossilMCParam!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "M3SToMM3SeriesParam")] = includeM3SToMM3SeriesParam!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "MWToGWhSeriesParam")] = includeMWToGWhSeriesParam!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "CostPerMWToGWhParam")] = includeCostPerMWToGWhParam!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "MeanSeriesParam")] = includeMeanSeriesParam!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "MeanSeriesIgnorePhaseinParam")] = includeMeanSeriesIgnorePhaseinParam!
