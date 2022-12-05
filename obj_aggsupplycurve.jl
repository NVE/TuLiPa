"""
We implement BaseAggSupplyCurve

This type takes a list of "simple" Flows that are connected to the same balance 
("simple" as they are only connected to one balance).
The parameter numclusters is the number of equivalent flows (or variables) that
should represent the list of Flows
This object only considers the cost, upper capacity and lower capacity
when aggregating the flows to equivalent flows
The aggregation is done with kmeans clustering of the costs
The equivalent flows is represented with the mean cost, and the sum
of lower and upper capacities of each cluster

NB! Other traits (like startupcosts and softbounds) are not considered
in the clustering and should be deleted if this type is used

This method assumes that the Flows are connected to an endogenous Balance.
If the Balance is exogenous the "simple" Flows are excessive

SegmentedArrow (production represented by efficiency segments) not supported
"""

# ---- Concrete types ----------------
struct BaseAggSupplyCurve <: AggSupplyCurve
    id::Id
    balance::Balance
    flows::Vector{Flow}
    numclusters::Int
end

# --- Interface functions ---
getid(var::BaseAggSupplyCurve) = var.id
getbalance(var::BaseAggSupplyCurve) = var.balance
getflows(var::BaseAggSupplyCurve) = var.flows
getnumclusters(var::BaseAggSupplyCurve) = var.numclusters

getmainmodelobject(var::AggSupplyCurve) = var.balance

# Build the equivalent variables
function build!(p::Prob, var::AggSupplyCurve)
    varname = getinstancename(var.id)
    eqperiods = getnumperiods(gethorizon(getcommodity(var.balance)))

    for c in 1:var.numclusters
        newname = string(varname,"_",c)
        addvar!(p, Id(AGGSUPPLYCURVE_CONCEPT,newname), eqperiods)
    end  
end

# Include the equivalent Flows in the endogenous Balance
function setconstants!(p::Prob, var::AggSupplyCurve)
    varname = getinstancename(var.id)
    eqinstance = split(varname, "PlantAgg_")[2]
    eqperiods = getnumperiods(gethorizon(getcommodity(var.balance)))
    
    for c in 1:var.numclusters
        newname = string(varname,"_",c)
        for t in 1:eqperiods
            setconcoeff!(p, Id(BALANCE_CONCEPT, eqinstance), Id(AGGSUPPLYCURVE_CONCEPT, newname), t, t, 1.0)
        end
    end
end

# Update the problem with cost and upper/lower bound for each equivalent flow
function update!(p::Prob, var::AggSupplyCurve, start::ProbTime)
    # Initialize
    horizon = gethorizon(getcommodity(var.balance))
    T = getnumperiods(horizon)
    
    varname = getinstancename(var.id)
    numflows = length(var.flows)
    mcs = zeros(Float64,T,numflows)
    lbs = zeros(Float64,T,numflows)
    ubs = zeros(Float64,T,numflows)
    
    querystarts = Vector{typeof(start)}(undef, T)
    querydeltas = Vector{Any}(undef,T) 
    
    dummytime = ConstantTime()
    dummydelta = MsTimeDelta(Hour(1))

    for t in 1:T
        querystarts[t] = getstarttime(horizon, t, start)
        querydeltas[t] = gettimedelta(horizon, t)
    end

    # Calculate costs and upper/lower bound for each flow and timeperiod
    for i in 1:numflows
        flow = var.flows[i]

        # Cost
        cost = getcost(flow)
        if isconstant(cost)
            paramvalue = getparamvalue(cost, dummytime, dummydelta)
            for t in 1:T
                mcs[t,i] = paramvalue # pq not supported
            end
        else
            for t in 1:T
                mcs[t,i] = getparamvalue(cost, querystarts[t], querydeltas[t]) # pq not supported
            end
        end   

        # Lower bound
        lb = getlb(flow)
        if isconstant(lb) && !isdurational(lb)
            paramvalue = getparamvalue(lb, dummytime, dummydelta)
            for t in 1:T
                lbs[t,i] = paramvalue 
            end
        else
            for t in 1:T
                lbs[t,i] = getparamvalue(lb, querystarts[t], querydeltas[t])
            end
        end

        # Upper bound
        ub = getub(flow)
        if isconstant(ub) && !isdurational(ub)
            paramvalue = getparamvalue(ub, dummytime, dummydelta)
            for t in 1:T
                ubs[t,i] = paramvalue 
            end
        else
            for t in 1:T
                ubs[t,i] = getparamvalue(ub, querystarts[t], querydeltas[t]) 
            end
        end
    end
    
    # Constant seed for reproducability of clustering
    Random.seed!(1000)

    # For each timeperiod cluster flows by costs
    for t in 1:T
        r = kmeans(reshape(mcs[t,:],1,numflows), var.numclusters)
        assignments = r.assignments

        # For each cluster aggregate costs and upper/lower bounds
        for assignment in 1:var.numclusters
            mc = 0
            lb = 0
            ub = 0
            for j in 1:numflows
                if assignments[j] == assignment
                    mc += mcs[t,j]*ubs[t,j]
                    lb += lbs[t,j]
                    ub += ubs[t,j]
                end
            end

            if ub == 0 # TODO: More robust. Checks
                mc = 100000
            else
                mc /= ub
            end

            newname = string(varname,"_",assignment)
            newid = Id(AGGSUPPLYCURVE_CONCEPT, newname)

            # Set costs and upper/lower bounds for timeperiod and cluster
            setobjcoeff!(p, newid, t, float(mc))
            setlb!(p, newid, t, float(lb))
            setub!(p, newid, t, float(ub))
        end
    end
end