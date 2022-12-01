# ---- Prob ----
#
# Represents a Linear Programming (LP) minimization problem where the
# formulation of the problem is defined by a list of model objects, 
# which know how to interact with the problem (i.e. add variables and constraints 
# and update parameters wrt. time input). 
# Intended use for problem types is component in energy system simulation models,
# where a problem is created once, and then updated and solved many times for different
# states and start times.
#
# Interface:
#   Constructor prob = f(objects, args...): 
#      prob = HiGHS_Prob(objects)
#      prob = JuMP_Prob(objects, jump_model)
#
#   solve!(prob)
#   update!(prob, probtime)
#
#   addvar!(prob, varid, N)
#   addeq!(prob, conid, N)
#   addge!(prob, conid, N)
#   addle!(prob, conid, N)
#
#   makefixable!(prob, varid, varix)
#   fix!(prob, varid, varix)
#   unfix!(prob, varid, varix)
#
#   setub!(prob, varid, varix, value)
#   setlb!(prob, varid, varix, value)
#   setobjcoeff!(prob, varid, varix, value)
#   setconcoeff!(prob, conid, varid, conix, varix, value)
#   setrhsterm!(prob, conid, termid, conix, value)
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
#   setsilent!(prob)
#   setunsilent!(prob)
#
abstract type Prob end


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
# Can have offset, to allow modelling of future scenarios in a Prob
# Can be adaptive (e.g. hours in each week of horizon are grouped in 5 blocks per week, 
#                  and hours to block mapping depends on data seen from probtime t)
#
# Interface:
#   getnumperiods(horizon)
#   getduration(horizon)
#   getstarttime(horizon, periodindex, probtime)
#   getstartduration(horizon, periodindex)
#   gettimedelta(horizon, periodindex)
#   getsubperiods(coarsehorizon, finehorizon, coarseperiodindex)
#   getoffset(horizon)
#   isadaptive(horizon)
#   hasconstantdurations(horizon)
#   build!(horizon, prob)
#   update!(horizon, probtime)
# 
abstract type Horizon end


# ---- ProbTime ----
#
# A ProbTime have at least two dimentions. 
# The first dimention is datatime, the second is scenariotime.
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
# Represents variable for each period in an Horizon.
# Have upper and lower Capacity. May have Cost terms.
# Connected to Balances through Arrows. Must have at least one Arrow.
# Horizon for a Flow is the Balance Horizon with finest time 
# resolution pointed to by its Arrows. This way, the Flow variable 
# can appear all connected Balances through by summation.
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
# Represents variable for each period in an Horizon
# Have upper and lower Capacity. May have Cost terms.
# Has a Balance and the time differential 
# of the Storage variable is connected to the outgoing side of theBalance
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
# Represents balance equation with possible RHSTerms 
# or external price for each period in an Horizon
# Has Commodity
#
# Interface:
#    getid(balance)
#    gethorzion(balance)
#    assemble!(balance)
#
#    if isexogen(balance)
#       getprice(balance)
#    else
#       getrhstems(balance)
#       addrhsterm!(balance, rhsterm)
#       build!(prob, balance)
#       setconstants!(prob, balance)
#       update!(prob, balance, start)
#    end
#
abstract type Balance end

# ---- Commodity ----
#
# Property of Balance
# Has Horizon
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
# Exogen Balances must hold a Price
# Has Direction to represent positive or negative contribution
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
# When Balance is endogeneous, the arrow connects 
# the Flow variable in the Balance equation
# When Balance is exogenous, the arrow model the connection
# using terms in the objective function
# Must have parameters that describe the contribution
# of the Flow in the Balance (e.g. Conversion or Loss)
#
# Some Arrow types create variables and equations (see SegmentedArrow)
#
# In the future, we want to implement an Arrow type with time delay, 
# e.g. to model which would have state variables
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
# The utilization rate is used for aggregation of Balances,
# where we represent loss on power flow on internal transmission lines
# as demand in the aggregated Balance
#
# Interface:
#     getutilisation(loss)
#     isdurational(loss)
#     getparamvalue(loss, probtime, timedelta)
#     isconstant(loss)

abstract type Loss end

# ---- Cost ----
#
# Many objects may have this property, including Flow and Storage
# Represents objective function cost parameter for a variable with Horizon
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
# getmainmodelobject(var)
# build!(var)
# setconstants!(var)
# update!(var)

abstract type AggSupplyCurve  end



abstract type StartUpCost end

# ---- SoftBound ----
#
# Optional trait object that affects a variable object (e.g. Flow or Storage)
# Represents soft upper or lower bounds to variables 
# Exceeding the soft bound will lead to an economic penalty
# Makes necessary variables and balances for each period in an Horizon.
#
# Interface: 
# getid(trait)
# getvar(trait)
# isupper(trait)
# getmainmodelobject(trait)
# assemble(trait)
# build!(trait)
# setconstants!(trait)
# update!(trait)

abstract type SoftBound end

# ---- Boundary condition ----
#
# Boundary condition for one or more objects that have state variables
# We want to have several types of BoundaryCondition, and we want them to work
# with different types of objects. We want to be able to check that all objects
# that have state variables have a terminal condition and initial condition for 
# all its state variables
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


# abstract type Group end # Do we need this?

# Dataset system
abstract type DataElement end # TODO: Make this concrete

# ---- Param ------------
# 
# Parameters that that store problem data
# Can store one or several of for example
# floats, Timevector, Price, Conversion or Loss
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
# 
# Interface:
# isconstant(timevector)
# getweightedaverage(timevector, starttime, timedelta)

abstract type TimeVector end





