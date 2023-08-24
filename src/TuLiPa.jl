module TuLiPa

# Abstract types in our modelling framework and general descriptions
include("abstracttypes.jl")

# Code to add and convert data elements into model objects
include("data_elements.jl")
include("data_elements_to_objects.jl")
include("data_constants.jl")
include("data_utils.jl")

# Problem implementation around JuMP framework and HiGHS package
include("problem_jump.jl") # with description of general problem framework
include("problem_highs.jl")

# Time, time-series and horizons (based on Dates.jl)
include("utils_datetime.jl") # functions for datetime
include("timedeltas.jl") # time-periods in horizons
include("timevectors.jl") # time-series data
include("times.jl") # problem times
include("timeperiods.jl") # start and stop of simulation/scenario 
include("timeoffset.jl") # to offset problem times
include("horizons.jl")

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

# Parameters for model objects and traits (Lowlevel)
include("parameters.jl")

# Toplevel model objects
include("obj_balance.jl")
include("obj_flow.jl")
include("obj_storage.jl")
include("obj_aggsupplycurve.jl")
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

export update! 
export solve!
export getduration 
export getrhsterm
export getisoyear
export getvarvalue
export getscenariotime
export getconcoeff
export getobjectivevalue
export getstartduration
export getcondual
export getbalance
export getcommodity
export getinstancename
export getisoyearstart
export getid 
export getrhsterms 
export getnumperiods 
export getparamvalue 
export gettimedelta
export getstarttime 
export getdatatime 
export getlb
export getub
export getarrows
export gethorizon
export getmodelobjects

export hasrhsterm
export isingoing

export Id 
export TwoTime
export SequentialHorizon
export BaseStorage
export BaseBalance
export BaseFlow
export JuMP_Prob
export DataElement

export TIMEVALUES_CONCEPT
export BALANCE_CONCEPT
export COMMODITY_CONCEPT
export FLOW_CONCEPT
export TIMEINDEX_CONCEPT
export BOUNDKEY
export COST_CONCEPT
export STORAGE_CONCEPT
export TIMEVECTOR_CONCEPT
export BOUNDUPPER
export RHSTERM_CONCEPT
export WHICHCONCEPT
export WHICHINSTANCE
export PARAM_CONCEPT
export ARROW_CONCEPT
export CONVERSION_CONCEPT
export DIRECTIONKEY
export DIRECTIONOUT
export DIRECTIONIN
export CAPACITY_CONCEPT
export TABLE_CONCEPT
export TIMEPERIOD_CONCEPT
export HORIZON_CONCEPT
export BOUNDARYCONDITION_CONCEPT



end
