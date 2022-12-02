struct BaseAggSupplyCurve <: AggSupplyCurve
    id::Id
    balance::Balance
    flows::Vector{Flow}
    numclusters::Int
end

getid(var::BaseAggSupplyCurve) = var.id
getbalance(var::BaseAggSupplyCurve) = var.balance
getflows(var::BaseAggSupplyCurve) = var.flows
getnumclusters(var::BaseAggSupplyCurve) = var.numclusters

getmainmodelobject(var::AggSupplyCurve) = getbalance(var)

function build!(p::Prob, var::AggSupplyCurve)
    varname = getinstancename(var.id)
    eqperiods = getnumperiods(gethorizon(getcommodity(var.balance)))

    for c in 1:var.numclusters
        newname = string(varname,"_",c)
        addvar!(p, Id(AGGSUPPLYCURVE_CONCEPT,newname), eqperiods)
    end  
end

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

function update!(p::Prob, var::AggSupplyCurve, start::ProbTime)
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

    for i in 1:numflows
        flow = var.flows[i]
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
    
    Random.seed!(1000)
    for t in 1:T
        r = kmeans(reshape(mcs[t,:],1,numflows), var.numclusters)
        assignments = r.assignments

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

            if ub == 0
                mc = 100000
            else
                mc /= ub
            end

            newname = string(varname,"_",assignment)
            newid = Id(AGGSUPPLYCURVE_CONCEPT, newname)

            setobjcoeff!(p, newid, t, float(mc))
            setlb!(p, newid, t, float(lb))
            setub!(p, newid, t, float(ub))
        end
    end
end