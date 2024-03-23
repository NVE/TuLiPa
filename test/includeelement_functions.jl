"""
Add test function with name test_[INCLUDEELEMENT function name]
(e.g. test_includeVectorTimeIndex!) for each function in the
INCLUDEELEMENT function registry.

A test function should test both expected error and success,
and should cover all known methods of the function.

Right below the definition of a test function, push a 
tuple of the INCLUDEELEMENT function name and the number
of methods tested into TESTED_INCLUDE_METHODS. This is 
neccesary for the final test_all_INCLUDEELEMENT_tested
test function to work.
"""

# To catch new functions and methods without tests
# Tuple of include func and num methods tested
const TESTED_INCLUDE_METHODS = Tuple{Function, Int}[]

# For comparison with TESTED_INCLUDE_METHODS
const ACTUAL_INCLUDE_METHODS = Tuple{Function, Int}[]

for f in values(INCLUDEELEMENT)
    f === includeVectorTimeIndex! || continue    # TODO: Remove later
    push!(ACTUAL_INCLUDE_METHODS, (f, length(methods(f))))
end

function test_all_INCLUDEELEMENT_tested()
    tested = Set(TESTED_INCLUDE_METHODS)
    actual = Set(ACTUAL_INCLUDE_METHODS)
    untested = setdiff(actual, tested)
    if length(untested) > 0
        ns = Dict(f => n for (f, n) in tested)
        for (f, n) in untested
            diff = n - get(ns, f, 0)
            s = diff > 1 ? "s" : ""
            println("Missing test$s for $diff method$s for $f")
        end
        return false
    end
    return true
end

function test_includeelement_functions()
    @test test_includeVectorTimeIndex!()
    @test test_all_INCLUDEELEMENT_tested()
end


function test_includeVectorTimeIndex!()
    # tests method when value::AbstractVector{DateTime}
    (TL, LL) = (Dict(), Dict())
    k = ElementKey(TIMEVECTOR_CONCEPT, "VectorTimeIndex", "test")
    # empty vector
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, DateTime[])
    # not sorted
    v = [DateTime(2024, 3, 23), DateTime(1985, 7, 1)]
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, v)
    # should be ok
    v = [DateTime(1985, 7, 1)]
    (ok, deps) = includeVectorTimeIndex!(TL, LL, k, [DateTime(1985, 7, 1)])
    @test ok
    @test deps isa Vector{Id}
    @test length(deps) == 0
    # same id already stored in lowlevel
    LL[Id(k.conceptname, k.instancename)] = 1
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, [DateTime(1985, 7, 1)])

    # tests method when value::Dict
    (TL, LL) = (Dict(), Dict())
    # missing vector in dict
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, Dict())
    # should be ok
    d = Dict()
    d["Vector"] = v
    (ok, deps) = includeVectorTimeIndex!(TL, LL, k, d)
    @test ok
    @test deps isa Vector{Id}
    @test length(deps) == 0
    return true
end
push!(TESTED_INCLUDE_METHODS, (includeVectorTimeIndex!, 2))

test_includeelement_functions()
