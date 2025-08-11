"""
We implement some concrete ProbMethod (see abstracttypes.jl)
"""

# Problem method objects
struct HighsSimplexMethod <: ProbMethod
    warmstart::Bool
    function HighsSimplexMethod(;warmstart=true)
        new(warmstart) 
    end
end
struct HighsPrimalSimplexMethod <: ProbMethod
    warmstart::Bool
    function HighsPrimalSimplexMethod(;warmstart=true)
        new(warmstart) 
    end
end
struct HighsSimplexPAMIMethod <: ProbMethod # parallel simplex method max 8 threads
    warmstart::Bool
    concurrency::Int64
    function HighsSimplexPAMIMethod(;warmstart=true, concurrency=0)
        new(warmstart, concurrency) # sets default (8)
    end
end 
struct HighsSimplexSIPMethod <: ProbMethod # parallel simplex method max 8 threads
    warmstart::Bool
    concurrency::Int64
    function HighsSimplexSIPMethod(;warmstart=true, concurrency=0)
        new(warmstart, concurrency) # sets default (8)
    end
end
struct HighsIPMMethod <: ProbMethod 
    warmstart::Bool
    function HighsIPMMethod(;warmstart=true)
        new(warmstart) 
    end
end

struct CPLEXSimplexMethod <: ProbMethod
    warmstart::Bool
    function CPLEXSimplexMethod(;warmstart=true)
        new(warmstart) 
    end
end
struct CPLEXPrimalSimplexMethod <: ProbMethod
    warmstart::Bool
    function CPLEXPrimalSimplexMethod(;warmstart=true)
        new(warmstart) 
    end
end
struct CPLEXNetworkMethod <: ProbMethod
    warmstart::Bool
    function CPLEXNetworkMethod(;warmstart=true)
        new(warmstart) 
    end
end
struct CPLEXIPMMethod <: ProbMethod 
    warmstart::Bool
    concurrency::Int64
    function CPLEXIPMMethod(;warmstart=true, concurrency=0)
        new(warmstart, concurrency) 
    end
end

struct JuMPMethod <: ProbMethod end
struct JuMPHiGHSMethod <: ProbMethod end
struct JuMPClpMethod <: ProbMethod end
struct JuMPClpIPMMethod <: ProbMethod end
struct JuMPTulipMethod <: ProbMethod end
struct JuMPTulipMPCMethod <: ProbMethod end
# struct JuMPTulipMPCCholeskyMethod <: ProbMethod end
# struct JuMPTulipMPCDenseMethod <: ProbMethod end
# struct JuMPTulipMPCLDLMethod <: ProbMethod end
struct JuMPClarabelMethod <: ProbMethod end
struct JuMPCPLEXMethod <: ProbMethod 
    warmstart::Bool
    function JuMPCPLEXMethod(;warmstart=true)
        new(warmstart) 
    end
end

# Buildprob function

# NOTE: Simplex highs never sets the solver to be simplex? 
buildprob(::ProbMethod, modelobjects) = error!("ProbMethod not implemented")
function buildprob(probmethod::HighsSimplexMethod, modelobjects)
    prob = HiGHS_Prob(modelobjects, warmstart=probmethod.warmstart)
    prob.settings.simplex_scale_strategy = 4
    prob.settings.time_limit = 300
    apply_settings!(prob)
    return prob
end
function buildprob(probmethod::HighsPrimalSimplexMethod, modelobjects)
    prob = HiGHS_Prob(modelobjects, warmstart=probmethod.warmstart)
    prob.settings.simplex_scale_strategy = 4
    prob.settings.simplex_strategy = 4
    prob.settings.time_limit = 300
    apply_settings!(prob)
    return prob
end
function buildprob(probmethod::HighsSimplexSIPMethod, modelobjects)
    prob = HiGHS_Prob(modelobjects, warmstart=probmethod.warmstart)
    prob.settings.simplex_scale_strategy = 4
    prob.settings.simplex_strategy = 2
    prob.settings.time_limit = 300
    if probmethod.concurrency > 0
        prob.settings.simplex_max_concurrency = probmethod.concurrency
    end
    apply_settings!(prob)
    return prob
end
function buildprob(probmethod::HighsSimplexPAMIMethod, modelobjects)
    prob = HiGHS_Prob(modelobjects, warmstart=probmethod.warmstart)
    prob.settings.simplex_scale_strategy = 4
    prob.settings.simplex_strategy = 2
    prob.settings.time_limit = 300
    if probmethod.concurrency > 0
        prob.settings.simplex_max_concurrency = probmethod.concurrency
    end
    apply_settings!(prob)
    return prob
end
function buildprob(probmethod::HighsIPMMethod, modelobjects)
    prob = HiGHS_Prob(modelobjects, warmstart=probmethod.warmstart)
    prob.settings.solver = "ipm"
    prob.settings.run_crossover = "off"
    prob.settings.time_limit = 300
    apply_settings!(prob)
    return prob
end

function buildprob(probmethod::CPLEXSimplexMethod, modelobjects)
    prob = CPLEX_Prob(modelobjects)
    setparam!(prob, "CPXPARAM_LPMethod", 2)
    setparam!(prob, "CPXPARAM_TimeLimit", 300)
    !probmethod.warmstart && setparam!(prob, "CPXPARAM_Advance", 0) # or CPXPARAM_ADVIND?
    return prob
end
function buildprob(probmethod::CPLEXPrimalSimplexMethod, modelobjects)
    prob = CPLEX_Prob(modelobjects)
    setparam!(prob, "CPXPARAM_LPMethod", 1)
    setparam!(prob, "CPXPARAM_TimeLimit", 300)
    !probmethod.warmstart && setparam!(prob, "CPXPARAM_Advance", 0) # or CPXPARAM_ADVIND?
    return prob
end
function buildprob(probmethod::CPLEXNetworkMethod, modelobjects)
    prob = CPLEX_Prob(modelobjects)
    setparam!(prob, "CPXPARAM_LPMethod", 3)
    setparam!(prob, "CPXPARAM_TimeLimit", 300)
    !probmethod.warmstart && setparam!(prob, "CPXPARAM_Advance", 0) # or CPXPARAM_ADVIND?
    return prob
end
function buildprob(probmethod::CPLEXIPMMethod, modelobjects)
    prob = CPLEX_Prob(modelobjects)
    setparam!(prob, "CPXPARAM_LPMethod", 4)
    setparam!(prob, "CPXPARAM_SolutionType", 2)
    setparam!(prob, "CPXPARAM_Barrier_StartAlg", 4)
    setparam!(prob, "CPXPARAM_TimeLimit", 300)
    if probmethod.concurrency > 0
        setparam!(prob, "CPXPARAM_Threads", probmethod.concurrency)
    end
    !probmethod.warmstart && setparam!(prob, "CPXPARAM_Advance", 0)
    return prob
end

buildprob(::JuMPHiGHSMethod, modelobjects) = JuMP_Prob(modelobjects, Model(optimizer_with_attributes(HiGHS.Optimizer, "simplex_scale_strategy" => 4)))
buildprob(::JuMPClpMethod, modelobjects) = JuMP_Prob(modelobjects, Model(Clp.Optimizer))
function buildprob(::JuMPClpIPMMethod, modelobjects)
    model = Model(Clp.Optimizer)
    set_attribute(model, "Algorithm", 4) # SolveType => 4
    prob = JuMP_Prob(modelobjects, model)
    return prob
end
buildprob(::JuMPTulipMethod, modelobjects) = JuMP_Prob(modelobjects, Model(Tulip.Optimizer))
buildprob(::JuMPTulipMPCMethod, modelobjects) = JuMP_Prob(modelobjects, Model(optimizer_with_attributes(Tulip.Optimizer, "IPM_Factory" => Tulip.Factory(Tulip.MPC)))) # "Threads" => 2, cholmods LDL factorisation
# buildprob(::JuMPTulipMPCCholeskyMethod, modelobjects) = JuMP_Prob(modelobjects, Model(optimizer_with_attributes(Tulip.Optimizer, "IPM_Factory" => Tulip.Factory(Tulip.MPC), "KKT_Backend" => Tulip.KKT.TlpCholmod.Backend(), "KKT_System" => Tulip.KKT.K1(), "Threads" => 8))) #, cholmods cholesky factorization
# buildprob(::JuMPTulipMPCDenseMethod, modelobjects) = JuMP_Prob(modelobjects, Model(optimizer_with_attributes(Tulip.Optimizer, "IPM_Factory" => Tulip.Factory(Tulip.MPC), "MatrixFactory" => Tulip.Factory(Matrix), "KKT_Backend" => Tulip.KKT.TlpDense.Backend(), "KKT_System" => Tulip.KKT.K1(), "Threads" => 8))) # , Dense
# buildprob(::JuMPTulipMPCLDLMethod, modelobjects) = JuMP_Prob(modelobjects, Model(optimizer_with_attributes(Tulip.Optimizer, "IPM_Factory" => Tulip.Factory(Tulip.MPC), "KKT_Backend" => Tulip.KKT.TlpLDLFact.Backend(), "KKT_System" => Tulip.KKT.K2(), "Threads" => 8))) # , LDL factorization
buildprob(::JuMPClarabelMethod, modelobjects) = JuMP_Prob(modelobjects, Model(Clarabel.Optimizer))
function buildprob(probmethod::JuMPCPLEXMethod, modelobjects)
    model = Model(CPLEX.Optimizer)
    set_attribute(model, "CPXPARAM_LPMethod", 2)
    !probmethod.warmstart && set_attribute(model, "CPXPARAM_Advance", 0)
    prob = JuMP_Prob(modelobjects, model)
    return prob
end