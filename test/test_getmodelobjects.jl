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
    return true
end

function test_getmodelobjects_kwarg_deps_true(elements)
    (modelobjects, deps) = getmodelobjects(elements, deps=true)
    @test typeof(deps) <: Dict{ElementKey, Vector{Int}}
    N = length(elements)
    @test modelobjects isa Dict{Id, Any}
    @test all(1 <= i <= N for e in elements for i in deps[getelkey(e)])
    return true
end

function test_getmodelobjects_kwarg_deps_false(elements)
    modelobjects = getmodelobjects(elements, deps=false)
    @test modelobjects isa Dict{Id, Any}
    return true
end

function test_getmodelobjects_missing_element(elements)
    missing_one = elements[2:end]
    @test_throws ErrorException getmodelobjects(missing_one)
    return true
end

function test_getmodelobjects_duplicates(elements)
    has_duplicates = copy(elements)
    push!(has_duplicates, first(elements))
    @test_throws ErrorException getmodelobjects(has_duplicates)
    return true
end

struct DummyAssembleError
    retval::Bool
end
function includeDummyAssembleError!(toplevel, lowlevel, elkey, value::DummyAssembleError)
    toplevel[Id("testconcept", "MyDummyInstance")] = value
    return (true, Id[])
end
assemble!(obj::DummyAssembleError) = obj.retval
INCLUDEELEMENT[TypeKey("testconcept", "DummyAssembleError")] = includeDummyAssembleError!

function test_getmodelobjects_assemble_error(elements)
    e = DataElement(
        "testconcept", 
        "DummyAssembleError", 
        "MyDummyInstance", 
        DummyAssembleError(true))
    should_be_ok = copy(elements)
    push!(should_be_ok, e)
    modelobjects = getmodelobjects(should_be_ok)

    e = DataElement(
        "testconcept", 
        "DummyAssembleError", 
        "MyDummyInstance", 
        DummyAssembleError(false))
    should_fail = copy(elements)
    push!(should_fail, e)
    @test_throws ErrorException getmodelobjects(should_fail)
    return true
end

# TODO: Test each function in INCLUDEELEMENT

@test test_getmodelobjects_kwarg_validate(elements; validate=true)
@test test_getmodelobjects_kwarg_validate(elements; validate=false)
@test test_getmodelobjects_kwarg_deps_true(elements)
@test test_getmodelobjects_kwarg_deps_false(elements)
@test test_getmodelobjects_missing_element(elements)
@test test_getmodelobjects_duplicates(elements)
@test test_getmodelobjects_assemble_error(elements)