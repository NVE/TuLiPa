"""
In this file we define a system for testing all methods in the
INCLUDEELEMENT function registry, and a way to catch missing tests 
for new methods added in the future.

The system has two parts: 
    The function test_all_includeelement_methods, which should
    test all known methods of each INCLUDEELEMENT function 
    that is defined in TuLiPa.
    
    The test_is_all_includeelement_methods_covered function, which
    tests that all methods registered as tested in this file
    (using the registration scheme described below), actually cover 
    all methods stored in the INCLUDEELEMENT registry.

For the system to work well, each INCLUDEELEMENT test function should behave 
a certain way:
    Define one test function for each generic function in INCLUDEELEMENT.
      
    The test function should test all methods of the function 
    (i.e. different implementations for different types for the 
    "value" argument. E.g. see test_includeVectorTimeIndex! 
    which tests both value::AbstractVector{DateTime} and value::Dict)

    As a convention, name the test function 
    test_[INCLUDEELEMENT function name]
    (e.g. test_includeVectorTimeIndex!)

    The final line of a test function should call the 
    register_tested_methods function to register how many 
    methods the test function tested.
    (e.g. register_tested_methods(includeVectorTimeIndex!, 2))

    Call the test function inside the 
    test_all_includeelement_methods function 

We wrap the tests in a module so that we do not inadvertently 
overwrite names the global namespace, which could affect other 
tests when running runtests.jl
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
	test_includeBaseElasticDemand!()
	test_includeVectorPrice!()
end

function _setup_common_variables() 
    return (ElementKey("", "", ""), Dict(), Dict())
end

function test_includeVectorTimeIndex!()
    # tests method when value::AbstractVector{DateTime}
    (k, TL, LL) = _setup_common_variables()
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, DateTime[])
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, [DateTime(2024, 3, 23), DateTime(1985, 7, 1)]) # not sorted error
    v = [DateTime(1985, 7, 1)]
    ret = includeVectorTimeIndex!(TL, LL, k, v)
    _test_ret(ret)
    @test LL[Id(k.conceptname, k.instancename)] === v
    @test length(TL) == 0 && length(LL) == 1
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, [DateTime(1985, 7, 1)]) # same id already stored in lowlevel error
    # tests method when value::Dict
    (TL, LL) = (Dict(), Dict())
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, Dict()) # missing vector in dict error
    ret = includeVectorTimeIndex!(TL, LL, k, Dict("Vector" => v))
    _test_ret(ret)
    @test LL[Id(k.conceptname, k.instancename)] === v
    @test length(TL) == 0 && length(LL) == 1
    register_tested_methods(includeVectorTimeIndex!, 2)
end

function test_includeRangeTimeIndex!()
    # tests when value::Dict
    (k, TL, LL) = _setup_common_variables()
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, Dict())
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, Dict("Start" => "DateTime(1985, 7, 1)", "Steps" => 10,"Delta" => Dates.Hour(1))) # wrong type Start error
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, Dict("Start" => DateTime(1985, 7, 1), "Steps" => "10","Delta" => Dates.Hour(1))) # wrong type Steps error
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, Dict("Start" => DateTime(1985, 7, 1), "Steps" => 10,"Delta" => 10)) # wrong type Delta error
    d = Dict("Start" => DateTime(1985, 7, 1), "Steps" => 10, "Delta" => Dates.Hour(1)) 
    ret = includeRangeTimeIndex!(TL, LL, k, d)
    _test_ret(ret)
    (TL, LL) = (Dict(), Dict())
    LL[Id(TIMEDELTA_CONCEPT, "MyTimeDelta")] = MsTimeDelta(Hour(1))
    d = Dict("Start" => DateTime(1985, 7, 1), "Steps" => 10, "Delta" => "MyTimeDelta") 
    ret = includeRangeTimeIndex!(TL, LL, k, d)
    _test_ret(ret; n=1)
    @test LL[Id(k.conceptname, k.instancename)] isa StepRange
    @test length(TL) == 0 && length(LL) == 2    
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, d) # same id already stored in lowlevel error
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, Dict("Start" => DateTime(1985, 7, 1), "Steps" => -1, "Delta" => Dates.Hour(1))) # negative step error
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, Dict("Start" => DateTime(1985, 7, 1), "Steps" => 10, "Delta" => Dates.Hour(-1)))  # negative Delta error
    # tests when value::StepRange{DateTime, Millisecond}
    (TL, LL) = (Dict(), Dict())
    @test_throws ArgumentError StepRange(DateTime(1985, 7, 1), Millisecond(Hour(0)), DateTime(1985, 7, 1))
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, StepRange(DateTime(1985, 7, 1), Millisecond(Hour(-1)), DateTime(1985, 7, 1))) # negative Millisecond error
    (TL, LL) = (Dict(), Dict())
    r = StepRange(DateTime(1985, 7, 1), Millisecond(Hour(1)), DateTime(1985, 7, 1) + Day(1))
    ret = includeRangeTimeIndex!(TL, LL, k, r)
    _test_ret(ret)
    @test LL[Id(k.conceptname, k.instancename)] === r
    @test length(TL) == 0 && length(LL) == 1
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, r) # same id already stored in lowlevel error
    # TODO: add validation t0 > t1 in includeRangeTimeIndex! for value::StepRange and add test for it here
    register_tested_methods(includeRangeTimeIndex!, 2)
end

function test_includeVectorTimeValues!()
    # tests for value::Dict
    (k, TL, LL) = _setup_common_variables()
    @test_throws ErrorException includeVectorTimeValues!(TL, LL, k, Dict())
    d = Dict("Vector" => Float64[1, 2, 3])
    ret = includeVectorTimeValues!(TL, LL, k, d)
    _test_ret(ret)
    @test LL[Id(k.conceptname, k.instancename)] === d["Vector"]
    @test length(TL) == 0 && length(LL) == 1
    @test_throws ErrorException includeVectorTimeValues!(TL, LL, k, d) # same id already stored in lowlevel error
    (TL, LL) = (Dict(), Dict())
    @test_throws ErrorException includeVectorTimeValues!(TL, LL, k, Dict("Vector" => Int[1, 2, 3])) # wrong vector eltype error
    register_tested_methods(includeVectorTimeValues!, 1)
end

function test_includeBaseTable!()
    # tests for value::Dict
    (k, TL, LL) = _setup_common_variables()
    @test_throws ErrorException includeBaseTable!(TL, LL, k, Dict())
    d = Dict("Matrix" => zeros(Float64, (2,2)), "Names" => ["a", "b"])
    ret = includeBaseTable!(TL, LL, k, d)
    _test_ret(ret)
    @test LL[Id(k.conceptname, k.instancename)] === d
    @test length(TL) == 0 && length(LL) == 1
    @test_throws ErrorException includeBaseTable!(TL, LL, k, d)  # same id already stored in lowlevel error
    (TL, LL) = (Dict(), Dict())
    @test_throws ErrorException includeBaseTable!(TL, LL, k, Dict("Matrix" => zeros(Float64, (2,2)), "Names" => ["a"]))  # missing name error
    @test_throws ErrorException includeBaseTable!(TL, LL, k, Dict("Matrix" => zeros(Float64, (2,2)), "Names" => ["a", "b", "c"])) # extra name error
    @test_throws ErrorException includeBaseTable!(TL, LL, k, Dict("Matrix" => zeros(Int, (2,2)), "Names" => ["a", "b"]))  # wrong matrix eltype error
    @test_throws ErrorException includeBaseTable!(TL, LL, k, Dict("Matrix" => zeros(Float64, (2,2)), "Names" => [:a, :b])) # wrong names eltype error
    @test_throws ErrorException includeBaseTable!(TL, LL, k, Dict("Matrix" => zeros(Float64, (2,2)), "Names" => String[]))  # empty names error
    @test_throws ErrorException includeBaseTable!(TL, LL, k, Dict("Matrix" => zeros(Float64, (2,2)), "Names" => ["a", "a"]))  # duplicate names error
    register_tested_methods(includeBaseTable!, 1)
end

function test_includeColumnTimeValues!()
    # tests for value::Dict
    (k, TL, LL) = _setup_common_variables()
    @test_throws ErrorException includeColumnTimeValues!(TL, LL, k, Dict())
    matrix = zeros(Float64, (2,2))
    table = Dict("Matrix" => matrix, "Names" => ["a", "b"])
    table_id = Id(TABLE_CONCEPT, "mytable")
    d = Dict(TABLE_CONCEPT => "mytable", "Name" => "a")
    ret = includeColumnTimeValues!(TL, LL, k, d)
    _test_ret(ret, n=1, okvalue=false)  # missing table returns ok=false
    @test ret[2][1] == table_id
    LL[table_id] = table
    ret = includeColumnTimeValues!(TL, LL, k, d)
    _test_ret(ret, n=1)
    @test ret[2][1] == table_id
    @test length(TL) == 0 && length(LL) == 2
    @test view(matrix, :, 1) === LL[Id(k.conceptname, k.instancename)]
    @test_throws ErrorException includeColumnTimeValues!(TL, LL, k, d) # same id already stored in lowlevel error
    d = Dict(TABLE_CONCEPT => "mytable", "Name" => :a) 
    @test_throws ErrorException includeColumnTimeValues!(TL, LL, k, d) # wrong name type error
    table = Dict("Matrix" => zeros(Float64, (2,2)), "Names" => ["a", "b"])
    d = Dict(TABLE_CONCEPT => table, "Name" => "c")
    @test_throws ErrorException includeColumnTimeValues!(TL, LL, k, d) # unknown name error
    register_tested_methods(includeColumnTimeValues!, 1)
end

function test_includeRotatingTimeVector!()
    # tests for value::Dict
    (k, TL, LL) = _setup_common_variables()
    @test_throws ErrorException includeRotatingTimeVector!(TL, LL, k, Dict())
    index = [DateTime(1985, 7, 1)]
    vals = [10.0]
    period = Dict("Start" => getisoyearstart(1985), "Stop" => getisoyearstart(1986))
    index_id = Id(TIMEINDEX_CONCEPT, "myindex")
    vals_id = Id(TIMEVALUES_CONCEPT, "myvals")
    period_id = Id(TIMEPERIOD_CONCEPT, "ScenarioTimePeriod")
    LL[index_id] = index
    LL[vals_id] = vals
    LL[period_id] = period
    d = Dict(TIMEINDEX_CONCEPT => index_id.instancename, TIMEVALUES_CONCEPT => vals_id.instancename, TIMEPERIOD_CONCEPT => period_id.instancename)
    ret = includeRotatingTimeVector!(TL, LL, k, d)
    _test_ret(ret, n=3)
    @test Set(ret[2]) == Set([index_id, vals_id, period_id])
    @test length(TL) == 0 && length(LL) == 4
    @test LL[Id(k.conceptname, k.instancename)] isa RotatingTimeVector
    @test_throws ErrorException includeRotatingTimeVector!(TL, LL, k, d) # same id already stored in lowlevel error
    (TL, LL) = (Dict(), Dict())
    LL[vals_id] = vals
    LL[period_id] = period
    ret = includeRotatingTimeVector!(TL, LL, k, d)
    _test_ret(ret, n=3, okvalue=false)  # ret with ok=false due to missing index
    @test Set(ret[2]) == Set([index_id, vals_id, period_id])
    (TL, LL) = (Dict(), Dict())
    LL[index_id] = index
    LL[period_id] = period
    ret = includeRotatingTimeVector!(TL, LL, k, d)
    _test_ret(ret, n=3, okvalue=false)   # ret with ok=false due to missing vals
    @test Set(ret[2]) == Set([index_id, vals_id, period_id])
    (TL, LL) = (Dict(), Dict())
    LL[index_id] = index
    LL[vals_id] = vals
    ret = includeRotatingTimeVector!(TL, LL, k, d)
    _test_ret(ret, n=3, okvalue=false)   # ret with ok=false due to missing period
    @test Set(ret[2]) == Set([index_id, vals_id, period_id])
    (TL, LL) = (Dict(), Dict())
    LL[vals_id] = vals
    LL[period_id] = period
    LL[index_id] = [DateTime(1985, 7, 1), DateTime(1985, 7, 2)]
    @test_throws ErrorException includeRotatingTimeVector!(TL, LL, k, d)  # different length index and vals error
    register_tested_methods(includeRotatingTimeVector!, 1)
end

function _common_timevector(func::Function, T::Type)
    (k, TL, LL) = _setup_common_variables()
    @test_throws ErrorException func(TL, LL, k, Dict())
    index = [DateTime(1985, 7, 1)]
    vals = [10.0]
    index_id = Id(TuLiPa.TIMEINDEX_CONCEPT, "myindex")
    vals_id = Id(TuLiPa.TIMEVALUES_CONCEPT, "myvals")
    LL[index_id] = index
    LL[vals_id] = vals
    d = Dict(TIMEINDEX_CONCEPT => index_id.instancename, TIMEVALUES_CONCEPT => vals_id.instancename)
    ret = func(TL, LL, k, d)
    _test_ret(ret, n=2)
    @test Set(ret[2]) == Set([index_id, vals_id])
    @test length(TL) == 0 && length(LL) == 3
    @test LL[Id(k.conceptname, k.instancename)] isa T
    @test_throws ErrorException func(TL, LL, k, d) # same id already stored in lowlevel error
    (TL, LL) = (Dict(), Dict())
    LL[vals_id] = vals
    ret = func(TL, LL, k, d)
    _test_ret(ret, n=2, okvalue=false)  # ret with ok=false due to missing index
    @test Set(ret[2]) == Set([index_id, vals_id])
    (TL, LL) = (Dict(), Dict())
    LL[index_id] = index
    ret = func(TL, LL, k, d)
    _test_ret(ret, n=2, okvalue=false)  # ret with ok=false due to missing vals
    @test Set(ret[2]) == Set([index_id, vals_id])
    (TL, LL) = (Dict(), Dict())
    LL[index_id] = [DateTime(1985, 7, 1), DateTime(1985, 7, 2)]
    LL[vals_id] = vals
    @test_throws ErrorException func(TL, LL, k, d) # different length index and vals error
    return (k, d, index_id, index, vals_id, vals)
end

function test_includeOneYearTimeVector!()
    # tests for value::Dict
    r = _common_timevector(includeOneYearTimeVector!, RotatingTimeVector)
    (k, d, index_id, index, vals_id, vals) = r
    (TL, LL) = (Dict(), Dict())
    LL[index_id] = index
    LL[vals_id] = vals
    LL[index_id] = [DateTime(1985, 7, 1), DateTime(1985, 7, 2)]
    @test_throws ErrorException includeOneYearTimeVector!(TL, LL, k, d) # different length index and vals error
    LL[index_id] = [DateTime(1985, 7, 1), DateTime(1988, 7, 2)]
    LL[vals_id] = [10.0, 11.0]
    @test_throws ErrorException includeOneYearTimeVector!(TL, LL, k, d) # not one isoyear
    register_tested_methods(includeOneYearTimeVector!, 1)
end

function test_includeInfiniteTimeVector!()
    # tests for value::Dict
    _common_timevector(includeInfiniteTimeVector!, InfiniteTimeVector)
    register_tested_methods(includeInfiniteTimeVector!, 1)
end

function test_includeMutableInfiniteTimeVector!()
    # tests for value::Dict
    _common_timevector(includeMutableInfiniteTimeVector!, MutableInfiniteTimeVector)
    register_tested_methods(includeMutableInfiniteTimeVector!, 1)
end

function _common_constant_timevector(TL, LL, k, ret)
    _test_ret(ret)
    @test length(TL) == 0 && length(LL) == 1
    @test LL[Id(k.conceptname, k.instancename)] isa ConstantTimeVector
    @test_throws ErrorException includeConstantTimeVector!(TL, LL, k, Dict("Value" => 1.0))
end

function test_includeConstantTimeVector!()
    # tests for value::Dict
    (k, TL, LL) = _setup_common_variables()
    @test_throws ErrorException includeConstantTimeVector!(TL, LL, k, Dict())
    @test_throws ErrorException includeConstantTimeVector!(TL, LL, k, Dict("Value" => 10))
    ret = includeConstantTimeVector!(TL, LL, k, Dict("Value" => 10.0))
    _common_constant_timevector(TL, LL, k, ret)
    # tests for value::AbstractFloat
    (k, TL, LL) = _setup_common_variables()
    ret = includeConstantTimeVector!(TL, LL, k, 10.0)
    _common_constant_timevector(TL, LL, k, ret)
    # tests for value::ConstantTimeVector
    (k, TL, LL) = _setup_common_variables()
    ret = includeConstantTimeVector!(TL, LL, k, ConstantTimeVector(10.0))
    _common_constant_timevector(TL, LL, k, ret)
    register_tested_methods(includeConstantTimeVector!, 3)
end

function test_includeStartEqualStop!()
    # tests for value::Dict
    (k, TL, LL) = _setup_common_variables()
    @test_throws ErrorException includeStartEqualStop!(TL, LL, k, Dict())
    ret = includeStartEqualStop!(TL, LL, k, Dict(WHICHINSTANCE => "myvar", WHICHCONCEPT => FLOW_CONCEPT))
    _test_ret(ret, n=1, okvalue=false)  # no var in TL
    @test ret[2] == [Id(FLOW_CONCEPT, "myvar")]
    TL[Id(FLOW_CONCEPT, "myvar")] = BaseFlow(Id(FLOW_CONCEPT, "myvar"))
    ret = includeStartEqualStop!(TL, LL, k, Dict(WHICHINSTANCE => "myvar", WHICHCONCEPT => FLOW_CONCEPT))
    _test_ret(ret, n=1)
    @test length(TL) == 2 && length(LL) == 0
    @test TL[Id(k.conceptname, k.instancename)] isa StartEqualStop
    register_tested_methods(includeStartEqualStop!, 1)
end

function test_includeBaseBalance!()
    # tests for value::Dict
    (k, TL, LL) = _setup_common_variables()
    @test_throws ErrorException includeBaseBalance!(TL, LL, k, Dict())
    ret = includeBaseBalance!(TL, LL, k, Dict(COMMODITY_CONCEPT => "Power")) # not in LL
    _test_ret(ret, n=1, okvalue=false)
    @test ret[2] == [Id(COMMODITY_CONCEPT, "Power")]
    LL[Id(COMMODITY_CONCEPT, "Power")] = BaseCommodity(Id(COMMODITY_CONCEPT, "Power"), SequentialHorizon(10, Day(1)))
    ret = includeBaseBalance!(TL, LL, k, Dict(COMMODITY_CONCEPT => "Power"))
    _test_ret(ret, n=1)
    @test ret[2] == [Id(COMMODITY_CONCEPT, "Power")]
    @test length(TL) == 1 && length(LL) == 1
    @test TL[Id(k.conceptname, k.instancename)] isa BaseBalance
    register_tested_methods(includeBaseBalance!, 1)
end

function test_includeExogenBalance!()
    # tests for value::Dict
    (k, TL, LL) = _setup_common_variables()
    @test_throws ErrorException includeExogenBalance!(TL, LL, k, Dict())
    ret = includeExogenBalance!(TL, LL, k, Dict(COMMODITY_CONCEPT => "Power", PRICE_CONCEPT => "Price")) # commodity and price not in LL
    _test_ret(ret, n=3, okvalue=false)
    @test Set(ret[2]) == Set([Id(COMMODITY_CONCEPT, "Power"), Id(PRICE_CONCEPT, "Price"), Id(PARAM_CONCEPT, "Price")]) # Price could be either PARAM or PRICE when ok=false
    LL[Id(COMMODITY_CONCEPT, "Power")] = BaseCommodity(Id(COMMODITY_CONCEPT, "Power"), SequentialHorizon(10, Day(1)))
    ret = includeExogenBalance!(TL, LL, k, Dict(COMMODITY_CONCEPT => "Power", PRICE_CONCEPT => "Price")) # price not in LL
    _test_ret(ret, n=3, okvalue=false)
    @test Set(ret[2]) == Set([Id(COMMODITY_CONCEPT, "Power"), Id(PRICE_CONCEPT, "Price"), Id(PARAM_CONCEPT, "Price")]) # Price could be either PARAM or PRICE when ok=false
    LL[Id(PRICE_CONCEPT, "Price")] = BasePrice(ConstantParam(10.0))
    ret = includeExogenBalance!(TL, LL, k, Dict(COMMODITY_CONCEPT => "Power", PRICE_CONCEPT => "Price"))
    _test_ret(ret, n=2)
    @test Set(ret[2]) == Set([Id(COMMODITY_CONCEPT, "Power"), Id(PRICE_CONCEPT, "Price")])
    @test length(TL) == 1 && length(LL) == 2
    @test TL[Id(k.conceptname, k.instancename)] isa ExogenBalance
    (k, TL, LL) = _setup_common_variables()
    LL[Id(COMMODITY_CONCEPT, "Power")] = BaseCommodity(Id(COMMODITY_CONCEPT, "Power"), SequentialHorizon(10, Day(1)))
    ret = includeExogenBalance!(TL, LL, k, Dict(COMMODITY_CONCEPT => "Power", PRICE_CONCEPT => 10.0))
    _test_ret(ret, n=1)
    @test ret[2] == [Id(COMMODITY_CONCEPT, "Power")]
    @test length(TL) == 1 && length(LL) == 1
    @test TL[Id(k.conceptname, k.instancename)] isa ExogenBalance
    TL = Dict()
    ret = includeExogenBalance!(TL, LL, k, Dict(COMMODITY_CONCEPT => "Power", PRICE_CONCEPT => ConstantParam(10.0)))
    _test_ret(ret, n=1)
    @test ret[2] == [Id(COMMODITY_CONCEPT, "Power")]
    @test length(TL) == 1 && length(LL) == 1
    @test TL[Id(k.conceptname, k.instancename)] isa ExogenBalance
    TL = Dict()
    ret = includeExogenBalance!(TL, LL, k, Dict(COMMODITY_CONCEPT => "Power", PRICE_CONCEPT => BasePrice(ConstantParam(10.0))))
    _test_ret(ret, n=1)
    @test ret[2] == [Id(COMMODITY_CONCEPT, "Power")]
    @test length(TL) == 1 && length(LL) == 1
    @test TL[Id(k.conceptname, k.instancename)] isa ExogenBalance
    LL[Id(PARAM_CONCEPT, "Price")] = ConstantParam(10.0)
    @test_throws ErrorException includeExogenBalance!(TL, LL, k, Dict(COMMODITY_CONCEPT => "Power", PRICE_CONCEPT => "Price")) # id already exists in TL
    TL = Dict()
    ret = includeExogenBalance!(TL, LL, k, Dict(COMMODITY_CONCEPT => "Power", PRICE_CONCEPT => "Price"))
    _test_ret(ret, n=2)
    @test Set(ret[2]) == Set([Id(COMMODITY_CONCEPT, "Power"), Id(PARAM_CONCEPT, "Price")])
    @test length(TL) == 1 && length(LL) == 2
    @test TL[Id(k.conceptname, k.instancename)] isa ExogenBalance
    register_tested_methods(includeExogenBalance!, 1)
end

function test_includeBaseFlow!()
    # tests for value::Dict
    (k, TL, LL) = _setup_common_variables()
    ret = includeBaseFlow!(TL, LL, k, Dict())
    _test_ret(ret)
    @test length(TL) == 1 && length(LL) == 0
    @test TL[Id(k.conceptname, k.instancename)] isa BaseFlow
    @test_throws ErrorException includeBaseFlow!(TL, LL, k, Dict()) # already exists in TL
    register_tested_methods(includeBaseFlow!, 1)
end

function test_includeBaseStorage!()
    # tests for value::Dict
    (k, TL, LL) = _setup_common_variables()
    @test_throws ErrorException includeBaseStorage!(TL, LL, k, Dict())
    ret = includeBaseStorage!(TL, LL, k, Dict(BALANCE_CONCEPT => "HydroBalance"))
    _test_ret(ret, n=1, okvalue=false)
    TL[Id(BALANCE_CONCEPT, "HydroBalance")] = BaseBalance(Id(BALANCE_CONCEPT, "HydroBalance"), BaseCommodity(Id(COMMODITY_CONCEPT, "Hydro"), SequentialHorizon(10, Day(1))))
    ret = includeBaseStorage!(TL, LL, k, Dict(BALANCE_CONCEPT => "HydroBalance"))
    _test_ret(ret, n=1)
    @test length(TL) == 2 && length(LL) == 0
    @test ret[2] == [Id(BALANCE_CONCEPT, "HydroBalance")]
    @test TL[Id(k.conceptname, k.instancename)] isa BaseStorage
    @test_throws ErrorException includeBaseStorage!(TL, LL, k, Dict(BALANCE_CONCEPT => "HydroBalance")) # already exists in TL
    register_tested_methods(includeBaseStorage!, 1)
end

function test_includeFossilMCParam!()
    # tests for value::Dict
    (k, TL, LL) = _setup_common_variables()
    @test_throws ErrorException includeFossilMCParam!(TL, LL, k, Dict())
    tvnames = ["FuelLevel", "FuelProfile", "CO2Factor", "CO2Level", "CO2Profile", "Efficiency", "VOC"]
    for name in tvnames
        (k, TL, LL) = _setup_common_variables()
        id_list = [s for s in tvnames if s != name]
        d = Dict{String, Any}(s => s for s in id_list)
        d[name] = ConstantTimeVector(1.0)
        expected_deps = Set([Id(TIMEVECTOR_CONCEPT, s) for s in id_list])
        for s in id_list
            ret = includeFossilMCParam!(TL, LL, k, d)
            _test_ret(ret, n=6, okvalue=false)
            LL[Id(TIMEVECTOR_CONCEPT, s)] = ConstantTimeVector(1.0)
            @test expected_deps == Set(ret[2])
        end
        ret = includeFossilMCParam!(TL, LL, k, d)
        _test_ret(ret, n=6)
        @test expected_deps == Set(ret[2])
        @test length(TL) == 0 && length(LL) == 7
        @test LL[Id(k.conceptname, k.instancename)] isa FossilMCParam
        @test_throws ErrorException includeBaseStorage!(TL, LL, k, d) # already exists in LL
    end
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

function test_includeVectorPrice!()
    # TODO: test for value::Dict
    register_tested_methods(includeVectorPrice!, 1)
end

function test_includeBaseElasticDemand!()
    # tests for value::Dict
    (k, TL, LL) = _setup_common_variables()
	
	d = Dict("Balance" => "PowerBalance_NO2", 
			 "Param" => "FirmDemand",
             "price_elasticity" => 1.0, 
			 "normal_price" => 1.0 , 
			 "max_price" => 2.0, 
			 "min_price" => 1.0
			)
	
	bal = BaseBalance(
			Id("a", "a"),
			BaseCommodity(
				Id("a", "a"), SequentialHorizon(1, Day(1))
			)
		  )
	par = MeanSeriesParam(ConstantTimeVector(1), ConstantTimeVector(1))
	TL[Id("Balance", "PowerBalance_NO2")] = bal
	LL[Id("Param", "FirmDemand")] = par
	
    ret = includeBaseElasticDemand!(TL, LL, k, d)
	_test_ret(ret, n=2, okvalue=true)
    @test TL[Id(k.conceptname, k.instancename)] isa ElasticPowerDemand
    register_tested_methods(includeBaseElasticDemand!, 1)
end

function _test_ret(ret; n=0, okvalue=true, depstype=Vector{Id})
    @test ret isa Tuple{Bool, Any}
    (ok, deps) = ret
    @test ok == okvalue
    @test deps isa depstype
    @test length(deps) == n
end

testset_name = Main.get_testset_name("includeelement_methods")
@testset "$testset_name" begin
    run_tests()
end

end # end module
