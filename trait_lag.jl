# Ramping and StartCost is special case. Does not use Arrow and Lag.

# TODO: Implement TimeDelayLag (which must deal with duration)

struct DifferentialLag <: Lag end
struct NoLag           <: Lag end

isdifferential(::DifferentialLag) = true
isdifferential(::NoLag) = false

getdelay(::DifferentialLag) = nothing
getdelay(::NoLag) = nothing

function getstatevariables(var::Any, ::Arrow, ::DifferentialLag)
    var_in_id = getstartvarid(var)
    var_out_id = getid(var)
    var_out_ix = getnumperiods(gethorizon(var))
    info = StateVariableInfo((var_in_id, 1), (var_out_id, var_out_ix))
    return [info]
end
getstatevariables(::Any, ::Arrow, ::NoLag) = StateVariableInfo[]

build!(::Prob, ::DifferentialLag) = nothing
build!(::Prob, ::NoLag) = nothing

setconstants!(::Prob, ::DifferentialLag) = nothing
setconstants!(::Prob, ::NoLag) = nothing

update!(::Prob, ::DifferentialLag, ::ProbTime) = nothing
update!(::Prob, ::NoLag, ::ProbTime) = nothing

function getsubperiods(balance_horizon::Horizon, flow_horizon::Horizon, s::Int, ::DifferentialLag)
    @assert balance_horizon === flow_horizon
    s0 = s - 1
    return max(s0, 1):s0
end

function getsubperiods(balance_horizon::Horizon, flow_horizon::Horizon, s::Int, ::NoLag)
    return getsubperiods(balance_horizon, flow_horizon, s)
end


