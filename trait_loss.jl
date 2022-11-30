# ---- Concrete types ----
struct SimpleLoss <: Loss
    value::Float64
    utilisation::Float64
end

# ---- General functions ----

getutilisation(loss::SimpleLoss) = loss.utilisation
isdurational(loss::SimpleLoss) = false
getparamvalue(loss::SimpleLoss, ::ProbTime, ::TimeDelta) = loss.value
isconstant(::SimpleLoss) = true

# ------ Includefunctions ----------------

function includeSimpleLoss!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    lossvalue = getdictvalue(value, LOSSFACTORKEY, Float64, elkey)
    @assert 0.0 <= lossvalue <= 1.0

    utilization = getdictvalue(value, UTILIZATIONKEY, Float64, elkey)
    @assert 0.0 <= utilization <= 1.0
    
    objname    = getdictvalue(value, WHICHINSTANCE, String, elkey)
    objconcept = getdictvalue(value, WHICHCONCEPT,  String, elkey)
    objkey = Id(objconcept, objname)

    if haskey(lowlevel, varkey)
        obj = lowlevel[objkey]
    elseif haskey(toplevel, varkey)
        obj = toplevel[objkey]
    else
        return
    end

    loss = SimpleLoss(lossvalue, utilization)

    setloss!(obj, loss)
    
    return true
end

INCLUDEELEMENT[TypeKey(LOSS_CONCEPT, "SimpleLoss")] = includeSimpleLoss!