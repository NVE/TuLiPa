
# Data world id fields
const CONCEPTNAME  = "Concept"
const TYPENAME     = "Type"
const INSTANCENAME = "Instance"

# To refer to other objects
const WHICHCONCEPT  = "WhichConcept"
const WHICHINSTANCE = "WhichInstance"

# Data world properties
const UPDATEPERIODSKEY   = "UpdatePeriods"
const UPDATEPERIODSALL   = "All"
const UPDATEPERIODSFIRST = "First"
const UPDATEPERIODSLAST  = "Last"

const DIRECTIONKEY = "Direction"
const DIRECTIONIN  = "In"
const DIRECTIONOUT = "Out"

const BOUNDKEY   = "Bound"
const BOUNDUPPER = "Upper"
const BOUNDLOWER = "Lower"

const LOSSFACTORKEY = "LossFactor"
const UTILIZATIONKEY = "Utilization"
const PENALTYKEY = "Penalty"
const SOFTCAPKEY = "SoftCap"

# Metadata
const STORAGEHINTKEY   = "Storagehint"

# Data world concepts

#  -> lowlevel objects
const TABLE_CONCEPT      = "Table"
const TIMEINDEX_CONCEPT  = "TimeIndex"
const TIMEVALUES_CONCEPT = "TimeValues"
const TIMEVECTOR_CONCEPT = "TimeVector"
const TIMEDELTA_CONCEPT  = "TimeDelta"
const TIMEPERIOD_CONCEPT = "TimePeriod"
const HORIZON_CONCEPT    = "Horizon"

#  -> toplevel objects
const BALANCE_CONCEPT    = "Balance"
const FLOW_CONCEPT       = "Flow"
const STORAGE_CONCEPT    = "Storage"
const COMMODITY_CONCEPT  = "Commodity"
const STARTEQUALSTOP_CONCEPT   = "StartEqualStop"
const AGGSUPPLYCURVE_CONCEPT   = "AggSupplyCurve"
const STARTUPCOST_CONCEPT = "StartUpCost"
const CUTS_CONCEPT = "Cuts"

#  -> toplevel object traits
const ARROW_CONCEPT      = "Arrow"
const PARAM_CONCEPT      = "Param" # Can also be lowlevel objects
const SOFTBOUND_CONCEPT = "SoftBound"
const COST_CONCEPT       = "Cost"
const RHSTERM_CONCEPT    = "RHSTerm"
const METADATA_CONCEPT   = "Metadata"
const BOUNDARYCONDITION_CONCEPT   = "BoundaryCondition"
const CONVERSION_CONCEPT = "Conversion"
const LOSS_CONCEPT = "Loss"
const CAPACITY_CONCEPT = "Capacity"
const PRICE_CONCEPT = "Price"