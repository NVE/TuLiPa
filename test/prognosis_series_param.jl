module TestPrognosisSeriesParam

using TuLiPa, Dates, Test

function run_tests()
    v = InfiniteTimeVector{Vector{DateTime},Vector{Float64}}(
            [DateTime("2023-01-01T00:00:00"),
            DateTime("2023-01-02T00:00:00"),
            DateTime("2023-01-03T00:00:00")],
            [10, 10, 10])

    horizon = SequentialHorizon(40, Day(1))
    obj_test = PositiveCapacity(Id("Capacity", "Capacity_test"), PrognosisSeriesParam(v, v, v, 1), true)
    pt = PrognosisTime(DateTime("2023-01-01T01:00:00"), DateTime("2023-01-01T01:00:00"), DateTime("2023-01-01T01:00:00"))
    querystart = getstarttime(horizon, 1, pt)
    querydelta = gettimedelta(horizon, 1)
    @test getparamvalue(obj_test.param, querystart, querydelta) == 100
end

@testset "PrognosisSeriesParam" begin
    run_tests()
end

end