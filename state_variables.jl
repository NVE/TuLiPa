
"""
All state variables must be fixable in this system
to ease the job of adding boundary conditions
"""

struct StateVariableInfo
    var_in::Tuple{Id, Int}
    var_out::Tuple{Id, Int}
end

getvarin(x::StateVariableInfo) = x.var_in
getvarout(x::StateVariableInfo) = x.var_out

getstatevariables(::Any) = StateVariableInfo[]

function getoutgoingstates!(states::Dict{StateVariableInfo, Float64}, p::Prob)
    for var in keys(states)
        (id, ix) = getvarout(var)
        states[var] = getvarvalue(p, id, ix)
    end
    return states
end

function setingoingstates!(p::Prob, states::Dict{StateVariableInfo, Float64})
    for (var, state) in states
        (id, ix) = getvarin(var)
        fix!(p, id, ix, state)
    end
    return
end

function getcutparameters(p::Prob, states::Dict{StateVariableInfo, Float64})
    constant = getobjectivevalue(p)
    slopes = Dict{StateVariableInfo, Float64}()
    for (var, state) in states
        (id, ix) = getvarin(var)
        slope = getfixvardual(p, id, ix)
        constant -= slope * state
        slopes[var] = slope
    end
    return (constant, slopes)
end

