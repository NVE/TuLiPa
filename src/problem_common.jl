"""
Contains functions that are shared among all the problem types 
(problem_cplex, problem_highs, problem_jump)
"""

is_CPLEX_Prob(p::Prob) = false # Used to check if the problem type is cplex without having the cplex package