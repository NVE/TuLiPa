"""
Contains functions that are shared among all the problem types 
(problem_cplex, problem_highs, problem_jump)
"""

# -------- Update problem for given problem time --------------
function update!(p::Prob, start::ProbTime)
    for horizon in gethorizons(p)
        update!(horizon, start)
    end
    for obj in getobjects(p)
        update!(p, obj, start)
    end
    return
end

function buildhorizons!(p::Prob)
    horizons = Set(gethorizon(x) for x in getobjects(p) if x isa Balance)
    for h in horizons
        build!(h, p)
    end
    p.horizons = Horizon[h for h in horizons]
    return
end

function build!(p::Prob)
    for obj in getobjects(p)
        build!(p, obj)
    end
    return
end

function setconstants!(p::Prob)
    for obj in getobjects(p)
        setconstants!(p, obj)
    end
    return
end

# ----- Check if specific problem type ----------
is_CPLEX_Prob(p::Prob) = false