"""
We implement some concrete ProbMethod (see abstracttypes.jl)
"""

# Problem method objects
struct HighsSimplexMethod <: ProbMethod end
struct HighsSimplexPAMIMethod <: ProbMethod # parallel simplex method max 8 threads
    concurrency::Int64
    function HighsSimplexPAMIMethod()
        new(0) # sets default 8
    end
end 
struct HighsSimplexSIPMethod <: ProbMethod # parallel simplex method max 8 threads
    concurrency::Int64
    function HighsSimplexSIPMethod()
        new(0) # sets default 8
    end
end
struct HighsIPMMethod <: ProbMethod end
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

# Buildprob function
buildprob(::ProbMethod, modelobjects) = error!("ProbMethod not implemented")
function buildprob(::HighsSimplexMethod, modelobjects)
    prob = HiGHS_Prob(modelobjects)
    Highs_setIntOptionValue(prob, "simplex_scale_strategy", 5)
    return prob
end
function buildprob(probmethod::HighsSimplexPAMIMethod, modelobjects)
    prob = HiGHS_Prob(modelobjects)
    Highs_setIntOptionValue(prob, "simplex_strategy", 2) # parallel simplex
    Highs_setIntOptionValue(prob, "simplex_scale_strategy", 5)
    if probmethod.concurrency > 0
        Highs_setIntOptionValue(prob, "simplex_max_concurrency", probmethod.concurrency)
    end
    return prob
end
function buildprob(probmethod::HighsSimplexSIPMethod, modelobjects)
    prob = HiGHS_Prob(modelobjects)
    Highs_setIntOptionValue(prob, "simplex_strategy", 3) # parallel simplex
    Highs_setIntOptionValue(prob, "simplex_scale_strategy", 5)
    if probmethod.concurrency > 0
        Highs_setIntOptionValue(prob, "simplex_max_concurrency", probmethod.concurrency)
    end
    return prob
end
function buildprob(::HighsIPMMethod, modelobjects)
    prob = HiGHS_Prob(modelobjects)
    Highs_setStringOptionValue(prob, "solver", "ipm") # interior point method
    return prob
end
buildprob(::JuMPHiGHSMethod, modelobjects) = JuMP_Prob(modelobjects, Model(optimizer_with_attributes(HiGHS.Optimizer, "simplex_scale_strategy" => 5)))
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