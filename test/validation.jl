#using Dates, CSV, DataFrames, Statistics, JuMP, Test, HiGHS, TuLiPa, Random
using TuLiPa, JuMP, HiGHS, Test
include("utils_dummy_data.jl");

elements = gettestdataset();
scenarioyearstart = 1981
scenarioyearstop = 1983
addscenariotimeperiod!(elements, "ScenarioTimePeriod", getisoyearstart(scenarioyearstart), getisoyearstart(scenarioyearstop));

# Removes power to create reference errors

hydro_horizon = SequentialHorizon(52 * 3, Week(1))
set_horizon!(elements, "Hydro", hydro_horizon);
push!(elements, getelement(BOUNDARYCONDITION_CONCEPT, "StartEqualStop", "StartEqualStop_StorageResNO2",
        (WHICHINSTANCE, "StorageResNO2"),
        (WHICHCONCEPT, STORAGE_CONCEPT)));

df = elements_to_df(elements)
checks = validate_refrences(df);
@test checks[1][1] == "Commodity"
@test checks[1][2].instancename == ["PowerBalance_NO2", "PowerBalance_GER"]
@test checks[1][2].Commodity == ["Power", "Power"]