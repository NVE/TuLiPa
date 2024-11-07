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
isstateful(param::Param) = false

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
struct HourProductParam{P <: Param} <: Param
    param::P
end
struct StatefulParam{P <: Param} <: Param
    param::P
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

struct M3SToMM3Param{P <: Param} <: Param
    param::P
end

struct M3SToMM3SeriesParam{L <: TimeVector, P <: TimeVector} <: Param
    level::L
    profile::P
end

struct MWToGWhSeriesParam{L <: TimeVector, P <: TimeVector} <: Param
    level::L
    profile::P
end

struct MWToGWhParam{P<:Param} <: Param
    param::P
end

struct CostPerMWToGWhParam{P <: Param} <: Param
    param::P
end

struct MeanSeriesIgnorePhaseinParam{L <: TimeVector, P <: TimeVector} <: Param # Special case that ignores phasein of scenarios.
    level::L
    profile::P
end

struct PrognosisSeriesParam{L <: TimeVector, P <: TimeVector, Prog <: TimeVector, C <: TimeVector} <: Param
    level::L
    profile::P
    prognosis::Prog
    confidence::C

    function PrognosisSeriesParam(level, profile, prognosis, confidencesteps::Int) # TODO: Add interface for confidencevector
        index = Vector{DateTime}(undef, confidencesteps+1)
        values = Vector{Float64}(undef, confidencesteps+1)
        confidencedelta = last(prognosis.index) - first(prognosis.index)
        for i in 0:confidencesteps
            index[i+1] = first(prognosis.index) + Millisecond(round(Int, confidencedelta.value*(i-1)/confidencesteps))
            values[i+1] = round((confidencesteps-i)/confidencesteps,digits=3)
        end
        confidence = InfiniteTimeVector(index, values)

        new{typeof(level),typeof(profile),typeof(prognosis),typeof(confidence)}(level, profile, prognosis, confidence)
    end

    function PrognosisSeriesParam(level, profile, prognosis) 
        confidence = ConstantTimeVector(1.0)
        new{typeof(level),typeof(profile),typeof(prognosis),typeof(confidence)}(level, profile, prognosis, confidence)
    end

    function PrognosisSeriesParam(level, profile, prognosis, confidence::TimeVector) 
        new{typeof(level),typeof(profile),typeof(prognosis),typeof(confidence)}(level, profile, prognosis, confidence)
    end
end

struct DynamicPrognosisSeriesParam{L <: TimeVector, P <: TimeVector, Prog <: TimeVector, C <: TimeVector} <: Param
    level::L
    profile::P
    prognosis::Prog
    confidence::C

    function DynamicPrognosisSeriesParam(level, profile, prognosis, confidence::TimeVector) 
        new{typeof(level),typeof(profile),typeof(prognosis),typeof(confidence)}(level, profile, prognosis, confidence)
    end
end

getconfidencedatatime(::PrognosisSeriesParam, t::ProbTime) = t.prognosisdatatime
getconfidencedatatime(::DynamicPrognosisSeriesParam, t::ProbTime) = t.datatime

struct UMMSeriesParam{L<:TimeVector,U<:TimeVector,P<:TimeVector} <: Param
    level::L
    ummprofile::U
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
iszero(param::HourProductParam) = false
iszero(param::FossilMCParam) = false
iszero(param::M3SToMM3Param) = false
iszero(param::M3SToMM3SeriesParam) = false
iszero(param::MWToGWhSeriesParam) = false
iszero(param::MWToGWhParam) = false
iszero(param::CostPerMWToGWhParam) = false
iszero(param::MeanSeriesParam) = false
iszero(param::MeanSeriesIgnorePhaseinParam) = false
iszero(param::PrognosisSeriesParam) = false
iszero(param::DynamicPrognosisSeriesParam) = false
iszero(param::ExogenCostParam) = iszero(param.price) && iszero(param.conversion)
iszero(param::ExogenIncomeParam) = iszero(param.price) && iszero(param.conversion)
iszero(param::InConversionLossParam) = iszero(param.conversion)
iszero(param::OutConversionLossParam) = iszero(param.conversion)
iszero(param::TransmissionLossRHSParam) = iszero(param.capacity)
iszero(param::UMMSeriesParam) = false
iszero(param::StatefulParam) = false

isone(param::FlipSignParam) = false
isone(param::ZeroParam) = false
isone(param::PlusOneParam) = true
isone(param::MinusOneParam) = false
isone(param::ConstantParam) = param.value == 1
isone(param::TwoProductParam) = isone(param.param1) && isone(param.param2)
isone(param::HourProductParam) = false
isone(param::FossilMCParam) = false
isone(param::M3SToMM3Param) = false
isone(param::M3SToMM3SeriesParam) = false
isone(param::MWToGWhSeriesParam) = false
isone(param::MWToGWhParam) = false
isone(param::CostPerMWToGWhParam) = false
isone(param::MeanSeriesParam) = false
isone(param::MeanSeriesIgnorePhaseinParam) = false
isone(param::PrognosisSeriesParam) = false
isone(param::DynamicPrognosisSeriesParam) = false
isone(param::ExogenCostParam) = false
isone(param::ExogenIncomeParam) = false
isone(param::InConversionLossParam) = false
isone(param::OutConversionLossParam) = false
isone(param::TransmissionLossRHSParam) = false
isone(param::UMMSeriesParam) = false
isone(param::StatefulParam) = false

isconstant(::ConstantParam) = true
isconstant(::ZeroParam) = true
isconstant(::PlusOneParam) = true
isconstant(::MinusOneParam) = true
isconstant(param::HourProductParam) = false
isconstant(param::TransmissionLossRHSParam) = isconstant(param.capacity)

# Is the parameter value dependant on the temporal aspect?
# Example: MWToGWhSeriesParam is durational since the power produced (GWh),
# will depend on how long you produce for
isdurational(param::FlipSignParam) = isdurational(param.param)
isdurational(param::ZeroParam) = false
isdurational(param::PlusOneParam) = false
isdurational(param::MinusOneParam) = false
isdurational(param::ConstantParam) = false
isdurational(param::TwoProductParam) = isdurational(param.param1) || isdurational(param.param2)
isdurational(param::HourProductParam) = true
isdurational(param::FossilMCParam) = false
isdurational(param::M3SToMM3Param) = true
isdurational(param::M3SToMM3SeriesParam) = true
isdurational(param::MWToGWhSeriesParam) = true
isdurational(param::MWToGWhParam) = true
isdurational(param::CostPerMWToGWhParam) = true
isdurational(param::MeanSeriesParam) = false
isdurational(param::MeanSeriesIgnorePhaseinParam) = false
isdurational(param::PrognosisSeriesParam) = false
isdurational(param::DynamicPrognosisSeriesParam) = false
isdurational(param::ExogenCostParam) = isdurational(param.price) || isdurational(param.conversion) || isdurational(param.loss)
isdurational(param::ExogenIncomeParam) = isdurational(param.price) || isdurational(param.conversion) || isdurational(param.loss)
isdurational(param::InConversionLossParam) = isdurational(param.conversion) || isdurational(param.loss)
isdurational(param::OutConversionLossParam) = isdurational(param.conversion) || isdurational(param.loss)
isdurational(param::TransmissionLossRHSParam) = isdurational(param.capacity)
isdurational(param::UMMSeriesParam) = false
isdurational(param::StatefulParam) = isdurational(param.param)

# Will the parameter change at every new state? Means that the parameter value will have to be recalculated at every time step.
isstateful(param::StatefulParam) = true
isstateful(param::TwoProductParam) = isstateful(param.param1) || isstateful(param.param2)

# Calculate the parameter value for a given parameter, problem time and timedelta duration
getparamvalue(::ZeroParam,     ::ProbTime, ::TimeDelta) =  0.0
getparamvalue(::PlusOneParam,  ::ProbTime, ::TimeDelta) =  1.0
getparamvalue(::MinusOneParam, ::ProbTime, ::TimeDelta) = -1.0
getparamvalue(param::ConstantParam, ::ProbTime, ::TimeDelta; ix=0) = param.value
getparamvalue(param::StatefulParam, start::ProbTime, d::TimeDelta) = getparamvalue(param.param, start, d)
getparamvalue(param::FlipSignParam, start::ProbTime, d::TimeDelta) = -getparamvalue(param.param, start, d)
getparamvalue(param::ExogenIncomeParam, start::ProbTime, d::TimeDelta; ix=0) = getparamvalue(param.price, start, d; ix)*getparamvalue(param.conversion, start, d)*(1-getparamvalue(param.loss, start, d))
getparamvalue(param::ExogenCostParam, start::ProbTime, d::TimeDelta; ix=0) = getparamvalue(param.price, start, d; ix)*getparamvalue(param.conversion, start, d)/(1-getparamvalue(param.loss, start, d))
getparamvalue(param::InConversionLossParam, start::ProbTime, d::TimeDelta) = getparamvalue(param.conversion, start, d)*(1-getparamvalue(param.loss, start, d))
getparamvalue(param::OutConversionLossParam, start::ProbTime, d::TimeDelta) = getparamvalue(param.conversion, start, d)/(1-getparamvalue(param.loss, start, d))
getparamvalue(param::TransmissionLossRHSParam, t::ProbTime, d::TimeDelta) = getparamvalue(param.capacity, t, d)*param.loss*param.utilisation

function getparamvalue(param::TwoProductParam, start::ProbTime, d::TimeDelta; ix=0)
    if ix == 0
        return getparamvalue(param.param1, start, d)*getparamvalue(param.param2, start, d)
    else
        return getparamvalue(param.param1, start, d; ix)*getparamvalue(param.param2, start, d)
    end
end

function getparamvalue(param::HourProductParam, start::ProbTime, d::TimeDelta)
    hours = float(getduration(d).value / 3600 / 1000)
    value = getparamvalue(param.param, start, d)
    return value*hours
end

function getparamvalue(param::FossilMCParam, start::ProbTime, d::TimeDelta; ix=0)
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

function getparamvalue(param::M3SToMM3Param, start::ProbTime, d::TimeDelta)
    m3s = getparamvalue(param.param, start, d)
    seconds = float(getduration(d).value / 1000)
    return m3s * seconds / 1e6
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

function _prognosislogic(param::Union{PrognosisSeriesParam, DynamicPrognosisSeriesParam}, datatime::DateTime, scenariotime::DateTime, d::TimeDelta, confidence::Float64, last_prognosis_time::DateTime)
    if (confidence == 0.0) || (datatime > last_prognosis_time) # Only use profile
        profile = getweightedaverage(param.profile, scenariotime, d)
    elseif (confidence == 1.0) && (datatime + getduration(d) <= last_prognosis_time) # Only use prognosis
        profile = getweightedaverage(param.prognosis, datatime, d)
    else # Combine profile and prognosis 
        if datatime + getduration(d) <= last_prognosis_time # Combine prognosis and profile at a confidence (weighting)
            prognosispart = getweightedaverage(param.prognosis, datatime, d)
            profilepart = getweightedaverage(param.profile, scenariotime, d)

            profile = profilepart*(1-confidence) + prognosispart*confidence
        else # Similar to previous, but with a part that is fully from the profile due to end of prognosis timevector
            new_delta = MsTimeDelta(last_prognosis_time - datatime)
            fullyprofilepart = getweightedaverage(param.profile, scenariotime + getduration(new_delta), d - new_delta)
            prognosispart = getweightedaverage(param.prognosis, datatime, new_delta)
            profilepart = getweightedaverage(param.profile, scenariotime, new_delta)

            profile = profilepart*(1-confidence) + prognosispart*confidence + fullyprofilepart
        end
    end
    return profile
end

function getparamvalue(param::Union{PrognosisSeriesParam, DynamicPrognosisSeriesParam}, start::ProbTime, d::TimeDelta)
    datatime_confidence = getconfidencedatatime(param, start)
    confidence = getweightedaverage(param.confidence, datatime_confidence, d)
    last_prognosis_time = last(param.prognosis.index)
    
    profile = _prognosislogic(param, start.datatime, start.scenariotime, d, confidence, last_prognosis_time)

    level = getweightedaverage(param.level, start.datatime, d)
    value = level * profile
    return value
end

# Calculate the parameter value if the start value is a PhaseinTwoTime
function getparamvalue(param::FossilMCParam, start::Union{PhaseinTwoTime,PhaseinFixedDataTwoTime,PhaseinPrognosisTime}, d::TimeDelta)
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

function getparamvalue(param::MeanSeriesParam, start::Union{PhaseinTwoTime,PhaseinFixedDataTwoTime,PhaseinPrognosisTime}, d::TimeDelta)
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

function getparamvalue(param::M3SToMM3SeriesParam, start::Union{PhaseinTwoTime,PhaseinFixedDataTwoTime,PhaseinPrognosisTime}, d::TimeDelta)
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

function getparamvalue(param::MWToGWhSeriesParam, start::Union{PhaseinTwoTime,PhaseinFixedDataTwoTime,PhaseinPrognosisTime}, d::TimeDelta)
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

function getparamvalue(param::Union{PrognosisSeriesParam, DynamicPrognosisSeriesParam}, start::Union{PhaseinTwoTime,PhaseinFixedDataTwoTime,PhaseinPrognosisTime}, d::TimeDelta)
    datatime_confidence = getconfidencedatatime(param, start)
    confidence = getweightedaverage(param.confidence, datatime_confidence, d)
    last_prognosis_time = last(param.prognosis.index)
    
    phasein = getweightedaverage(start.phaseinvector, start.scenariotime1, d)
    local profile::Float64
    if phasein == 0.0
        profile = _prognosislogic(param, start.datatime, start.scenariotime1, d, confidence, last_prognosis_time)
    elseif phasein == 1.0
        # TODO?: Also possible to phase in datatime: datatime_new = start.datatime + start.scenariotime2 - start.scenariotime1
        profile = _prognosislogic(param, start.datatime, start.scenariotime2, d, confidence, last_prognosis_time)
    else
        profile1 = _prognosislogic(param, start.datatime, start.scenariotime1, d, confidence, last_prognosis_time)
        profile2 = _prognosislogic(param, start.datatime, start.scenariotime2, d, confidence, last_prognosis_time)
        profile = profile1*(1-phasein) + profile2*phasein
    end

    level = getweightedaverage(param.level, start.datatime, d)
    value = level * profile
    return value
end
  
function _phaseinLogic(phaseinvector, param, d, scenariotime1, scenariotime2)
    phasein = getweightedaverage(phaseinvector, scenariotime1, d)
    profile1 = getweightedaverage(param.profile, scenariotime1, d)
    profile2 = getweightedaverage(param.profile, scenariotime2, d)
    profile = profile1 * (1 - phasein) + profile2 * phasein
    return profile
end

function _umm_logic(param, start, d, new_profile_start, new_start_delta)
    datatime = getdatatime(start)
    scenariotime = getscenariotime(start)
    delta = getduration(d)
    over = scenariotime + delta - new_profile_start
    start_to_lastdate = new_profile_start - scenariotime
    @assert start_to_lastdate >= Millisecond(0)
    new_umm_start = datatime
    new_umm_delta = delta - over
    new_profile_delta = over
    new_scen_1 = start.scenariotime1 + new_start_delta
    new_scen_2 = start.scenariotime2 + new_start_delta

    if over > Millisecond(0)
        @assert (over + start_to_lastdate) == delta
        umm_part = getweightedaverage(param.ummprofile, new_umm_start, MsTimeDelta(new_umm_delta))
        profile_part = _phaseinLogic(start.phaseinvector, param, MsTimeDelta(new_profile_delta), new_scen_1, new_scen_2)
        ummprofile = (start_to_lastdate / delta) * umm_part + (over / delta) * profile_part

    else
        ummprofile = getweightedaverage(param.ummprofile, datatime, d)
    end

    return ummprofile
end

function getparamvalue(param::UMMSeriesParam, start::Union{PhaseinTwoTime,PhaseinPrognosisTime}, d::TimeDelta)
    datatime = getdatatime(start)
    scenariotime = getscenariotime(start)
    new_profile_start, new_start_delta = _get_new_profile_start(param, datatime, scenariotime)
    level_mw = getweightedaverage(param.level, datatime, d)
    if scenariotime > new_profile_start

        profile = _phaseinLogic(start.phaseinvector, param, d, start.scenariotime1, start.scenariotime2)
        return level_mw * profile
    end
    profile = _umm_logic(param, start, d, new_profile_start, new_start_delta)
    return level_mw * profile
end

function _get_new_profile_start(param, datatime, scenariotime)
    last_umm_date = last(param.ummprofile.index)
    new_start_delta = last_umm_date - datatime
    new_profile_start = scenariotime + new_start_delta
    return new_profile_start, new_start_delta
end

function getparamvalue(param::UMMSeriesParam, start::ProbTime, d::TimeDelta)
    datatime = getdatatime(start)
    scenariotime = getscenariotime(start)
    new_profile_start, _ = _get_new_profile_start(param, datatime, scenariotime)
    level_mw = getweightedaverage(param.level, datatime, d)

    if scenariotime > new_profile_start
        profile = getweightedaverage(param.profile, scenariotime, d)
        return level_mw * profile
    end

    delta = getduration(d)
    over = scenariotime + delta - new_profile_start
    start_to_lastdate = new_profile_start - scenariotime
    @assert start_to_lastdate >= Millisecond(0)
    new_umm_start = datatime
    new_umm_delta = delta - over
    new_profile_delta = over

    if over > Millisecond(0)
        @assert (over + start_to_lastdate) == delta
        umm_part = getweightedaverage(param.ummprofile, new_umm_start, MsTimeDelta(new_umm_delta))
        profile_part = getweightedaverage(param.profile, new_profile_start, MsTimeDelta(new_profile_delta))
        ummprofile = (start_to_lastdate / delta) * umm_part + (over / delta) * profile_part
    else
        ummprofile = getweightedaverage(param.ummprofile, datatime, d)
    end
    mw = level_mw * ummprofile
    return mw
end

function getparamvalue(param::MWToGWhParam, start::ProbTime, d::TimeDelta)
    mw = getparamvalue(param.param, start, d)
    hours = float(getduration(d).value / 3600000)
    return mw * hours / 1e3
end

# ------ Include dataelements -------

function includeFossilMCParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)

    fuellevel   = getdictvalue(value, "FuelLevel",   TIMEVECTORPARSETYPES, elkey)
    fuelprofile = getdictvalue(value, "FuelProfile", TIMEVECTORPARSETYPES, elkey)
    co2factor   = getdictvalue(value, "CO2Factor",   TIMEVECTORPARSETYPES, elkey)
    co2level    = getdictvalue(value, "CO2Level",    TIMEVECTORPARSETYPES, elkey)
    co2profile  = getdictvalue(value, "CO2Profile",  TIMEVECTORPARSETYPES, elkey)
    efficiency  = getdictvalue(value, "Efficiency",  TIMEVECTORPARSETYPES, elkey)
    voc         = getdictvalue(value, "VOC",         TIMEVECTORPARSETYPES, elkey)
    
    deps = Id[]
    all_ok = true

    (id, fuellevel, ok) = getdicttimevectorvalue(lowlevel, fuellevel)
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    (id, fuelprofile, ok) = getdicttimevectorvalue(lowlevel, fuelprofile) 
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)
    
    (id, co2factor, ok) = getdicttimevectorvalue(lowlevel, co2factor)
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    (id, co2level, ok) = getdicttimevectorvalue(lowlevel, co2level)
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    (id, co2profile, ok) = getdicttimevectorvalue(lowlevel, co2profile)
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)
    
    (id, efficiency, ok) = getdicttimevectorvalue(lowlevel, efficiency)
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    (id, voc, ok) = getdicttimevectorvalue(lowlevel, voc)
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    if all_ok == false
        return (false, deps)
    end
    
    obj = FossilMCParam(fuellevel, fuelprofile, co2factor, co2level, co2profile, efficiency, voc)
    
    lowlevel[getobjkey(elkey)] = obj
    return (true, deps)
end

function includeM3SToMM3Param!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)

    (id, param, ok) = getdictparamvalue(lowlevel, elkey, value)

    deps = Id[]
    _update_deps(deps, id, ok)
    
    ok || return (false, deps)
    
    lowlevel[getobjkey(elkey)] = M3SToMM3Param(param)

    return (true, deps)
end

function includeM3SToMM3SeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)
    
    level   = getdictvalue(value, "Level",   TIMEVECTORPARSETYPES, elkey)
    profile = getdictvalue(value, "Profile", TIMEVECTORPARSETYPES, elkey)

    deps = Id[]
    all_ok = true

    (id, level, ok) = getdicttimevectorvalue(lowlevel, level)
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    (id, profile, ok) = getdicttimevectorvalue(lowlevel, profile)
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    if all_ok == false
        return (false, deps)
    end
    
    lowlevel[getobjkey(elkey)] = M3SToMM3SeriesParam(level, profile)

    return (true, deps)
end

function includeM3SToMM3SeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::M3SToMM3SeriesParam)
    checkkey(lowlevel, elkey)
    deps = Id[]
    lowlevel[getobjkey(elkey)] = value
    return (true, deps)
end

function includeM3SToMM3SeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::AbstractFloat)
    checkkey(lowlevel, elkey)    
    deps = Id[]
    level = ConstantTimeVector(value)
    profile = ConstantTimeVector(one(typeof(value)))
    lowlevel[getobjkey(elkey)] = M3SToMM3SeriesParam(level, profile)
    return (true, deps)
end

function includeMWToGWhSeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)
    
    level   = getdictvalue(value, "Level",   TIMEVECTORPARSETYPES, elkey)
    profile = getdictvalue(value, "Profile", TIMEVECTORPARSETYPES, elkey)

    deps = Id[]
    all_ok = true

    (id, level, ok) = getdicttimevectorvalue(lowlevel, level)    
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)
    
    (id, profile, ok) = getdicttimevectorvalue(lowlevel, profile)  
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    if all_ok == false
        return (false, deps)
    end
    
    lowlevel[getobjkey(elkey)] = MWToGWhSeriesParam(level, profile)
    return (true, deps)
end

function includeMWToGWhSeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::MWToGWhSeriesParam)
    checkkey(lowlevel, elkey)    
    deps = Id[]
    lowlevel[getobjkey(elkey)] = value
    return (true, deps)
end

function includeMWToGWhSeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::AbstractFloat)
    checkkey(lowlevel, elkey)    
    deps = Id[]
    level = ConstantTimeVector(value)
    profile = ConstantTimeVector(one(typeof(value)))
    lowlevel[getobjkey(elkey)] = MWToGWhSeriesParam(level, profile)
    return (true, deps)
end

function includeMWToGWhParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)

    (id, param, ok) = getdictparamvalue(lowlevel, elkey, value)

    deps = Id[]
    _update_deps(deps, id, ok)

    ok || return (false, deps)

    lowlevel[getobjkey(elkey)] = MWToGWhParam(param)
    return (true, deps)
end

function includeCostPerMWToGWhParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)

    deps = Id[]

    if haskey(value, STARTCOSTKEY)
        (id, startcost, ok) = getdictparamvalue(lowlevel, elkey, value, STARTCOSTKEY)
        _update_deps(deps, id, ok)

        ok || return (false, deps)

        lowlevel[getobjkey(elkey)] = CostPerMWToGWhParam(startcost)
        return (true, deps)

    elseif haskey(value, "Level") && haskey(value, "Profile")
        level   = getdictvalue(value, "Level",   TIMEVECTORPARSETYPES, elkey)
        profile = getdictvalue(value, "Profile", TIMEVECTORPARSETYPES, elkey)

        all_ok = true

        (id, level, ok) = getdicttimevectorvalue(lowlevel, level)   
        all_ok = all_ok && ok
        _update_deps(deps, id, ok)

        (id, profile, ok) = getdicttimevectorvalue(lowlevel, profile)
        all_ok = all_ok && ok
        _update_deps(deps, id, ok)

        if all_ok == false
            return (false, deps)
        end

        lowlevel[getobjkey(elkey)] = CostPerMWToGWhParam(MeanSeriesParam(level, profile))
        return (true, deps)
    end
    error("Missing expected Dict-keys for $elkey")
end

function includeCostPerMWToGWhParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::CostPerMWToGWhParam)
    checkkey(lowlevel, elkey)    
    deps = Id[]
    lowlevel[getobjkey(elkey)] = value
    return (true, deps)
end

function includeCostPerMWToGWhParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::AbstractFloat)
    checkkey(lowlevel, elkey)    
    deps = Id[]
    lowlevel[getobjkey(elkey)] = CostPerMWToGWhParam(ConstantParam(value))
    return (true, deps)
end

function includeMeanSeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)
    
    level   = getdictvalue(value, "Level",   TIMEVECTORPARSETYPES, elkey)
    profile = getdictvalue(value, "Profile", TIMEVECTORPARSETYPES, elkey)
    
    deps = Id[]
    all_ok = true

    (id, level, ok) = getdicttimevectorvalue(lowlevel, level)   
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    (id, profile, ok) = getdicttimevectorvalue(lowlevel, profile)
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    if all_ok == false
        return (false, deps)
    end

    lowlevel[getobjkey(elkey)] = MeanSeriesParam(level, profile)
    return (true, deps)
end

function includeMeanSeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::MeanSeriesParam)
    checkkey(lowlevel, elkey)    
    deps = Id[]
    lowlevel[getobjkey(elkey)] = value
    return (true, deps)
end

function includeMeanSeriesIgnorePhaseinParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)
    
    level   = getdictvalue(value, "Level",   TIMEVECTORPARSETYPES, elkey)
    profile = getdictvalue(value, "Profile", TIMEVECTORPARSETYPES, elkey)

    deps = Id[]
    all_ok = true
    
    (id, level, ok) = getdicttimevectorvalue(lowlevel, level)   
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    (id, profile, ok) = getdicttimevectorvalue(lowlevel, profile) 
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    if all_ok == false
        return (false, deps)
    end
    
    lowlevel[getobjkey(elkey)] = MeanSeriesIgnorePhaseinParam(level, profile)
    return (true, deps)
end

function includeMeanSeriesIgnorePhaseinParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::MeanSeriesIgnorePhaseinParam)
    checkkey(lowlevel, elkey)    
    deps = Id[]
    lowlevel[getobjkey(elkey)] = value
    return (true, deps)
end

function includePrognosisSeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)
    
    level   = getdictvalue(value, "Level",   TIMEVECTORPARSETYPES, elkey)
    profile = getdictvalue(value, "Profile", TIMEVECTORPARSETYPES, elkey)
    prognosis = getdictvalue(value, "Prognosis", TIMEVECTORPARSETYPES, elkey)
    steps = getdictvalue(value, "Steps", Int, elkey) 
    steps > 0 || error("Steps <= 0 for $elkey")

    deps = Id[]
    all_ok = true
    
    (id, level, ok) = getdicttimevectorvalue(lowlevel, level)   
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    (id, profile, ok) = getdicttimevectorvalue(lowlevel, profile) 
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    (id, prognosis, ok) = getdicttimevectorvalue(lowlevel, prognosis) 
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    if all_ok == false
        return (false, deps)
    end
    
    lowlevel[getobjkey(elkey)] = PrognosisSeriesParam(level, profile, prognosis, steps)
    return (true, deps)
end

function includeUMMSeriesParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)

    level = getdictvalue(value, "Level", TIMEVECTORPARSETYPES, elkey)
    ummprofile = getdictvalue(value, "Ummprofile", TIMEVECTORPARSETYPES, elkey)
    profile = getdictvalue(value, "Profile", TIMEVECTORPARSETYPES, elkey)

    deps = Id[]
    all_ok = true

    (id, level, ok) = getdicttimevectorvalue(lowlevel, level)
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    (id, ummprofile, ok) = getdicttimevectorvalue(lowlevel, ummprofile)
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    (id, profile, ok) = getdicttimevectorvalue(lowlevel, profile)
    all_ok = all_ok && ok
    _update_deps(deps, id, ok)

    if all_ok == false
        return (false, deps)
    end

    lowlevel[getobjkey(elkey)] = UMMSeriesParam(level, ummprofile, profile)
    return (true, deps)
end

function includeStatefulParam!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)

    deps = Id[]

    (id, param, ok) = getdictparamvalue(lowlevel, elkey, value)
    _update_deps(deps, id, ok)

    ok || return (false, deps)

    lowlevel[getobjkey(elkey)] = StatefulParam(param)

    return (true, deps)
end

INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "FossilMCParam")] = includeFossilMCParam!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "M3SToMM3SeriesParam")] = includeM3SToMM3SeriesParam!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "M3SToMM3Param")] = includeM3SToMM3Param!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "MWToGWhSeriesParam")] = includeMWToGWhSeriesParam!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "MWToGWhParam")] = includeMWToGWhParam!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "CostPerMWToGWhParam")] = includeCostPerMWToGWhParam!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "MeanSeriesParam")] = includeMeanSeriesParam!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "MeanSeriesIgnorePhaseinParam")] = includeMeanSeriesIgnorePhaseinParam!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "PrognosisSeriesParam")] = includePrognosisSeriesParam!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "UMMSeriesParam")] = includeUMMSeriesParam!
INCLUDEELEMENT[TypeKey(PARAM_CONCEPT, "StatefulParam")] = includeStatefulParam!