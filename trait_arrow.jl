"""
We implement BaseArrow and SegmentedArrow. Since they
"""

# ------- Generic fallbacks -------------
gethorizon(arrow::Arrow) = gethorizon(getbalance(arrow))

# ------- Concrete types ----------------
mutable struct BaseArrow <: Arrow
    id::Id
    balance::Balance
    conversion::Conversion
    loss::Union{Loss, Nothing}
    isingoing::Bool

    function BaseArrow(id, balance, conversion, isingoing)
        new(id, balance, conversion, nothing, isingoing)
    end

    function BaseArrow(id, balance, conversion, loss, isingoing)
        new(id, balance, conversion, loss, isingoing)
    end
end

mutable struct SegmentedArrow <: Arrow
    id::Id
    balance::Balance
    conversions::Vector{Conversion}
    capacities::Vector{Param}
    isingoing::Bool
end

# ----- Interface for our concrete types --------------
const OurArrowTypes = Union{BaseArrow, SegmentedArrow}

getid(arrow::OurArrowTypes) = arrow.id
getstatevariables(::OurArrowTypes) = StateVariableInfo[]

getbalance(arrow::OurArrowTypes) = arrow.balance
setbalance!(arrow::OurArrowTypes, balance::Balance) = arrow.balance = balance

isingoing(arrow::OurArrowTypes) = arrow.isingoing

# -------- General functions ----------------
# BaseArrow has these elements describing the contribution of the variable in the Balance
getconversion(arrow::BaseArrow) = arrow.conversion
getloss(arrow::BaseArrow) = arrow.loss

setloss!(arrow::BaseArrow, loss::Loss) = arrow.loss = loss

# SegmentedArrow has these elements describing the contribution of the varible in the Balance
getconversions(arrow::SegmentedArrow) = arrow.conversions
getcapacities(arrow::SegmentedArrow) = arrow.capacities

getconversion(::SegmentedArrow) = error("Not supported")
getloss(::SegmentedArrow) = nothing
setloss!(::SegmentedArrow, loss::Loss) = error("SegmentedArrow does not support")

# SegmentedArrow creates variables and equations that needs ids/names
function getsegmentid(arrow::SegmentedArrow, i::Int)
    Id(getconceptname(arrow.id),string(getinstancename(arrow.id),i))
end

function geteqid(arrow::SegmentedArrow)
    Id(getconceptname(arrow.id),string(getinstancename(arrow.id),"Eq"))
end

# ---------- Exogen cost/income
# BaseArrow build a CostTerm if the Balance is exogenous.
# This is added to the sumcost of a BaseFlow
function getexogencost(arrow::BaseArrow)

    if isexogen(arrow.balance)

        if arrow.isingoing
            if isnothing(arrow.loss) && isone(arrow.conversion)
                param = getprice(arrow.balance)
            elseif isnothing(arrow.loss)
                param = TwoProductParam(getprice(arrow.balance), arrow.conversion)
            else
                param = ExogenIncomeParam(getprice(arrow.balance), arrow.conversion, arrow.loss)
            end
        else
            if isnothing(arrow.loss) && isone(arrow.conversion)
                param = getprice(arrow.balance)
            elseif isnothing(arrow.loss)
                param = TwoProductParam(getprice(arrow.balance), arrow.conversion)
            else
                param = ExogenCostParam(getprice(arrow.balance), arrow.conversion, arrow.loss)
            end
        end
        
        id = Id(COST_CONCEPT, "ExCost_" * getinstancename(arrow.id))
        cost = CostTerm(id, param, !arrow.isingoing)
        
        return cost
    else
        return nothing
    end
end

# SegmentedArrow does not fit the cost interface of a BaseFlow
# See setconstants! and update! for how the exogenous cost is added to the problem
getexogencost(::SegmentedArrow) = nothing

# ------ build! ----------------

# BaseArrow can build the conversion if this is needed
function build!(p::Prob, ::Any, arrow::BaseArrow)
    build!(p, arrow.conversion)
    return
end

# Segmentedarrow creates equations and variables
function build!(p::Prob, var::Any, arrow::SegmentedArrow)
    T = getnumperiods(gethorizon(var))
    
    addeq!(p, geteqid(arrow), T) 

    for i in eachindex(getconversions(arrow))
        addvar!(p, getsegmentid(arrow, i), T)
    end
end

# ------ setconstants! and update! -----------------------

# BaseArrow 
function setconstants!(p::Prob, var::Any, arrow::BaseArrow)
    # Update the conversion if this is needed
    setconstants!(p, arrow.conversion)

    # If the balance is exogen, the contribution of the variabe is added to the Balance
    if !isexogen(arrow.balance)
        if isnothing(arrow.loss)
            # If there is no loss the parameter only consist of the conversion
            param = arrow.conversion
        else
            # Depending on the direction of the arrow, the conversion is multiplied 
            # or divided by (1-loss)
            # See getparamvalue() of InConversionLossParam and OutConversionLossParam
            if arrow.isingoing
                param = InConversionLossParam(arrow.conversion, arrow.loss)
            else
                param = OutConversionLossParam(arrow.conversion, arrow.loss)
            end
        end

        if isconstant(param)            
            varhorizon = gethorizon(var)
            balancehorizon = gethorizon(arrow.balance)

            # The parameter is constant for all scenarios and time
            # and can be calculated once
            value = getparamvalue(param, ConstantTime(), MsTimeDelta(Hour(1)))

            # The direction also decides if the contribution is positive or negative
            if !arrow.isingoing 
                value = -value
            end

            for s in 1:getnumperiods(balancehorizon)
                subperiods = getsubperiods(balancehorizon, varhorizon, s)
                for t in subperiods
                    # The contribution of the variable is added to the balance for each time period
                    setconcoeff!(p, getid(arrow.balance), getid(var), s, t, value)
                end
            end
        end
    end  
end

# See comments for setconstants! over
function update!(p::Prob, var::Any, arrow::BaseArrow, start::ProbTime)
    update!(p, arrow.conversion, start)

    if !isexogen(arrow.balance)
        if isnothing(arrow.loss)
            param = arrow.conversion
        else
            if arrow.isingoing
                param = InConversionLossParam(arrow.conversion, arrow.loss)
            else
                param = OutConversionLossParam(arrow.conversion, arrow.loss)
            end
        end

        if !isconstant(param)

            varhorizon = gethorizon(var)
            balancehorizon = gethorizon(arrow.balance)

            for s in 1:getnumperiods(balancehorizon)
                subperiods = getsubperiods(balancehorizon, varhorizon, s)
                for t in subperiods
                    querystart = getstarttime(varhorizon, t, start)
                    querydelta = gettimedelta(varhorizon, t)
                    value = getparamvalue(param, querystart, querydelta)
                    if !arrow.isingoing 
                        value = -value
                    end

                    setconcoeff!(p, getid(arrow.balance), getid(var), s, t, value)
                end
            end
        end
    end  
end

# SegmentedArrow
function setconstants!(p::Prob, var::Any, arrow::SegmentedArrow)
    varhorizon = gethorizon(var)
    T = getnumperiods(gethorizon(var))

    balancehorizon = gethorizon(arrow.balance)

    conversions = getconversions(arrow)
    capacities = getcapacities(arrow)
    
    # Main variable should equal the sum of the segmented variables
    eqid = geteqid(arrow)
    for t in 1:T
        setconcoeff!(p, eqid, getid(var), t, t, 1.0)
    end

    # For each segment
    for i in eachindex(capacities)
        for t in 1:T
            setconcoeff!(p, eqid, getsegmentid(arrow,i), t, t, -1.0)

            # LB of segmented variables are set to 0
            setlb!(p, getsegmentid(arrow, i), t, 0.0)
        end
    
        # UB of the segmented variables are set
        capacity = capacities[i]
        if !_must_dynamic_update(capacity, varhorizon)
            if isdurational(capacity)
                for t in 1:T
                    querydelta = gettimedelta(varhorizon, t)
                    value = getparamvalue(capacity, ConstantTime(), querydelta)
                    setub!(p, getsegmentid(arrow, i), t, value)
                end               
            else
                value = getparamvalue(capacity, ConstantTime(), MsTimeDelta(Hour(1)))
                for t in 1:T 
                    setub!(p, getsegmentid(arrow, i), t, value)
                end
            end
        end

        # Contribution of the variable
        conversion = conversions[i]
        if isexogen(arrow.balance)
            # The exogen cost/income of the segment variables is added to the objective function
            if isone(conversion)
                param = getprice(arrow.balance)
            else
                param = TwoProductParam(getprice(arrow.balance), conversion)
            end
            if isconstant(param)
                value = getparamvalue(param, ConstantTime(), MsTimeDelta(Hour(1)))
                if !arrow.isingoing
                    value = -value
                end
                for t in 1:T
                    setobjcoeff!(p, getsegmentid(arrow, i), t, value)
                end
            end
    
        else
            # The contribution of the segment variables is added to the Balance
            if isconstant(conversion)
                value = getparamvalue(conversion, ConstantTime(), MsTimeDelta(Hour(1)))
                if !arrow.isingoing
                    value = -value
                end

                for s in 1:getnumperiods(balancehorizon)
                    subperiods = getsubperiods(balancehorizon, varhorizon, s)
                    for t in subperiods        
                        setconcoeff!(p, getid(arrow.balance), getsegmentid(arrow, i), s, t, value)
                    end
                end 
            end
        end
    end
    return
end

# See comments for setconstants! over
function update!(p::Prob, var::Any, arrow::SegmentedArrow, start::ProbTime)
    varhorizon = gethorizon(var)
    T = getnumperiods(varhorizon)

    balancehorizon = gethorizon(arrow.balance)

    conversions = getconversions(arrow)
    capacities = getcapacities(arrow)

    for i in eachindex(capacities)        
        capacity = capacities[i]
        if _must_dynamic_update(capacity, varhorizon)
            for t in 1:T
                querystart = getstarttime(varhorizon, t, start)
                querydelta = gettimedelta(varhorizon, t)
                value = getparamvalue(capacity, querystart, querydelta)  
                setlb!(p, getsegmentid(arrow, i), t, 0.0)
                setub!(p, getsegmentid(arrow, i), t, value)
            end
        end

        conversion = conversions[i]

        if isexogen(arrow.balance)

            if isone(conversion)
                param = getprice(arrow.balance)
            else
                param = TwoProductParam(getprice(arrow.balance), conversion)
            end
            if !isconstant(param)
                for t in 1:T
                    querystart = getstarttime(varhorizon, t, start)
                    querydelta = gettimedelta(varhorizon, t)
                    value = getparamvalue(param, querystart, querydelta)
                    if !arrow.isingoing
                        value = -value
                    end

                    setobjcoeff!(p, getsegmentid(arrow, i), t, value)
                end
            end
        else
            if !isconstant(conversion)
                for s in 1:getnumperiods(balancehorizon)
                    subperiods = getsubperiods(balancehorizon, varhorizon, s)
                    for t in subperiods
                        querystart = getstarttime(varhorizon, t, start)
                        querydelta = gettimedelta(varhorizon, t)
                        value = getparamvalue(conversion, querystart, querydelta)
                        if !arrow.isingoing
                            value = -value
                        end

                        setconcoeff!(p, getid(arrow.balance), getsegmentid(arrow, i), s, t, value)
                    end
                end 
            end
        end
    end
    return
end

# ---------- Include functions -----------------
function includeBaseArrow!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)

    varname = getdictvalue(value, FLOW_CONCEPT, String, elkey) 
    varkey = Id(FLOW_CONCEPT, varname)
    haskey(toplevel, varkey) || return false
    
    balancename = getdictvalue(value, BALANCE_CONCEPT, String, elkey)
    balancekey = Id(BALANCE_CONCEPT, balancename)
    haskey(toplevel, balancekey) || return false

    (conversion, ok) = getdictconversionvalue(lowlevel, elkey, value)
    ok || return false
    
    isingoing = getdictisingoing(value, elkey)
    balance   = toplevel[balancekey]
    var      = toplevel[varkey]

    objkey = getobjkey(elkey)

    arrow = BaseArrow(objkey, balance, conversion, isingoing)
    
    addarrow!(var, arrow)
    lowlevel[objkey] = arrow
     
    return true    
end

function includeSegmentedArrow!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    (conversionparams, ok) = getdictparamlist(lowlevel, elkey, value, CONVERSION_CONCEPT)
    ok || return false
    conversions = [BaseConversion(cp) for cp in conversionparams]
    
    (capacities, ok) = getdictparamlist(lowlevel, elkey, value, CAPACITY_CONCEPT)
    ok || return false

    balancename = getdictvalue(value, BALANCE_CONCEPT, String, elkey)
    balancekey = Id(BALANCE_CONCEPT, balancename)
    haskey(toplevel, balancekey) || return false
    
    varname = getdictvalue(value, FLOW_CONCEPT, String, elkey)
    varkey = Id(FLOW_CONCEPT, varname)
    haskey(toplevel, varkey) || return false
    
    isingoing = getdictisingoing(value, elkey)
    balance   = toplevel[balancekey]
    var      = toplevel[varkey]

    arrow = SegmentedArrow(getobjkey(elkey), balance, conversions, capacities, isingoing)
    addarrow!(var, arrow)
     
    return true    
end

INCLUDEELEMENT[TypeKey(ARROW_CONCEPT, "BaseArrow")] = includeBaseArrow!
INCLUDEELEMENT[TypeKey(ARROW_CONCEPT, "SegmentedArrow")] = includeSegmentedArrow!