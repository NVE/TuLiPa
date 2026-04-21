module TestMaskUpdateChecker

using TuLiPa, Test

function run_tests()
    @test TuLiPa._is_mask_updated(Int32[0, 0, 0]) == false
    @test TuLiPa._is_mask_updated(Int32[0, 1, 0]) == true
    @test TuLiPa._is_mask_updated(Int32[]) == false
end

testset_name = Main.get_testset_name("mask_update_checker")
@testset "$testset_name" begin
    run_tests()
end

end # module
