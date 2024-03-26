module TestGetmodelobjects

using TuLiPa, Test

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

function test_getmodelobjects_kwarg_validate(elements; validate=true)
    modelobjects = getmodelobjects(elements, validate=validate)
    @test modelobjects isa Dict{Id, Any}
end

function test_getmodelobjects_kwarg_deps_true(elements)
    (modelobjects, deps) = getmodelobjects(elements, deps=true)
    @test deps isa Dict{ElementKey, Vector{Int}}
    N = length(elements)
    @test modelobjects isa Dict{Id, Any}
    @test all(1 <= i <= N for e in elements for i in deps[getelkey(e)])
end

function test_getmodelobjects_kwarg_deps_false(elements)
    modelobjects = getmodelobjects(elements, deps=false)
    @test modelobjects isa Dict{Id, Any}
end

function test_getmodelobjects_missing_element(elements)
    missing_one = elements[2:end]
    @test_throws ErrorException getmodelobjects(missing_one)
end

function test_getmodelobjects_duplicates(elements)
    has_duplicates = copy(elements)
    push!(has_duplicates, first(elements))
    @test_throws ErrorException getmodelobjects(has_duplicates)
end

@testset "getmodelobjects" begin
    test_getmodelobjects_kwarg_validate(elements; validate=true)
    test_getmodelobjects_kwarg_validate(elements; validate=false)
    test_getmodelobjects_kwarg_deps_true(elements)
    test_getmodelobjects_kwarg_deps_false(elements)
    test_getmodelobjects_missing_element(elements)
    test_getmodelobjects_duplicates(elements)
end

end # module
