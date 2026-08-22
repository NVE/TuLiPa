module TestElasticDemandSegments

using TuLiPa, Test

function run_tests()
    # Test parameters: negative elasticity, positive prices
    normal_price = 50.0
    price_elasticity = -0.5
    max_price = 200.0
    min_price = 10.0
    threshold = 0.05

    min_relative_demand = price_to_relative_demand(normal_price, price_elasticity, max_price)
    max_relative_demand = price_to_relative_demand(normal_price, price_elasticity, min_price)

    # --- Test 1: min_relative_demand < max_relative_demand ---
    @test min_relative_demand < max_relative_demand
    @test min_relative_demand > 0

    # --- Test 2: f=1.0 is between min and max relative demand ---
    @test min_relative_demand < 1.0 < max_relative_demand

    # --- Test 3: price_to_relative_demand and relative_demand_to_price are inverses ---
    for p in [10.0, 30.0, 50.0, 100.0, 200.0]
        f = price_to_relative_demand(normal_price, price_elasticity, p)
        p_recovered = relative_demand_to_price(normal_price, price_elasticity, f)
        @test isapprox(p_recovered, p, rtol=1e-10)
    end

    # --- Test 4: at f=1.0 the price equals normal_price ---
    @test isapprox(relative_demand_to_price(normal_price, price_elasticity, 1.0), normal_price, rtol=1e-10)

    # --- Test 5: optimize_segments includes f=1.0 as a breakpoint ---
    L, reserve_prices, N = optimize_segments(
        normal_price, price_elasticity,
        min_relative_demand, max_relative_demand, threshold
    )
    @test 1.0 in L

    # --- Test 6: breakpoints are sorted and within bounds ---
    @test issorted(L)
    @test first(L) ≈ min_relative_demand
    @test last(L) ≈ max_relative_demand

    # --- Test 7: reserve_prices are positive and decreasing (demand curve is decreasing) ---
    @test all(reserve_prices .> 0)
    @test issorted(reserve_prices, rev=true)

    # --- Test 8: segment_capacities are all positive ---
    segment_capacities = [first(L), diff(L)...]
    @test all(segment_capacities .> 0)
    @test length(segment_capacities) == N

    # --- Test 9: segment capacities sum to max_relative_demand ---
    @test isapprox(sum(segment_capacities), max_relative_demand, rtol=1e-10)

    # --- Test 10: after adjust_prices_for_demand_curve_area, the total area is preserved ---
    adjusted_prices = adjust_prices_for_demand_curve_area(
        normal_price, price_elasticity,
        min_relative_demand, max_relative_demand,
        L, reserve_prices
    )
    # The stepped approximation area (excluding the first max_price segment) should
    # equal the integral of the demand curve between min and max relative demand
    seg = diff(L)
    approx_area = sum(adjusted_prices[2:end] .* seg)
    # Exact integral: ∫ p_ref * f^(1/e) df from f1 to f2 = p_ref*e/(1+e) * [f^(1+1/e)] from f1 to f2
    e = price_elasticity
    exact_integral(f) = (normal_price * e * f^(1 + 1/e)) / (1 + e)
    exact_area = exact_integral(max_relative_demand) - exact_integral(min_relative_demand)
    @test isapprox(approx_area, exact_area, rtol=1e-6)

    # --- Test 11: first reserve price equals max_price (from the demand curve at min_relative_demand) ---
    @test isapprox(adjusted_prices[1], reserve_prices[1], rtol=1e-10)

    # --- Test 12: the segment containing f=1.0 has a boundary exactly at 1.0 ---
    # This ensures that at prices above normal_price, demand < firm_demand
    idx_one = findfirst(==(1.0), L)
    @test idx_one !== nothing
    # The reserve price at this breakpoint should equal normal_price
    @test isapprox(reserve_prices[idx_one], normal_price, rtol=1e-10)

    # --- Test 13: with different parameters verify segments stay within N<=10 ---
    for (np, pe, maxp, minp, thr) in [
        (100.0, -0.3, 500.0, 5.0, 0.1),
        (30.0, -1.0, 60.0, 15.0, 0.1),
        (80.0, -2.0, 150.0, 20.0, 0.05),
    ]
        min_rd = price_to_relative_demand(np, pe, maxp)
        max_rd = price_to_relative_demand(np, pe, minp)
        Lp, rp, Np = optimize_segments(np, pe, min_rd, max_rd, thr)
        @test Np <= 10
        @test Np == length(Lp)
        @test issorted(Lp)
        @test all(diff(Lp) .> 0)
        # f=1.0 should be a breakpoint when it's in range
        if min_rd < 1.0 < max_rd
            @test 1.0 in Lp
        end
    end

    # --- Test 14: adaptive_sampling subdivides based on price span ---
    # For a very curved function, adaptive_sampling adds points
    f_curved = x -> 1.0 / (x + 0.01)
    pts_curved = TuLiPa.adaptive_sampling(f_curved, 0.01, 10.0, 0.01, 6)
    @test length(pts_curved) > 2
    @test issorted(pts_curved)
end

testset_name = Main.get_testset_name("elastic_demand_segs")
@testset "$testset_name" begin
    run_tests()
end

end
