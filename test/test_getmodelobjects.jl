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
    @test deps isa Dict{ElementKey, Vector{Int}}
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

# TODO: Test each function in INCLUDEELEMENT

function includeVectorTimeIndex!(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    vector = getdictvalue(value, "Vector", AbstractVector{DateTime}, elkey)
    includeVectorTimeIndex!(toplevel, lowlevel, elkey, vector)
end

function test_includeVectorTimeIndex!()
    # tests method when value::AbstractVector{DateTime}
    (tl, ll) = (Dict(), Dict())
    k = ElementKey(TIMEVECTOR_CONCEPT, "VectorTimeIndex", "test")
    # empty vector
    @test_throws ErrorException includeVectorTimeIndex!(tl, ll, k, DateTime[])
    # not sorted
    v = [DateTime(2024, 3, 23), DateTime(1985, 7, 1)]
    @test_throws ErrorException includeVectorTimeIndex!(tl, ll, k, v)
    # should be ok
    v = [DateTime(1985, 7, 1)]
    (ok, deps) = includeVectorTimeIndex!(tl, ll, k, [DateTime(1985, 7, 1)])
    @test ok
    @test deps isa Vector{Id}
    @test length(deps) == 0
    # same id already stored in lowlevel
    ll[k] = 1
    @test_throws ErrorException includeVectorTimeIndex!(tl, ll, k, [DateTime(1985, 7, 1)])

    # tests method when value::Dict
    (tl, ll) = (Dict(), Dict())
    # missing vector in dict
    @test_throws ErrorException includeVectorTimeIndex!(tl, ll, k, Dict())
    # should be ok
    d = Dict()
    d["Vector"] = v
    (ok, deps) = includeVectorTimeIndex!(tl, ll, k, d)
    @test ok
    @test deps isa Vector{Id}
    @test length(deps) == 0
    return true
end

@test test_getmodelobjects_kwarg_validate(elements; validate=true)
@test test_getmodelobjects_kwarg_validate(elements; validate=false)
@test test_getmodelobjects_kwarg_deps_true(elements)
@test test_getmodelobjects_kwarg_deps_false(elements)
@test test_getmodelobjects_missing_element(elements)
@test test_getmodelobjects_duplicates(elements)

@test test_includeVectorTimeIndex!()
