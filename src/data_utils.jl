# --- Helper functions used to include data elements -----

_update_deps(deps::Any, id::Nothing, ok::Bool) = @assert ok
_update_deps(deps::Tuple{Vector{String}, Vector{Id}}, id::Id, ok::Bool) = push!(deps[2], id)
_update_deps(deps::Vector{Id}, id::Id, ok::Bool) = push!(deps, id)
function _update_deps(deps::Tuple{Vector{String}, Vector{Id}}, id, ok::Bool)
    for i in id
        _update_deps(deps, i, ok)
    end
end
function _update_deps(deps::Vector{Id}, ids, ok::Bool)
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
    paramvaluelist = [p for (id, p, ok) in paramlist]
    parambools = [ok for (id, p, ok) in paramlist]
    ids = [id for (id, p, ok) in paramlist]
    return (ids, paramvaluelist, all(y->y==true, parambools))
end

# Parse Conversion
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

# Parse Price
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