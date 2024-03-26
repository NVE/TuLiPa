"""
In this file we define a system for testing all methods in the
INCLUDEELEMENT function registry, and a way to catch missing tests 
for new methods added in the future.

The system has two parts: 
- The function test_all_includeelement_methods, which should
  test all known methods of each INCLUDEELEMENT function 
  that is defined in TuLiPa.

- The test_is_all_includeelement_methods_covered function, which
  tests that all methods registered as tested in this file
  (using the registration scheme described below), actually cover 
  all methods stored in the INCLUDEELEMENT registry.

For the system to work well, each INCLUDEELEMENT test function should behave 
a certain way:
- Define one test function for each generic function in INCLUDEELEMENT.

- The test function should test all methods of the function 
  (i.e. different implementations for different types for the 
   "values" argument. E.g. see test_includeVectorTimeIndex! 
   which tests both value::AbstractVector{DateTime} and value::Dict)

- As a convention, name the test function 
  test_[INCLUDEELEMENT function name]
  (e.g. test_includeVectorTimeIndex!)

- The final line of a test function should call the 
  register_tested_methods function to register how many 
  methods the test function tested.
  (e.g. register_tested_methods(includeVectorTimeIndex!, 2))

- Call the test function inside the 
  test_all_includeelement_methods function 

We wrap the tests in a module so that we do not (inadvertently) 
overwrite names the global namespace, which could affect other 
tests in when running the runtests.jl script.
"""

# TODO: Complete empty tests 

module Test_INCLUDEELEMENT_Methods

using TuLiPa, Test, Dates

const TESTED_INCLUDE_METHODS = Tuple{Function, Int}[]

function register_tested_methods(include_func::Function, num_methods::Int)
    if !(include_func in values(INCLUDEELEMENT))
        error("Unknown INCLUDEELEMENT function $include_func")
    end
    push!(TESTED_INCLUDE_METHODS, (include_func, num_methods))
    return nothing
end

function run_tests()
    test_all_includeelement_methods()
    test_is_all_includeelement_methods_covered()
end

function test_is_all_includeelement_methods_covered()
    ACTUAL_INCLUDE_METHODS = Tuple{Function, Int}[]
    for f in values(INCLUDEELEMENT)
        push!(ACTUAL_INCLUDE_METHODS, (f, length(methods(f))))
    end
    
    tested = Set(TESTED_INCLUDE_METHODS)
    actual = Set(ACTUAL_INCLUDE_METHODS)

    untested = setdiff(actual, tested)

    success = true
    if length(untested) > 0
        success = false
        ns = Dict(f => n for (f, n) in tested)
        for (f, n) in untested
            diff = n - get(ns, f, 0)
            s = diff > 1 ? "s" : ""
            println("Missing test$s for $diff method$s for $f")
        end
    end

    @test success
end

function test_all_includeelement_methods()
    test_includeVectorTimeIndex!()
    test_includeRangeTimeIndex!()
    test_includeVectorTimeValues!()
    test_includeBaseTable!()
    test_includeColumnTimeValues!()
    test_includeRotatingTimeVector!()
    test_includeOneYearTimeVector!()
    test_includeInfiniteTimeVector!()
    test_includeMutableInfiniteTimeVector!()
    test_includeConstantTimeVector!()
    test_includeStartEqualStop!()
    test_includeBaseBalance!()
    test_includeExogenBalance!()
    test_includeBaseFlow!()
    test_includeBaseStorage!()
    test_includeFossilMCParam!()
    test_includeM3SToMM3Param!()
    test_includeM3SToMM3SeriesParam!()
    test_includeMWToGWhSeriesParam!()
    test_includeMWToGWhParam!()
    test_includeCostPerMWToGWhParam!()
    test_includeMeanSeriesParam!()
    test_includeMeanSeriesIgnorePhaseinParam!()
    test_includePrognosisSeriesParam!()
    test_includeUMMSeriesParam!()
    test_includeStatefulParam!()
    test_includeMsTimeDelta!()
    test_includeScenarioTimePeriod!()
    test_includeSimulationTimePeriod!()
    test_includeBaseArrow!()
    test_includeSegmentedArrow!()
    test_includePositiveCapacity!()
    test_includeLowerZeroCapacity!()
    test_includeBaseCommodity!()
    test_includeBaseConversion!()
    test_includePumpConversion!()
    test_includeCostTerm!()
    test_includeSimpleLoss!()
    test_includeStoragehint!()
    test_includeResidualhint!()
    test_includeReservoirCurve!()
    test_includeProductionInfo!()
    test_includeHydraulichint!()
    test_includeGlobalEneq!()
    test_includeBasePrice!()
    test_includeTransmissionRamping!()
    test_includeHydroRampingWithout!()
    test_includeHydroRamping!()
    test_includeBaseRHSTerm!()
    test_includeBaseSoftBound!()
    test_includeSimpleStartUpCost!()
end

function test_includeVectorTimeIndex!()
    # tests method when value::AbstractVector{DateTime}
    (TL, LL) = (Dict(), Dict())
    k = ElementKey("doesnotmatter", "doesnotmatter", "doesnotmatter")
    # empty vector error
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, DateTime[])
    # not sorted error
    v = [DateTime(2024, 3, 23), DateTime(1985, 7, 1)]
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, v)
    # should be ok
    v = [DateTime(1985, 7, 1)]
    ret = includeVectorTimeIndex!(TL, LL, k, [DateTime(1985, 7, 1)])
    _test_ret(ret)
    # same id already stored in lowlevel error
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, [DateTime(1985, 7, 1)])

    # tests method when value::Dict
    (TL, LL) = (Dict(), Dict())
    # missing vector in dict error
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, Dict())
    # should be ok
    d = Dict()
    d["Vector"] = v
    ret = includeVectorTimeIndex!(TL, LL, k, d)
    _test_ret(ret)

    register_tested_methods(includeVectorTimeIndex!, 2)
end

function test_includeRangeTimeIndex!()
    # tests when value::Dict
    (TL, LL) = (Dict(), Dict())
    k = ElementKey("doesnotmatter", "doesnotmatter", "doesnotmatter")
    # empty dict error
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, Dict())
    # wrong type Start error
    d = Dict("Start" => "DateTime(1985, 7, 1)", 
             "Steps" => 10,
             "Delta" => Dates.Hour(1)) 
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, d)
    # wrong type Steps error
    d = Dict("Start" => DateTime(1985, 7, 1), 
             "Steps" => "10",
             "Delta" => Dates.Hour(1)) 
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, d)
    # wrong type Delta error
    d = Dict("Start" => DateTime(1985, 7, 1), 
             "Steps" => 10,
             "Delta" => 10) 
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, d)
    # should be ok
    d = Dict("Start" => DateTime(1985, 7, 1), 
             "Steps" => 10,
             "Delta" => Dates.Hour(1)) 
    ret = includeRangeTimeIndex!(TL, LL, k, d)
    _test_ret(ret)
    # should also be ok
    (TL, LL) = (Dict(), Dict())
    LL[Id(TIMEDELTA_CONCEPT, "MyTimeDelta")] = MsTimeDelta(Hour(1))
    d = Dict("Start" => DateTime(1985, 7, 1), 
             "Steps" => 10,
             "Delta" => "MyTimeDelta") 
    ret = includeRangeTimeIndex!(TL, LL, k, d)
    _test_ret(ret; n=1)
    # same id already stored in lowlevel error
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, d)
    # negative step error 
    d = Dict("Start" => DateTime(1985, 7, 1), 
             "Steps" => -1,
             "Delta" => Dates.Hour(1)) 
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, d)
    # negative Delta error 
    d = Dict("Start" => DateTime(1985, 7, 1), 
             "Steps" => 10,
             "Delta" => Dates.Hour(-1)) 
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, d)

    # tests when value::StepRange{DateTime, Millisecond}
    # same id already stored in lowlevel error
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, d)
    # non-positive Millisecond error
    (TL, LL) = (Dict(), Dict())
    t = DateTime(1985, 7, 1)
    @test_throws ArgumentError StepRange(t, Millisecond(Hour(0)), t)
    d = Millisecond(Hour(-1))
    r = StepRange(t, d, t)
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, r)
    # should be ok
    (TL, LL) = (Dict(), Dict())
    t = DateTime(1985, 7, 1)
    d = Millisecond(Hour(1))
    r = StepRange(t, d, t + Day(1))
    ret = includeRangeTimeIndex!(TL, LL, k, r)
    _test_ret(ret)

    # TODO: add validation t0 > t1 in includeRangeTimeIndex! for value::StepRange and add test for it here

    register_tested_methods(includeRangeTimeIndex!, 2)
end

function test_includeVectorTimeValues!()
  # tests for value::Dict
  (TL, LL) = (Dict(), Dict())
  k = ElementKey("doesnotmatter", "doesnotmatter", "doesnotmatter")
  # missing vector error
  @test_throws ErrorException includeVectorTimeValues!(TL, LL, k, Dict())
  # should be ok
  d = Dict("Vector" => Float64[1, 2, 3])
  ret = includeVectorTimeValues!(TL, LL, k, d)
  _test_ret(ret)
  # same id already stored in lowlevel error
  @test_throws ErrorException includeVectorTimeValues!(TL, LL, k, d)
  # wrong vector eltype error
  (TL, LL) = (Dict(), Dict())
  d = Dict("Vector" => Int[1, 2, 3])
  @test_throws ErrorException includeVectorTimeValues!(TL, LL, k, d)

  register_tested_methods(includeVectorTimeValues!, 1)
end

function test_includeBaseTable!()
  # tests for value::Dict
  (TL, LL) = (Dict(), Dict())
  k = ElementKey("doesnotmatter", "doesnotmatter", "doesnotmatter")
  # missing keys error
  @test_throws ErrorException includeBaseTable!(TL, LL, k, Dict())
  # should be ok
  d = Dict("Matrix" => zeros(Float64, (2,2)), "Names" => ["a", "b"])
  ret = includeBaseTable!(TL, LL, k, d)
  _test_ret(ret)
  # same id already stored in lowlevel error
  @test_throws ErrorException includeVectorTimeValues!(TL, LL, k, d)
  (TL, LL) = (Dict(), Dict())
  # missing name error
  d = Dict("Matrix" => zeros(Float64, (2,2)), "Names" => ["a"])
  @test_throws ErrorException includeBaseTable!(TL, LL, k, d)
  # extra name error
  d = Dict("Matrix" => zeros(Float64, (2,2)), "Names" => ["a", "b", "c"])
  @test_throws ErrorException includeBaseTable!(TL, LL, k, d)
  # wrong matrix eltype error
  d = Dict("Matrix" => zeros(Int, (2,2)), "Names" => ["a", "b"])
  @test_throws ErrorException includeBaseTable!(TL, LL, k, d)
  # wrong names eltype error
  d = Dict("Matrix" => zeros(Float64, (2,2)), "Names" => [:a, :b])
  @test_throws ErrorException includeBaseTable!(TL, LL, k, d)
  # empty names error
  d = Dict("Matrix" => zeros(Float64, (2,2)), "Names" => String[])
  @test_throws ErrorException includeBaseTable!(TL, LL, k, d)
  # duplicate names error
  d = Dict("Matrix" => zeros(Float64, (2,2)), "Names" => ["a", "a"])
  @test_throws ErrorException includeBaseTable!(TL, LL, k, d)

  register_tested_methods(includeBaseTable!, 1)
end

function test_includeColumnTimeValues!()
  # tests for value::Dict
  (TL, LL) = (Dict(), Dict())
  k = ElementKey("doesnotmatter", "doesnotmatter", "doesnotmatter")
  # missing keys error
  @test_throws ErrorException includeColumnTimeValues!(TL, LL, k, Dict())
  # setup test data
  matrix = zeros(Float64, (2,2))
  table = Dict("Matrix" => matrix, "Names" => ["a", "b"])
  table_id = Id(TuLiPa.TABLE_CONCEPT, "mytable")
  # missing table error
  d = Dict(TuLiPa.TABLE_CONCEPT => "mytable", "Name" => "a")
  @test_throws ErrorException includeColumnTimeValues!(TL, LL, k, d)
  # should be ok
  LL[table_id] = table
  ret = includeColumnTimeValues!(TL, LL, k, d)
  _test_ret(ret, n=1)
  # check that stored value is a view into column 1 (name "a") of matrix
  x = LL[Id(k.conceptname, k.instancename)]
  @test view(matrix, :, 1) === x
  # wrong name type error
  d = Dict(TuLiPa.TABLE_CONCEPT => "mytable", "Name" => :a)
  @test_throws ErrorException includeColumnTimeValues!(TL, LL, k, d)
  # unknown name error
  table = Dict("Matrix" => zeros(Float64, (2,2)), "Names" => ["a", "b"])
  d = Dict(TuLiPa.TABLE_CONCEPT => table, "Name" => "c")
  @test_throws ErrorException includeColumnTimeValues!(TL, LL, k, d)

  register_tested_methods(includeColumnTimeValues!, 1)
end

function test_includeRotatingTimeVector!()
  # TODO: test for value::Dict
  register_tested_methods(includeRotatingTimeVector!, 1)
end

function test_includeOneYearTimeVector!()
  # TODO: test for value::Dict
  register_tested_methods(includeOneYearTimeVector!, 1)
end

function test_includeInfiniteTimeVector!()
  # TODO: test for value::Dict
  register_tested_methods(includeInfiniteTimeVector!, 1)
end

function test_includeMutableInfiniteTimeVector!()
  # TODO: test for value::Dict
  register_tested_methods(includeMutableInfiniteTimeVector!, 1)
end

function test_includeConstantTimeVector!()
  # TODO: test for value::Dict
  # TODO: test for value::AbstractFloat
  # TODO: test for value::ConstantTimeVector
  register_tested_methods(includeConstantTimeVector!, 3)
end

function test_includeStartEqualStop!()
  # TODO: test for value::Dict
  register_tested_methods(includeStartEqualStop!, 1)
end

function test_includeBaseBalance!()
  # TODO: test for value::Dict
  register_tested_methods(includeBaseBalance!, 1)
end

function test_includeExogenBalance!()
  # TODO: test for value::Dict
  register_tested_methods(includeExogenBalance!, 1)
end

function test_includeBaseFlow!()
  # TODO: test for value::Dict
  register_tested_methods(includeBaseFlow!, 1)
end

function test_includeBaseStorage!()
  # TODO: test for value::Dict
  register_tested_methods(includeBaseStorage!, 1)
end

function test_includeFossilMCParam!()
  # TODO: test for value::Dict
  register_tested_methods(includeFossilMCParam!, 1)
end

function test_includeM3SToMM3Param!()
  # TODO: test for value::Dict
  register_tested_methods(includeM3SToMM3Param!, 1)
end

function test_includeM3SToMM3SeriesParam!()
  # TODO: test for value::Dict
  # TODO: test for value::M3SToMM3SeriesParam
  # TODO: test for value::AbstractFloat
  register_tested_methods(includeM3SToMM3SeriesParam!, 3)
end

function test_includeMWToGWhSeriesParam!()
  # TODO: test for value::Dict
  # TODO: test for value::MWToGWhSeriesParam
  # TODO: test for value::AbstractFloat
  register_tested_methods(includeMWToGWhSeriesParam!, 3)
end

function test_includeMWToGWhParam!()
  # TODO: test for value::Dict
  register_tested_methods(includeMWToGWhParam!, 1)
end

function test_includeCostPerMWToGWhParam!()
  # TODO: test for value::Dict
  # TODO: test for value::CostPerMWToGWhParam
  # TODO: test for value::AbstractFloat
  register_tested_methods(includeCostPerMWToGWhParam!, 3)
end

function test_includeMeanSeriesParam!()
  # TODO: test for value::Dict
  # TODO: test for value::MeanSeriesParam
  register_tested_methods(includeMeanSeriesParam!, 2)
end

function test_includeMeanSeriesIgnorePhaseinParam!()
  # TODO: test for value::Dict
  # TODO: value::MeanSeriesIgnorePhaseinParam
  register_tested_methods(includeMeanSeriesIgnorePhaseinParam!, 2)
end

function test_includePrognosisSeriesParam!()
  # TODO: test for value::Dict
  register_tested_methods(includePrognosisSeriesParam!, 1)
end

function test_includeUMMSeriesParam!()
  # TODO: test for value::Dict
  register_tested_methods(includeUMMSeriesParam!, 1)
end

function test_includeStatefulParam!()
  # TODO: test for value::Dict
  register_tested_methods(includeStatefulParam!, 1)
end

function test_includeMsTimeDelta!()
  # TODO: test for value::Dict
  register_tested_methods(includeMsTimeDelta!, 1)
end

function test_includeScenarioTimePeriod!()
  # TODO: test for value::Dict
  register_tested_methods(includeScenarioTimePeriod!, 1)
end

function test_includeSimulationTimePeriod!()
  # TODO: test for value::Dict
  register_tested_methods(includeSimulationTimePeriod!, 1)
end

function test_includeBaseArrow!()
  # TODO: test for value::Dict
  register_tested_methods(includeBaseArrow!, 1)
end

function test_includeSegmentedArrow!()
  # TODO: test for value::Dict
  register_tested_methods(includeSegmentedArrow!, 1)
end

function test_includePositiveCapacity!()
  # TODO: test for value::Dict
  register_tested_methods(includePositiveCapacity!, 1)
end

function test_includeLowerZeroCapacity!()
  # TODO: test for value::Dict
  register_tested_methods(includeLowerZeroCapacity!, 1)
end

function test_includeBaseCommodity!()
  # TODO: test for value::Dict
  register_tested_methods(includeBaseCommodity!, 1)
end

function test_includeBaseConversion!()
  # TODO: test for value::Dict
  register_tested_methods(includeBaseConversion!, 1)
end

function test_includePumpConversion!()
  # TODO: test for value::Dict
  register_tested_methods(includePumpConversion!, 1)
end

function test_includeCostTerm!()
  # TODO: test for value::Dict
  register_tested_methods(includeCostTerm!, 1)
end

function test_includeSimpleLoss!()
  # TODO: test for value::Dict
  register_tested_methods(includeSimpleLoss!, 1)
end

function test_includeStoragehint!()
  # TODO: test for value::Dict
  register_tested_methods(includeStoragehint!, 1)
end

function test_includeResidualhint!()
  # TODO: test for value::Dict
  register_tested_methods(includeResidualhint!, 1)
end

function test_includeReservoirCurve!()
  # TODO: test for value::Dict
  register_tested_methods(includeReservoirCurve!, 1)
end

function test_includeProductionInfo!()
  # TODO: test for value::Dict
  register_tested_methods(includeProductionInfo!, 1)
end

function test_includeHydraulichint!()
  # TODO: test for value::Dict
  register_tested_methods(includeHydraulichint!, 1)
end

function test_includeGlobalEneq!()
  # TODO: test for value::Dict
  register_tested_methods(includeGlobalEneq!, 1)
end

function test_includeBasePrice!()
  # TODO: test for value::Dict
  register_tested_methods(includeBasePrice!, 1)
end

function test_includeTransmissionRamping!()
  # TODO: test for value::Dict
  register_tested_methods(includeTransmissionRamping!, 1)
end

function test_includeHydroRampingWithout!()
  # TODO: test for value::Dict
  register_tested_methods(includeHydroRampingWithout!, 1)
end

function test_includeHydroRamping!()
  # TODO: test for value::Dict
  register_tested_methods(includeHydroRamping!, 1)
end

function test_includeBaseRHSTerm!()
  # TODO: test for value::Dict
  register_tested_methods(includeBaseRHSTerm!, 1)
end

function test_includeBaseSoftBound!()
  # TODO: test for value::Dict
  register_tested_methods(includeBaseSoftBound!, 1)
end

function test_includeSimpleStartUpCost!()
  # TODO: test for value::Dict
  register_tested_methods(includeSimpleStartUpCost!, 1)
end

function _test_ret(ret; n=0, okvalue=true, depstype=Vector{Id})
    @test ret isa Tuple{Bool, Any}
    (ok, deps) = ret
    @test ok == okvalue
    @test deps isa depstype
    @test length(deps) == n
end

run_tests()

end # end module
