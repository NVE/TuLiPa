"""
We pad testset names to get aligned 
summaries when the tests are run.
Much easier to read this way.
"""
function get_testset_name(s::String, n::Int=40)
    length(s) < n || return s
    string(s, repeat("_", n - length(s)))
end

include("basic_solving.jl")
include("timeoffset.jl")
include("highs_equals_jump_results.jl")
# include("rotating_time_vector.jl")  # TODO: Modify tests to handle one year data
include("umm.jl")
include("prognosis_series_param.jl")
include("apply_settings.jl")
include("getmodelobjects.jl")
include("includeelement_functions.jl")
