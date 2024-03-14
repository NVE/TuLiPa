# --- Helper functions used to include data elements -----

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


const  TIMEVECTORPARSETYPES = Union{AbstractFloat, String, TimeVector}
function getdicttimevectorvalue(lowlevel::Dict, value::String)
    objkey = Id(TIMEVECTOR_CONCEPT, value)
    haskey(lowlevel, objkey) && return (objkey, lowlevel[objkey], true)
    return (objkey, value, false)
end

getdicttimevectorvalue(::Dict, value::AbstractFloat) = (nothing, ConstantTimeVector(value), true)
getdicttimevectorvalue(::Dict, value::TimeVector) = (nothing, value, true)

# Parse Param
const  PARAMPARSETYPES = Union{AbstractFloat, String, Param}
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

# Parse ParamList
function getdictparamlist(lowlevel::Dict, elkey::ElementKey, value::Dict, paramname=PARAM_CONCEPT)
    haskey(value, paramname) || error("Missing $paramname for $elkey")
    paramlist = [getdictparamvalue(lowlevel, elkey, listvalue) for listvalue in value[paramname]]
    paramvaluelist = [first(param) for param in paramlist]
    parambool = [bool for (param,bool) in paramlist]
    all(y->y==true,parambool) || return (paramvaluelist, false)
    return (paramvaluelist, true)
end

# Parse Conversion
# If conversion is a constant or param it should be converted to BaseConversion
function getdictconversionvalue(lowlevel::Dict, elkey::ElementKey, value::Dict)
    haskey(value, CONVERSION_CONCEPT) || error("Missing $CONVERSION_CONCEPT for $elkey")
    conversion = getdictconversionvalue(lowlevel, elkey, value[CONVERSION_CONCEPT])
    return conversion
end

function getdictconversionvalue(lowlevel::Dict, elkey::ElementKey, value::String)
    objkey = Id(CONVERSION_CONCEPT, value)
    haskey(lowlevel, objkey) && return (lowlevel[objkey], true)
    objkey = Id(PARAM_CONCEPT, value)
    haskey(lowlevel, objkey) && return getdictconversionvalue(lowlevel, elkey, lowlevel[objkey])
    return (value, false)
end

getdictconversionvalue(::Dict, ::ElementKey, value::AbstractFloat) = (BaseConversion(ConstantParam(value)), true)
getdictconversionvalue(::Dict, ::ElementKey, value::Param) = (BaseConversion(value), true)
getdictconversionvalue(::Dict, ::ElementKey, value::Conversion) = (value, true)

# Parse Price
# If price is a constant or param it should be converted to BasePrice
function getdictpricevalue(lowlevel::Dict, elkey::ElementKey, value::Dict)
    haskey(value, PRICE_CONCEPT) || error("Missing $PRICE_CONCEPT for $elkey")
    (id, obj, ok) = getdictpricevalue(lowlevel, elkey, value[PRICE_CONCEPT])
    return (id, obj, ok)
end

function getdictpricevalue(lowlevel::Dict, elkey::ElementKey, value::String)
    objkey = Id(PRICE_CONCEPT, value)
    haskey(lowlevel, objkey) && return (objkey, lowlevel[objkey], true)
    objkey = Id(PARAM_CONCEPT, value)
    haskey(lowlevel, objkey) && return (objkey, BasePrice(lowlevel[objkey]), true)
    return (nothing, value, false)
end

getdictpricevalue(::Dict, ::ElementKey, value::AbstractFloat) = (nothing, BasePrice(ConstantParam(value)), true)
getdictpricevalue(::Dict, ::ElementKey, value::Param) = (nothing, BasePrice(value), true)
getdictpricevalue(::Dict, ::ElementKey, value::Price) = (nothing, value, true)