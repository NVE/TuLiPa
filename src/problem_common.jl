"""
Contains functions that are shared among all the problem types 
(problem_cplex, problem_highs, problem_jump)
"""

# -------- Update problem for given problem time --------------
function update!(p::Prob, start::ProbTime)
    # Update horizons that need to dynamically update
    for horizon in gethorizons(p)
        update!(horizon, start)
    end
    
    # Loop through all model objects. Set parameters and coefficients that
    # depend on the problem time and period in the horizon.
    # The generic function update! has different methods depending on the inputed object
    # Some objects will again call update! on its internal traits
    for obj in getobjects(p)
        update!(p, obj, start)
    end
end

# ----- Check if specific problem type ----------
is_CPLEX_Prob(p::Prob) = false