"""
State variables are the ingoing and outgoing variables. These can be 
inside the horizon periods 1:T or outside (e.g. x[0]).

Ingoing and outgoing state variables are paired together (e.g. x[0] with x[T] 
and x[-1] with x[T-1]). This is convenient if start should equal stop

All state variables must be fixable in this system
to ease the job of adding boundary conditions
"""

# ------- State variable type -------------
struct StateVariableInfo
    var_in::Tuple{Id, Int}
    var_out::Tuple{Id, Int}
end

# -------- General fallback -----------------
getstatevariables(::Any) = StateVariableInfo[]

# -------- Function interface ---------------
getvarin(x::StateVariableInfo) = x.var_in
getvarout(x::StateVariableInfo) = x.var_out

function getingoingstates!(p::Prob, states::Dict{StateVariableInfo, Float64})
    for var in keys(states)
        (id, ix) = getvarin(var)
        states[var] = getvarvalue(p, id, ix)
    end
    return states
end

function getoutgoingstates!(p::Prob, states::Dict{StateVariableInfo, Float64})
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

function setoutgoingstates!(p::Prob, states::Dict{StateVariableInfo, Float64})
    for (var, state) in states
        (id, ix) = getvarout(var)
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

