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

# Setup jump model
mymodel = JuMP.Model(HiGHS.Optimizer)
set_silent(mymodel)
prob = JuMP_Prob(modelobjects, mymodel)

t = TwoTime(getisoyearstart(2021), getisoyearstart(1981))
update!(prob, t)
solve!(prob)
prob1_jump = getobjectivevalue(prob)
t = TwoTime(getisoyearstart(2024), getisoyearstart(1982))
update!(prob, t)
solve!(prob)
prob2_jump = getobjectivevalue(prob)

# Setup highs model
prob = HiGHS_Prob(modelobjects)

t = TwoTime(getisoyearstart(2021), getisoyearstart(1981))
update!(prob, t)
solve!(prob)
prob1_highs = getobjectivevalue(prob)
t = TwoTime(getisoyearstart(2024), getisoyearstart(1982))
update!(prob, t)
solve!(prob)
prob2_highs = getobjectivevalue(prob)

@test round(prob1_highs, sigdigits=10) == round(prob1_jump, sigdigits=10)
@test round(prob2_highs, sigdigits=10) == round(prob2_jump, sigdigits=10)
