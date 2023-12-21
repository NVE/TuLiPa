"""
Problem that resolves if any soft penalty variables are active.
In the resolve, we fix all penalty variables. This turns soft constraints
into feasible hard constraints. We do this to remove penalty costs from
the dual solution, because we don't want technical penalty parameters
influencing modelled market prices.
"""

struct FixBreach_Prob{P <: Prob} <: Prob
    prob::P
    breachvars::Vector{Tuple{Id, Int}}
    breachcosts::Vector{Float64}

    function FixBreach_Prob(prob::Prob)
        if prob isa FixBreach_Prob
            return prob
        end

        breachvars = Tuple{Id, Int}[]
        for obj in getobjects(prob)
            for (id, varix) in getbreachvars(obj)
                push!(breachvars, (id, varix))
            end
        end

        breachcosts = zeros(length(breachvars))

        return new{typeof(prob)}(prob, breachvars, breachcosts)
    end
end

# Specialized methods
const _FixBreach_Prob_ERRMSG = "Underlying problem already built"
addvar!(p::FixBreach_Prob, id::Id, N::Int) = error(_FixBreach_Prob_ERRMSG)
addeq!(p::FixBreach_Prob, id::Id, N::Int) = error(_FixBreach_Prob_ERRMSG)
addge!(p::FixBreach_Prob, id::Id, N::Int) = error(_FixBreach_Prob_ERRMSG)
addle!(p::FixBreach_Prob, id::Id, N::Int) = error(_FixBreach_Prob_ERRMSG)
makefixable!(p::FixBreach_Prob, varid::Id, varix::Int) = error(_FixBreach_Prob_ERRMSG)
getbreachvars(obj::Any) = []

function solve!(p::FixBreach_Prob)
    firsttime = @elapsed solve!(p.prob)

    need_resolve = false
    for (i, (id, t)) in enumerate(p.breachvars)
        value = getvarvalue(p, id, t)
        if value > zero(typeof(value))
            need_resolve = true
            break
        end
    end

    if need_resolve == false
        return
    end

    count = 0
    for (i, (id, t)) in enumerate(p.breachvars)
        value = getvarvalue(p, id, t)
        fix!(p, id, t, value)
        p.breachcosts[i] = getobjcoeff(p, id, t)
        setobjcoeff!(p, id, t, 0.0)
        if value > zero(typeof(value))
            count += 1
        end
    end

    mainwarmstart = getwarmstart(p)
    mainwarmstart == false && setwarmstart!(p, true)

    secondtime = @elapsed solve!(p.prob)
    println("$count breaches. First and second solves $firsttime / $secondtime")

    mainwarmstart == false && setwarmstart!(p, false)

    for (i, (id, t)) in enumerate(p.breachvars)
        # if p.breachcosts[i] > 0
        unfix!(p, id, t)
        setobjcoeff!(p, id, t, p.breachcosts[i])
        # end
    end

    fill!(p.breachcosts, 0.0)

    return
end

# Forwarded methods
update!(p::FixBreach_Prob, start::ProbTime) = update!(p.prob, start)
getobjects(p::FixBreach_Prob) = getobjects(p.prob)
gethorizons(p::FixBreach_Prob) = gethorizons(p.prob)
setconcoeff!(p::FixBreach_Prob, con::Id, var::Id, ci::Int, vi::Int, value::Float64) = setconcoeff!(p.prob, con, var, ci, vi, value)
setub!(p::FixBreach_Prob, var::Id, i::Int, value::Float64) = setub!(p.prob, var, i, value)
setlb!(p::FixBreach_Prob, var::Id, i::Int, value::Float64) = setlb!(p.prob, var, i, value)
setobjcoeff!(p::FixBreach_Prob, var::Id, i::Int, value::Float64) = setobjcoeff!(p.prob, var, i, value)
setrhsterm!(p::FixBreach_Prob, con::Id, trait::Id, i::Int, value::Float64) = setrhsterm!(p.prob, con, trait, i, value)
getobjectivevalue(p::FixBreach_Prob) = getobjectivevalue(p.prob)
setvarvalues!(p::FixBreach_Prob) = setvarvalues!(p.prob)
setconduals!(p::FixBreach_Prob) = setconduals!(p.prob)
getvarvalue(p::FixBreach_Prob, key::Id, t::Int) = getvarvalue(p.prob, key, t)
getcondual(p::FixBreach_Prob, key::Id, t::Int) = getcondual(p.prob, key, t)
getrhsterm(p::FixBreach_Prob, con::Id, trait::Id, i::Int) = getrhsterm(p.prob, con, trait, i)
hasrhsterm(p::FixBreach_Prob, con::Id, trait::Id, i::Int) = hasrhsterm(p.prob, con, trait, i)
getlb(p::FixBreach_Prob, var::Id, i::Int) = getlb(p.prob, var, i)
getub(p::FixBreach_Prob, var::Id, i::Int) = getub(p.prob, var, i)
getconcoeff(p::FixBreach_Prob, con::Id, var::Id, ci::Int, vi::Int) = getconcoeff(p.prob, con, var, ci, vi)
getobjcoeff(p::FixBreach_Prob, var::Id, i::Int) = getobjcoeff(p.prob, var, i)
getfixvardual(p::FixBreach_Prob, varid::Id, varix::Int) = getfixvardual(p.prob, varid, varix)
fix!(p::FixBreach_Prob, varid::Id, varix::Int, value::Float64) = fix!(p.prob, varid, varix, value)
unfix!(p::FixBreach_Prob, varid::Id, varix::Int) = unfix!(p.prob, varid, varix)
setsilent!(p::FixBreach_Prob) = setsilent!(p.prob)
unsetsilent!(p::FixBreach_Prob) = unsetsilent!(p.prob)
getwarmstart(p::FixBreach_Prob) = getwarmstart(p.prob)
setwarmstart!(p::FixBreach_Prob, bool::Bool) = setwarmstart!(p.prob, bool)