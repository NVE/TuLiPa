using Dates, TuLiPa, CSV, DataFrames, Statistics, JuMP, Test, HiGHS
include("../demos/Demo 1a - Deterministic power market with dummy data.jl");

elements = gettestdataset();
scenarioyearstart = 1981
scenarioyearstop = 1983
addscenariotimeperiod!(elements, "ScenarioTimePeriod", getisoyearstart(scenarioyearstart), getisoyearstart(scenarioyearstop));

# We choose the horizon (time-resolution) of the commodities. We set the duration of the horizons to 3 years
# We want the variables connected to power (daily) to be more detailed than the hydro variables (weekly)
power_horizon = SequentialHorizon(364*3, Day(1))
hydro_horizon = SequentialHorizon(52*3, Week(1))
set_horizon!(elements, "Power", power_horizon)
set_horizon!(elements, "Hydro", hydro_horizon);


# Storages have state-dependant variables that need a boundary condition
# We set the starting storage to be equal to the ending storage, x[0] = x[T] (for horizon where t in 1:T)
push!(elements, getelement(BOUNDARYCONDITION_CONCEPT, "StartEqualStop", "StartEqualStop_StorageResNO2",
        (WHICHINSTANCE, "StorageResNO2"),
        (WHICHCONCEPT, STORAGE_CONCEPT)));


modelobjects = getmodelobjects(elements);

mymodel = JuMP.Model(HiGHS.Optimizer)
set_silent(mymodel)
prob = JuMP_Prob(modelobjects, mymodel)
prob.model

t = TwoTime(getisoyearstart(2021), getisoyearstart(1981))
update!(prob, t)

solve!(prob)
prob1 = getobjectivevalue(prob)

t = TwoTime(getisoyearstart(2024), getisoyearstart(1982))
update!(prob, t)
solve!(prob)
prob2 = getobjectivevalue(prob)

prob1 = round(prob1, sigdigits=10)
prob2 = round(prob2, sigdigits=10)

ans1 = round(9.61646303403379e10, sigdigits=10)
ans2 = round(8.194441022906749e10, sigdigits=10)

@test prob1 == ans1
@test prob2 == ans2