"""
In this file we define a system for testing all methods in the
INCLUDEELEMENT function registry, and to catch missing tests for 
new methods added in the future.

The system has two parts: 
- The function test_all_includeelement_methods, which should
  contain tests for each method for each INCLUDEELEMENT function
  that is defined in TuLiPa.

- The test_is_all_includeelement_methods_covered function, which
  tests that all methods registered as tested in this file
  (using TESTED_INCLUDE_METHODS), actually cover all methods
  stored in the INCLUDEELEMENT registry.

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

We put all functionality for this test into a module so that we do not 
(inadvertently) overwrite names the global namespace, which could affect other 
tests in when running the runtests.jl script.
"""

module Test_INCLUDEELEMENT_Methods

using TuLiPa, Test, Dates

const TESTED_INCLUDE_METHODS = Tuple{Function, Int}[]

function register_tested_methods(include_func::Function, num_methods::Int)
    if !haskey(INCLUDEELEMENT, include_func)
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
        f === includeVectorTimeIndex! || f === includeRangeTimeIndex! || continue    # TODO: Remove later
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

function _test_ret_deps_0(ret)
    @test ret isa Tuple{Bool, Any}
    (ok, deps) = ret
    @test ok
    @test deps isa Vector{Id}
    @test length(deps) == 0
end

function test_all_includeelement_methods()
    test_includeVectorTimeIndex!()
    test_includeRangeTimeIndex!()
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
    _test_ret_deps_0(ret)
    # same id already stored in lowlevel error
    LL[Id(k.conceptname, k.instancename)] = 1
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, [DateTime(1985, 7, 1)])

    # tests method when value::Dict
    (TL, LL) = (Dict(), Dict())
    # missing vector in dict error
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, Dict())
    # should be ok
    d = Dict()
    d["Vector"] = v
    ret = includeVectorTimeIndex!(TL, LL, k, d)
    _test_ret_deps_0(ret)

    register_tested_methods(includeVectorTimeIndex!, 2)
end

function test_includeRangeTimeIndex!()
    # tests method when value::Dict
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
    _test_ret_deps_0(ret)
    # should also be ok
    (TL, LL) = (Dict(), Dict())
    LL[Id(TIMEDELTA_CONCEPT, "MyTimeDelta")] = MsTimeDelta(Hour(1))
    d = Dict("Start" => DateTime(1985, 7, 1), 
             "Steps" => 10,
             "Delta" => "MyTimeDelta") 
    ret = includeRangeTimeIndex!(TL, LL, k, d)
    _test_ret_deps_0(ret)
    # same id already stored in lowlevel error
    LL[Id(k.conceptname, k.instancename)] = 1
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

    # tests whem value::StepRange{DateTime, Millisecond}
    (TL, LL) = (Dict(), Dict())
    # same id already stored in lowlevel
    LL[Id(k.conceptname, k.instancename)] = 1
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, d)
    # negative Millisecond error
    (TL, LL) = (Dict(), Dict())
    t = DateTime(1985, 7, 1)
    d = Millisecond(Hour(-1))
    r = StepRange(t, d, t + Day(1))
    # (just to show that StepRange does not throw, 
    #  but instead evaluates to an empty iterator)
    @test r == StepRange(t, d, t) 
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, r)
    # should be ok
    (TL, LL) = (Dict(), Dict())
    t = DateTime(1985, 7, 1)
    d = Millisecond(Hour(1))
    r = StepRange(t, d, t + Day(1))
    ret = includeRangeTimeIndex!(TL, LL, k, r)
    _test_ret_deps_0(ret)

    register_tested_methods(includeRangeTimeIndex!, 2)
end

run_tests()

end # end module
