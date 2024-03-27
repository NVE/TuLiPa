"""
Below follows general descriptions of abstract types in our 
modelling framework, and the interfaces each abstract type 
supports. Each abstract type represents a model concept that 
can have subtypes in the form of other abstract types or 
concrete types. The concrete types at the bottom of 
the hierarchy are structs.

Example where JuMP_Prob is a struct with supertype Prob:
mutable struct JuMP_Prob <: Prob
    model::JuMP.Model
    objects::Vector
    horizons::Vector{Horizon}
    rhs::Dict
    isrhsupdated::Bool
end

In our framework we take advantage of Julia having the possibility to 
write functions that work for different types. We can make a generic 
function that work for all or some of the subtypes:
    function solve!(p::Prob)
And if some subtypes are more complex and need a different method, 
we can make functions for these concrete type:
    function solve!(p::JuMP_Prob) 
    function solve!(p::HiGHs_Prob)
When the function solve!(p) is called, the dispatcher will choose the 
most specific method/function that matches the given inputs. This is 
called multiple dispatch, and makes it possible to make a general 
framework that works for different concrete types and 
methods/functions. It also makes it easy to add new concrete types 
or methods without having to change much of the existing code.

TODO: Add resultsystem that collects different data depending on the problem solved
TODO: Add abstract type Group? Have AggSupplyCurve as subtype?
"""


# ---- Prob ----
#
# Represents a Linear Programming (LP) minimization problem where the
# formulation of the problem is defined by a list of model objects.
# The model objects know how they are connected to other model objects
# and how to interact with an optimization model (e.g. add variables 
# and constraints and update parameters wrt. time input). 
# Intended use for problem types is component in energy system 
# simulation models, where a problem is created once, and then updated 
# and solved many times for different states and start times.
# This type is built to work with different optimization frameworks 
# and solvers, see problem_jump.jl and problem_highs.jl
# We only support minimization because it simplified the 
# implementation of state variables and boundary conditions. 
# Maximization must therefore be done by changing the sign of 
# objective function coefficients.
#
# Interface:
#   Constructor prob = f(objects, args...): 
#      prob = HiGHS_Prob(objects)
#      prob = JuMP_Prob(objects, jump_model)
#
#   update!(prob, probtime)
#
#   addvar!(prob, varid, N)
#   addeq!(prob, conid, N)
#   addge!(prob, conid, N)
#   addle!(prob, conid, N)
#
#   setub!(prob, varid, varix, value)
#   setlb!(prob, varid, varix, value)
#   setobjcoeff!(prob, varid, varix, value)
#   setconcoeff!(prob, conid, varid, conix, varix, value)
#   setrhsterm!(prob, conid, termid, conix, value)
#
#   solve!(prob)
#   setsilent!(prob)
#   setunsilent!(prob)
#
#   getobjectivevalue(prob)
#   getvarvalue(prob, varid, varix)
#   getcondual(prob, conid, conix)
#
#   getub(prob, varid, varix)
#   getlb(prob, varid, varix)
#   getobjcoeff(prob, varid, varix)
#   getconcoeff(prob, conid, varid, conix, varix)
#   getrhsterm(prob, conid, termid, conix)
#
#   makefixable!(prob, varid, varix)
#   fix!(prob, varid, varix)
#   unfix!(prob, varid, varix)
#   getfixvardual(prob, varid, varix)
#
abstract type Prob end

# ---- ProbMethod ----
#
# Represent a combination of Prob and specific solver with possible settings.
# Most settings are in the buildprob(probmethod, modelobjects) function 
# (for example solver type or strategy)
# Some information can be input to the object (e.g parallel processes for the solver)
# 
# Interface:
#   prob = buildprob(probmethod, modelobjects)
abstract type ProbMethod end

# ---- TimeDelta ----
#
# Represents a time period
# Used in Horizon
# Can consist of many smaller time periods (see UnitsTimeDelta)
#
# Interface:
#   getduration(timedelta) 
#
abstract type TimeDelta end


# ---- Horizon ----
#
# Horizon is a ProbTime aware sequence of time periods t = 1, 2, .., T
# Each time period has a TimeDelta
# With the starting time of the horizon, and the TimeDeltas of each 
# period, we can find the starting time of each period in the horizon, 
# and look up the corresponding parameter values in data series
# Can have offset, to allow modelling of future scenarios in a Prob
# Can be adaptive (e.g. hours in each week of horizon are grouped in 
#       5 blocks per week, and hours-to-block mapping depends on data 
#       seen from probtime t, for example mapping done by residual load)
#
# Interface:
#   getnumperiods(horizon)
#   getduration(horizon)
#   getstarttime(horizon, periodindex, probtime)
#   getstartduration(horizon, periodindex)
#   gettimedelta(horizon, periodindex)
#   getsubperiods(coarsehorizon, finehorizon, coarseperiodindex)
#   getoffset(horizon)
#   hasoffset(horizon)
#   isadaptive(horizon)
#   hasconstantdurations(horizon)
#   build!(horizon, prob)
#   update!(horizon, probtime)
# 
abstract type Horizon end


# ---- ProbTime ----
#
# A ProbTime is a point in time in the problem horizon / planning period
# Must have at least two dimensions
# The first is datatime
# The second is scenariotime
# This is because most of our data sets are a combination of a 
# level (e.g. installed capacity in datatime 2030, 2040 and 2050) and 
# a profile (e.g. profile value at scenariotime inside the weather 
# scenario 1981-2010). This gives flexibility to run many different scenarios
#
# Interface:
#    getdatatime(probtime)
#    getscenariotime(probtime)
#    + and - for args (probtime, timedelta) in any order
#    + and - for args (probtime, Dates.Period) in any order
#
abstract type ProbTime end


# ---- Flow ----
# 
# Represents variable for each period in an Horizon (e.g. production, 
# transmission, hydro release etc...)
# Have upper and lower Capacity. May have Cost terms.
# Connected to Balances through Arrows. Must have at least one Arrow.
# Horizon for a Flow is the Balance Horizon with finest time 
# resolution pointed to by its Arrows. This way, the Flow variable 
# can appear in all connected Balances regardless of their Horizon.
# May be affected by other traits indirectly
#
# Interface:
#    getid(flow)
#    gethorzion(flow)
#    getarrows(flow)
#    getub(flow)
#    getlb(flow)
#    getsumcost(flow)
#
#    setlb!(flow, capacity)
#    setub!(flow, capacity)
#
#    addcostterm!(flow, cost)
#    addarrow!(flow, arrow)
#
#    build!(prob, flow)
#    setconstants!(prob, flow)
#    update!(prob, flow, start)
#
#    assemble!(flow)
#
#    getstatevariables(flow)
#
abstract type Flow end


# ---- Storage ----
#
# Represents a Storage variable for each period in an Horizon 
# (e.g. hydro/battery/gas storage)
# Connected to a Balance
# For each period the time differential (x[t-1]-x[t]) of the Storage is 
# added to the Balance
# Must have boundary condition for start and/or end variable
# Have upper and lower Capacity. May have Cost terms. May have Loss
# May be affected by other traits indirectly
#
# Interface:
#    getid(storage)
#    getstartvarid(storage)
#    getbalance(storage)
#    gethorzion(storage)
#    getub(storage)
#    getlb(storage)
#    getloss(storage)
#    getsumcost(storage)
#
#    setlb!(storage, capacity)
#    setub!(storage, capacity)
#    setloss!(storage, loss)
#
#    addcostterm!(storage, cost)
#
#    build!(prob, storage)
#    setconstants!(prob, storage)
#    update!(prob, storage, start)
#
#    assemble!(storage)
#
#    getstatevariables(storage)
#
abstract type Storage end


# ---- Balance ----
#
# Represents balance equation with variables and RHSTerms (see BaseBalance)
# (e.g. power market (Balance) with variable thermal production (Flow)
# and fixed wind production or demand (RHSTerm))
# or external price for each period in an Horizon (see ExogenBalance)
# (e.g. power market with fixed price that Flows can exchange with)
# Has Commodity
#
# Interface:
#    getid(balance)
#    gethorzion(balance)
#    getcommodity(balance)
#    assemble!(balance)
#    build!(prob, balance)
#    setconstants!(prob, balance)
#    update!(prob, balance, start)
#
#    if isexogen(balance)
#       getprice(balance)
#    else
#       getrhstems(balance)
#       addrhsterm!(balance, rhsterm)
#    end
#
abstract type Balance end

# ---- Commodity ----
#
# Gives information about a commodity (e.g. Power, Hydro, Gas)
# Has Horizon
# Property of Balance. Balances assigned a Commodity inherits its traits (e.g. its Horizon)
# Makes it easy to assign horizons to modelobjects in the same system, 
# and differentiate which modelobjects are in the same system
#
# Interface:
#    getid(commodity)
#    gethorizon(commodity)
#
abstract type Commodity end


# ---- RHSTerm ----
#
# Property of Balance
# Holds data that will be included in the RHS of Balance equation
# Has Direction to represent positive or negative contribution
#
# Interface:
#    getid(rhsterm)
#    getparamvalue(rhsterm, probtime, timedelta)
#    isconstant(rhsterm)
#    isdurational(rhsterm)
#
abstract type RHSTerm end


# ---- Price ----
#
# Property of Balance
# Holds data that represents the dual solution of a Balance
# Exogen Balances must hold a Price since connected variables will 
# contribute to the Balance based on the Price
#
# Interface:
#    getparamvalue(price, probtime, timedelta)
#    isconstant(price)
#    isdurational(price)
#    iszero(price)
#    isingoing(price)
#
abstract type Price end

# ---- Arrow ----
#
# Represents edge with direction that connects Flow to Balance
# When Balance is endogenous, the arrow puts 
# the Flow variable in the Balance equation
# When Balance is exogenous, the arrow model the connection
# using terms in the objective function
# Must have parameters that describe the contribution
# of the Flow in the Balance (e.g. Conversion or Loss)
#
# Some Arrow types create variables and equations (see SegmentedArrow)
#
# Interface:
#    getid(arrow)
#    getbalance(arrow)
#    setbalance!(arrow, balance)
#    isingoing(arrow)
#
#    build!(prob, arrow)
#    setconstants!(prob, arrow)
#    update!(prob, arrow, start)
#
#    getexogencost(arrow)
#
abstract type Arrow end

# ---- Conversion ----
#
# Property of some Arrow types
# Represents the conversion factor to include a Flow in a Balance
# (e.g. 1 to include a hydro release in a hydro balance, or the energy
# equivalent to include a hydro release in a power balance)
#
# Interface:
#   getparamvalue(conversion, probtime, timedelta)
#   isconstant(conversion)
#   isone(conversion)
#   iszero(conversion)
#   isdurational(conversion)
#   build!(prob, conversion)
#   setconstants!(prob, conversion)
#   update!(prob, conversion, probtime)

abstract type Conversion end

# ---- Loss ----
#
# Property of some Arrow types (e.g. loss on transmission line) 
# or Storage (e.g. loss in heat over time in heat storage)
#
# The utilization rate in SimpleLoss is used for aggregation of Balances,
# where we represent loss on power flow on internal transmission lines
# as demand in the aggregated Balance (e.g. power markets of NO2 and NO1
# is aggregated, then the line NO2-NO1 becomes a demand (loss))
#
# Interface:
#     getutilisation(loss) # TODO: Should all losses have this?
#     isdurational(loss)
#     getparamvalue(loss, probtime, timedelta)
#     isconstant(loss)

abstract type Loss end

# ---- Cost ----
#
# Many objects may have this property, including Flow and Storage
# Represents objective function cost parameter for a variable with Horizon
# Has direction to indicate positive or negative contribution (cost or revenue)
#
# Interface:
#   getparamvalue(cost, probtime, timedelta)
#   isconstant(cost)
#   isingoing(cost)
#   isdurational(cost)
#
abstract type Cost end

# ---- Capacity ----
#
# Property of Flow and Storage
# Represents upper or lower bound parameter for a variable with Horizon
# Some capacity types can have variables and equations (e.g. InvestmentProjectCapacity)
#
# Interface:
#   getparamvalue(capacity, probtime, timedelta)
#   isconstant(capacity)
#   isupper(capacity)
#   iszero(capacity)
#   isnonnegative(capacity)
#   isdurational(capacity)
#   build!(prob, capacity)
#   setconstants!(prob, capacity)
#   update!(prob, capacity, probtime)
#
abstract type Capacity end

# ---- AggSupplyCurve ----
#
# Flows connected to the same Balance are grouped together to
# one or several "equivalent Flows"
# E.g. 20 thermal plants in DEU are represented by 3 equivalent plants 
# One or several variables for each period in an Horizon.
# Possible to aggregate marginal costs, capacities and other Flow traits
# Calculations can be done dynamically as the problem is updated
#
# Interface: 
# getid(var)
# getbalance(var)
# getflows(var)
# getparent(var)
# build!(var)
# setconstants!(var)
# update!(var)

abstract type AggSupplyCurve  end

# ---- StartUpCost ----
#
# Optional trait object that affects a Flow
# Represents the cost of increasing a Flow from 0 up to a 
# value (could be max or minimal viable value)
# Builds and updates internal variables and equations for each period in a Horizon.
# Has internal state variables
# Has cost, and can have information about how long the startup is and what is the 
# minimal viable value (e.g. minimal stable load)
# Linear modelling, so simplification of wanted behaviour
#
# Interface: 
# getid(trait)
# getflow(trait)
# getparent(trait)
# getstatevariables(trait)
# build!(trait)
# setconstants!(trait)
# update!(trait)

abstract type StartUpCost end

# ---- Ramping ----
# 
# Optional trait that affects a (or several) flow(s)
# Maximum increase in a flow variable (ramping) over a given period
# Builds and updates internal variables and equations for each period in a Horizon.
# Can have internal state variables
# 
# Interface:
# getid(trait)
# gethorizon(trait)
# getparent(trait)
# getstatevariables(trait)
# assemble(trait)
# build!(trait)
# setconstants!(trait)
# update!(trait)


abstract type Ramping end

# ---- SoftBound ----
#
# Optional trait object that affects a variable object (e.g. Flow or Storage)
# Represents soft upper or lower bounds to variables 
# Exceeding the soft bound will lead to a penalty (usually a cost)
# Makes necessary variables and balances for each period in a Horizon.
#
# Interface: 
# getid(trait)
# getvar(trait)
# isupper(trait)
# getparent(trait)
# assemble(trait)
# build!(trait)
# setconstants!(trait)
# update!(trait)

abstract type SoftBound end

# ---- Boundary condition ----
#
# Boundary condition for one or more objects that have state variables
# We want to have several types of BoundaryCondition, and we want them 
# to work with different types of objects. We want to be able to check 
# that all objects that have state variables have a terminal condition 
# and initial condition for all its state variables
#
# Interface:
#    isterminalcondition(boundary_condition)
#    isinitialcondition(boundary_condition)
#    getstatfulobjects(boundary_condition)
#    build!(prob, boundary_condition)
#    setconstants!(prob, boundary_condition)
#    update!(prob, boundary_condition, probtime)
# 

abstract type BoundaryCondition end

# ---- Param ------------
# 
# Parameters that store problem data
# Have two (or more) dimensions, in line with ProbTime
# Can store one or several of for example floats, Timevector, Price, Conversion or Loss
# Can be durational
# 
# Interface:
# isconstant(param)
# iszero(param)
# isone(param)
# isdurational(param)
# getparamvalue(param, starttime, timedelta)
# _must_dynamic_update(param, horizon)

abstract type Param end

# ---- TimeVector -------------------
# 
# Objects that store time series data
# timevectors.jl also includes data elements used to read in TimeVectors
# 
# Interface:
# isconstant(timevector)
# getweightedaverage(timevector, starttime, timedelta)

abstract type TimeVector end

# ---- Offset -------------------
# 
# An optional element that shifts where the Horizon starts. 
# Can consist of a isoyear the starttime should be shifted to, and/or
# a TimeDelta. Can be used to combine datasets in time (e.g. adding 
# future scenarios)
# 
# Interface:
# getoffsettime(starttime, offset)

abstract type Offset end





