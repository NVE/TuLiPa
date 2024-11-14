module TuLiPa

# TODO: Can we drop CSV and DataFrames?
using CSV, Dates, DataFrames

# Abstract types in our modelling framework and general descriptions
include("abstracttypes.jl")

# Code to add and convert data elements into model objects
include("input_system.jl")
include("input_utils.jl")

# Problem implementation around JuMP framework and HiGHS package
include("problem_jump.jl") # with description of general problem framework
include("problem_highs.jl")
include("problem_method.jl")
include("problem_common.jl")
include("problem_fixbreach.jl")

# Time, time-series and horizons (based on Dates.jl)
include("utils_datetime.jl") # functions for datetime
include("timedeltas.jl") # time-periods in horizons
include("timevectors.jl") # time-series data
include("times.jl") # problem times
include("timeperiods.jl") # start and stop of simulation/scenario 
include("timeoffset.jl") # to offset problem times
include("horizons.jl")
include("horizons_shrinkable_shiftable.jl") # shrink or shift horizon periods

# Lowlevel model objects
# see data_elements_to_objects.jl for description of difference between lowlevel and toplevel
include("trait_conversion.jl")
include("trait_loss.jl")
include("trait_cost.jl")
include("trait_price.jl")
include("trait_capacity.jl")
include("trait_arrow.jl")
include("trait_rhsterm.jl")
include("trait_commodity.jl")
include("trait_metadata.jl")
include("trait_flow_based_constraints.jl")

# Parameters for model objects and traits (Lowlevel)
include("parameters.jl")

# Toplevel model objects
include("obj_balance.jl")
include("obj_flow.jl")
include("obj_storage.jl")
include("obj_aggsupplycurve.jl")
include("obj_elastic_demand.jl")

include("trait_softbound.jl")
include("trait_startupcost.jl")
include("trait_ramping.jl")

# State variables and boundary conditions
include("state_variables.jl")
include("boundary_conditions.jl") # (Toplevel)

# Code to manipulate model objects
# (e.g. alter, aggregate, distinguish features)
include("reasoning_modelobjects.jl")
include("reasoning_nvehydro.jl")

# Resulthandling
include("results.jl")

_EXCLUDE_SYMBOLS = [:include, :eval]

for sym in names(@__MODULE__; all = true)
    sym_string = string(sym)
    if sym in _EXCLUDE_SYMBOLS ||
       startswith(sym_string, "_") ||
       startswith(sym_string, "@_")
        continue
    end
    if !(
        Base.isidentifier(sym) ||
        (startswith(sym_string, "@") && Base.isidentifier(sym_string[2:end]))
    )
        continue
    end
        
    @eval export $sym
end

include("../test/utils_dummy_data.jl")

using PrecompileTools, JuMP, HiGHS

@compile_workload begin
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
	modelobjects = getmodelobjects(elements);

	mymodel = JuMP.Model(HiGHS.Optimizer)
	set_silent(mymodel)
	prob = JuMP_Prob(modelobjects, mymodel)
	prob.model

	t = TwoTime(getisoyearstart(2021), getisoyearstart(1981))
	update!(prob, t)

	solve!(prob)
	prob1 = getobjectivevalue(prob)
end


end
