using TuLiPa, CSV, DataFrames, Statistics, JuMP, Test, HiGHS, Dates
include("utils_dummy_data.jl");


elements = gettestdataset();
scenarioyearstart = 1981
scenarioyearstop = 1983
addscenariotimeperiod!(elements, "ScenarioTimePeriod", getisoyearstart(scenarioyearstart), getisoyearstart(scenarioyearstop));
power_horizon = SequentialHorizon(364 * 3, Day(1))
hydro_horizon = SequentialHorizon(52 * 3, Week(1))
set_horizon!(elements, "Power", power_horizon)
set_horizon!(elements, "Hydro", hydro_horizon);
push!(elements, getelement(BOUNDARYCONDITION_CONCEPT, "StartEqualStop", "StartEqualStop_StorageResNO2",
	(WHICHINSTANCE, "StorageResNO2"),
	(WHICHCONCEPT, STORAGE_CONCEPT)));
modelobjects = getmodelobjects(elements);

prob = buildprob(HighsSimplexMethod(), modelobjects)
TuLiPa._passLP_reset!(prob)

value = Ref{Int32}(0)
status = Highs_getIntOptionValue(prob, "simplex_scale_strategy", value)
@test value[] == 5

value = Ref{Int32}(0)
status = Highs_getIntOptionValue(prob, "simplex_strategy", value)
@test value[] == 1

value = Ref{Float64}(0)
status = Highs_getDoubleOptionValue(prob, "time_limit", value)
@test value[] == 300

value = Ref{Int32}(0)
status = Highs_getIntOptionValue(prob, "simplex_max_concurrency", value)
@test value[] == 8

# NOTE: Simplex highs never sets the solver to be simplex? 
buffer = Vector{UInt8}(undef, 100)
status = Highs_getStringOptionValue(prob, "solver", buffer)
@test unsafe_string(pointer(buffer)) == "choose"

buffer = Vector{UInt8}(undef, 100)
status = Highs_getStringOptionValue(prob, "run_crossover", buffer);
@test unsafe_string(pointer(buffer)) == "on"

prob = buildprob(HighsIPMMethod(), modelobjects)
TuLiPa._passLP_reset!(prob)

value = Ref{Int32}(0)
status = Highs_getIntOptionValue(prob, "simplex_scale_strategy", value)
@test value[] == 1

buffer = Vector{UInt8}(undef, 100)
status = Highs_getStringOptionValue(prob, "solver", buffer)
@test unsafe_string(pointer(buffer)) == "ipm"

buffer = Vector{UInt8}(undef, 100)
status = Highs_getStringOptionValue(prob, "run_crossover", buffer);
@test unsafe_string(pointer(buffer)) == "off"
