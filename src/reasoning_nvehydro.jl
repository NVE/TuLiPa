"""
Here we store functions that are specific for NVE's implementation of the hydropower dataset. 
Watercourse structure and metada is important for the below functions to work.

Functions include:
 - Check if object is plant or pumps and get plants and pumps from list of model objects
 - Get upper and lower reservoir of plants and pumps
 - Set state dependent energy equivalent for plants and pumps (variable based on head)
 - Set head loss costs for reservoirs

 TODO: 
 - More documentation, e.g. illustration of how Storage, Flow, Balance and Arrow make up
 watercourses with regulated/unregulated hydropower plants, pumps, hydraulic couplings,
 bypasses, spills and metadata.
- Consider head dependent release capacity (add as metadata), different hydraulic couplings
(different structure?) and reference curves for storages (already added as restriction, but
could be usefull as metadata aswell)
"""

# --------------- Hydropower plants and pumps -------------------

function ishydroflow(obj)
    if obj isa Flow
        for arrow in getarrows(obj)
            if (getinstancename(getid(getcommodity(getbalance(arrow)))) == "Hydro")
                return true
            end
        end
    end
    return false
end

function ishydroplant(obj)
    if ishydroflow(obj)
        for arrow in getarrows(obj)
            if (getinstancename(getid(getcommodity(getbalance(arrow)))) == "Power") && isingoing(arrow)
                return true
            end
        end
    end
    return false
end

function ishydropump(obj)
    if ishydroflow(obj)
        for arrow in getarrows(obj)
            if (getinstancename(getid(getcommodity(getbalance(arrow)))) == "Power") && !isingoing(arrow)
                return true
            end
        end
    end
    return false
end

function gethydroplants(objects::Vector)
    plants = []
    for obj in objects
        if ishydroplant(obj)
            push!(plants, obj)
        end
    end
    return plants
end

function gethydropumps(objects::Vector)
    pumps = []
    for obj in objects
        if ishydropump(obj)
            push!(pumps, obj)
        end
    end
    return pumps
end

# -------------- Upper and lower reservoir of plants and pumps ---------------------

function getupperreservoirplant(plant::Flow, balanceflows::Dict, storages::Vector)
    for arrow in getarrows(plant)
        if !isingoing(arrow)
            prodbalance = getbalance(arrow) # first identify water balance over plant
            
            # plants with only regulated inflow have one storage directly over plant / water balance (dependant on dataset)
            for storage in storages
                if getbalance(storage) == prodbalance
                    return storage
                end
            end

            # plants with unregulated and regulated inflow have one storage two waterbalances up (dependant on dataset)
            for flow in balanceflows[prodbalance]
                if split(getinstancename(getid(flow)),"r")[1] == split(getinstancename(getid(plant)),"u")[1] # only difference in instancename is "r" and "u"
                    for arrow in getarrows(flow)
                        if isingoing(arrow) & (getbalance(arrow) == prodbalance)
                            for arrow1 in getarrows(flow)
                                if !isingoing(arrow1)
                                    storagebalance = getbalance(arrow1)
                                    for storage in storages
                                        if getbalance(storage) == storagebalance
                                            return storage
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return
end

function getlowerreservoirplant(plant::Flow, balanceflows::Dict, storages::Vector)
    for arrow in getarrows(plant)
        if isingoing(arrow) && (getinstancename(getid(getcommodity(getbalance(arrow)))) == "Hydro")
            prodbalance = getbalance(arrow) # first identify water balance under plant
            
            # most plants will send water directly to underlying reservoir
            for storage in storages
                if getbalance(storage) == prodbalance
                    return storage
                end
            end

            # plants with hydraulic coupling will send water through a water balance, and then to underlying reservoir
            if haskey(prodbalance.metadata, HYDRAULICHINTKEY)
                for flow in balanceflows[prodbalance]
                    for arrow1 in getarrows(flow)
                        if isingoing(arrow1)
                            resbalance = getbalance(arrow1)
                            for storage in storages
                                if getbalance(storage) == resbalance
                                    return storage
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function getlowerreservoirpump(pump::Flow, storages::Vector)
    for arrow in getarrows(pump)
        if !isingoing(arrow) && (getinstancename(getid(getcommodity(getbalance(arrow)))) == "Hydro") # not power market arrow
            prodbalance = getbalance(arrow) # first identify water balance under pump
            
            # find storage connected to balance
            for storage in storages
                if getbalance(storage) == prodbalance
                    return storage
                end
            end
        end
    end
    return
end

function getupperreservoirpump(pump::Flow, storages::Vector)
    for arrow in getarrows(pump)
        if isingoing(arrow)
            prodbalance = getbalance(arrow) # first identify water balance over pump
            
            # find storage connected to balance
            for storage in storages
                if getbalance(storage) == prodbalance
                    return storage
                end
            end
        end
    end
    return
end

# ------------------ State dependent production and pumping -------------------

function statedependentprod_init!(problem::Prob, startstorage::Float64, t::ProbTime)
    dummydelta = MsTimeDelta(Millisecond(0))
    plants = gethydroplants(getobjects(problem))
    storages = getstorages(getobjects(problem))
    balanceflows = getbalanceflows(getobjects(problem))
    for plant in plants
        lowerheight = 0.0 # preallocate
        upperstorage = getupperreservoirplant(plant, balanceflows, storages)
        # Only for plants with upper storages with reservoir curves
        if upperstorage isa Storage
            if haskey(upperstorage.metadata, RESERVOIRCURVEKEY)
                rescurve = upperstorage.metadata[RESERVOIRCURVEKEY]
                startupperstorage = getparamvalue(getub(upperstorage), t, dummydelta)*startstorage/100
                upperheight = yvalue(rescurve, startupperstorage)

                nominalhead = plant.metadata[NOMINALHEADKEY]
                outletlevel = plant.metadata[OUTLETLEVELKEY]

                lowerstorage = getlowerreservoirplant(plant, balanceflows, storages)
                if lowerstorage isa Storage
                    # If has lower storage and has reservoir curve
                    if haskey(lowerstorage.metadata, RESERVOIRCURVEKEY)
                        rescurve = lowerstorage.metadata[RESERVOIRCURVEKEY]
                        startlowerstorage = getparamvalue(getub(lowerstorage), t, dummydelta)*startstorage/100
                        lowerheight = yvalue(rescurve, startlowerstorage)
                        # Make sure lower height is higher than outlet level
                        lowerheight = max(lowerheight, outletlevel)
                    else
                        # Else set lowerheight to outlet level of plant
                        lowerheight = outletlevel
                    end
                else
                    # Else set lowerheight to outlet level of plant
                    lowerheight = outletlevel
                end
                
                # Calculate actual head and factors
                actualhead = upperheight - lowerheight
                factor = actualhead/nominalhead

                # Adjust energy equivalent based on actual head
                for arrow in getarrows(plant)
                    if getinstancename(getid(getcommodity(getbalance(arrow)))) == "Power"
                        if arrow isa BaseArrow # if standard arrow
                            arrow.conversion.param = StatefulParam(TwoProductParam(arrow.conversion.param, ConstantParam(factor)))
                        elseif arrow isa SegmentedArrow # if pq-curve, adjust all points
                            for conversion in arrow.conversions
                                conversion.param = StatefulParam(TwoProductParam(conversion.param, ConstantParam(factor)))
                            end
                        end
                    end
                end
            end
        end
    end
end

function statedependentprod!(problem::Prob, startstates::Dict{String, Float64}; init::Bool=false)
    plants = gethydroplants(getobjects(problem))
    storages = getstorages(getobjects(problem))
    balanceflows = getbalanceflows(getobjects(problem))
    for plant in plants
        lowerheight = 0.0 # preallocate
        upperstorage = getupperreservoirplant(plant, balanceflows, storages)
        # Only for plants with upper storages with reservoir curves
        if upperstorage isa Storage
            if haskey(upperstorage.metadata, RESERVOIRCURVEKEY)
                rescurve = upperstorage.metadata[RESERVOIRCURVEKEY]
                startupperstorage = startstates[getinstancename(getid(upperstorage))]
                upperheight = yvalue(rescurve, startupperstorage)

                nominalhead = plant.metadata[NOMINALHEADKEY]
                outletlevel = plant.metadata[OUTLETLEVELKEY]

                lowerstorage = getlowerreservoirplant(plant, balanceflows, storages)
                if lowerstorage isa Storage
                    # If has lower storage and has reservoir curve
                    if haskey(lowerstorage.metadata, RESERVOIRCURVEKEY)
                        rescurve = lowerstorage.metadata[RESERVOIRCURVEKEY]
                        startlowerstorage = startstates[getinstancename(getid(lowerstorage))]
                        lowerheight = yvalue(rescurve, startlowerstorage)
                        # Make sure lower height is higher than outlet level
                        lowerheight = max(lowerheight, outletlevel)
                    else
                        # Else set lowerheight to outlet level of plant
                        lowerheight = outletlevel
                    end
                else
                    # Else set lowerheight to outlet level of plant
                    lowerheight = outletlevel
                end
                
                # Calculate actual head and factors
                actualhead = upperheight - lowerheight
                factor = actualhead/nominalhead

                # Adjust energy equivalent based on actual head
                for arrow in getarrows(plant)
                    if getinstancename(getid(getcommodity(getbalance(arrow)))) == "Power"
                        if arrow isa BaseArrow # if standard arrow
                            if init
                                arrow.conversion.param = StatefulParam(TwoProductParam(arrow.conversion.param, ConstantParam(factor)))
                            else
                                arrow.conversion.param = StatefulParam(TwoProductParam(arrow.conversion.param.param.param1, ConstantParam(factor)))
                            end
                        elseif arrow isa SegmentedArrow # if pq-curve, adjust all points
                            for conversion in arrow.conversions
                                if init
                                    conversion.param = StatefulParam(TwoProductParam(conversion.param, ConstantParam(factor)))
                                else
                                    conversion.param = StatefulParam(TwoProductParam(conversion.param.param.param1, ConstantParam(factor)))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function statedependentpump!(problem::Prob, startstates::Dict{String, Float64})
    pumps = gethydropumps(getobjects(problem))
    storages = getstorages(getobjects(problem))
    for pump in pumps
        for arrow in getarrows(pump)
            conversion = arrow.conversion
            if conversion isa PumpConversion
                pumpname = getinstancename(getid(pump))
                
                # Lower storage
                lowerstorage = getlowerreservoirpump(pump, storages)
                lowerstorage isa Storage || error(string("No lower storage found for ", pumpname))
                haskey(lowerstorage.metadata, RESERVOIRCURVEKEY) || error("No reservoir curve for lower pump storage ", getinstancename(getid(lowerstorage)))

                rescurve = lowerstorage.metadata[RESERVOIRCURVEKEY]
                startlowerstorage = startstates[getinstancename(getid(lowerstorage))]
                lowerheight = yvalue(rescurve, startlowerstorage)

                # If lower height is lower than intake level there should be no pump capacity
                if lowerheight < conversion.intakelevel
                    pump.ub.param = ConstantParam(0.0)
                    @goto exit_pump # Break nested for loop
                end

                # Upper storage
                upperstorage = getupperreservoirpump(pump, storages)
                upperstorage isa Storage || error(string("No upper storage found for ", pumpname))
                haskey(upperstorage.metadata, RESERVOIRCURVEKEY) || error("No reservoir curve for upper pump storage ", getinstancename(getid(upperstorage)))

                rescurve = upperstorage.metadata[RESERVOIRCURVEKEY]
                startupperstorage = startstates[getinstancename(getid(upperstorage))]
                upperheight = yvalue(rescurve, startupperstorage)
                
                # Calculate actual head, energy equivalent and pump capacity
                actualhead = upperheight - lowerheight
                pumpcapacity = yvalue(conversion.releaseheightcurve, actualhead) # Interpolation handles that conversion.hmin < actalhead < conversion.hmax
                energyequivalent = conversion.pumppower/pumpcapacity/3.6

                # Set pump capacity and energy equivalent
                pump.ub.param = StatefulParam(M3SToMM3Param(ConstantParam(pumpcapacity)))
                conversion.param = StatefulParam(ConstantParam(energyequivalent))
            end
        end
        @label exit_pump
    end
end

# ------------------ Headloss costs ----------------------

"""
The energy equivalent of a hydropower plant is a function of the head,
among other things. For hydropower plants with high head dependence we
want to incentivise the hydropower plant to keep a high reservoir filling,
so that the energy equivalent of produced water is higher. The headloss cost
is a change in the the water value of reservoirs. The head loss cost can be
calculated with different methods.

ReservoirCurveSlopeMethod increases the watervalue if a small increase in 
reservoir filling would give a higher head at the current reservoir filling.
The head loss cost is based on the slope of the reservoir curve (reservoir height [m]
to filling [Mm3]) at the current reservoir filling. To get the headloss cost, we
multiply the water value with a factor of the percentage change in the height for a 2%
change in the reservoir filling divided by 2% (a bit simplified).
- TODO: Test how the ref factor impacts the results and if it should be different
for different reservoirs. Ref factor could also be replaced with the current reservoir filling level. 
ReservoirCurveSlopeMethod could also have a factor which adjust the impact of the headloss cost.

"""

abstract type HeadLossCostMethod end
struct ReservoirCurveSlopeMethod <: HeadLossCostMethod end

function updateheadlosscosts!(method::ReservoirCurveSlopeMethod, clearing::Prob, masters::Vector, t::ProbTime)
    dummydelta = MsTimeDelta(Millisecond(0))
    reffactor = 0.67 

    # Assumes all reservoirs in master problems are also in clearing problem
    for master in masters
        for obj in getobjects(master)
            if obj isa Storage
                if haskey(obj.metadata, RESERVOIRCURVEKEY)
                    (resid, headlosscost, T) = get_headlosscost_data_obj(method, master, t, dummydelta, reffactor, obj)

                    setobjcoeff!(clearing, resid, T, headlosscost) # TODO: Condition that T is the same in clearing and master
                end
            end
        end
    end
end

function updateheadlosscosts!(method::ReservoirCurveSlopeMethod, master::Prob, t::ProbTime)
    dummydelta = MsTimeDelta(Millisecond(0))
    reffactor = 0.67 

    buffer = Tuple{Id, Float64, Int}[]
    for obj in getobjects(master)
        if obj isa Storage
            if haskey(obj.metadata, RESERVOIRCURVEKEY)
                (resid, headlosscost, T) = get_headlosscost_data_obj(method, master, t, dummydelta, reffactor, obj)
                push!(buffer, (resid, headlosscost, T))
            end
        end
    end

    for (resid, headlosscost, T) in buffer
        setobjcoeff!(master, resid, T, headlosscost)
    end
end

function get_headlosscost_data(method::ReservoirCurveSlopeMethod, master::Prob, t::ProbTime)
    dummydelta = MsTimeDelta(Millisecond(0))
    reffactor = 0.67 
    ret = []

    for obj in getobjects(master)
        if hasproperty(obj, :metadata)
            if haskey(obj.metadata, RESERVOIRCURVEKEY) # also implies hydro storage
                push!(ret, get_headlosscost_data_obj(method, master, t, dummydelta, reffactor, obj))
            end
        end
    end

    return ret
end

function get_headlosscost_data_obj(method::ReservoirCurveSlopeMethod, master::Prob, t::ProbTime, dummydelta::TimeDelta, reffactor::Float64, obj::Any)
    resid = getid(obj)
    balid = getid(getbalance(obj))
    T = getnumperiods(gethorizon(obj))

    rescurve = obj.metadata[RESERVOIRCURVEKEY]
    resend = getvarvalue(master, resid, T)
    resmax = getparamvalue(getub(obj), t, dummydelta)
    watervalue = getcondual(master, balid, T)

    R = resmax * reffactor
    H = yvalue(rescurve, R)

    R1 = resend + resmax*0.01
    R0 = resend - resmax*0.01

    H1 = yvalue(rescurve, R1)
    H0 = yvalue(rescurve, R0)

    dH = (H1 - H0) / H
    dR = (R1 - R0) / R

    F = dH/dR

    headlosscost = watervalue * F

    return (resid, headlosscost, T)
end

function resetheadlosscosts!(problem::Prob)
    for obj in getobjects(problem)
        if obj isa Storage
            if haskey(obj.metadata, RESERVOIRCURVEKEY)
                resid = getid(obj)
                T = getnumperiods(gethorizon(obj))
                setobjcoeff!(problem, resid, T, 0.0)
            end
        end
    end
end

# ------------------ State dependent hydraulic leveling  ----------------------
"""
Update hydraulic leveling flows based on storage states and reservoir curves.

For each Flow with `HydraulicFlowHint`:
- Find ingoing and outgoing Hydro balances and their connected storages.
- Compute reservoir elevations from the reservoir curves and current storage states.
- If outgoing elevation is higher than ingoing, enable leveling with capacity limited by
    `min(original_capacity, 0.5 * levelingvolume)` where `levelingvolume` is computed from
    current storage levels.
- Set the flow upper bound as `StatefulParam(TwoProductParam(base_capacity, factor))` where
    `factor ∈ [0, 1]`.

The function throws an error if required storages, reservoir curves, start states,
or compatible flow capacity parameters are missing.
"""

function _get_storage_for_balance(balance::Balance, storages::Vector)
    for storage in storages
        if getbalance(storage) == balance
            return storage
        end
    end
    return nothing
end

function statedependentleveling!(problem::Prob, startstates::Dict{String, Float64}; t::ProbTime=ConstantTime())
    objects = getobjects(problem)
    storages = getstorages(objects)

    for obj in objects
        obj isa Flow || continue

        hasflowhint = haskey(obj.metadata, HYDRAULICFLOWHINTKEY)
        hasflowhint || continue

        isnothing(getub(obj)) && error("Hydraulic leveling flow ", getinstancename(getid(obj)), " is missing upper bound")

        outbalance = nothing
        inbalance = nothing
        for arrow in getarrows(obj)
            commodityname = getinstancename(getid(getcommodity(getbalance(arrow))))
            commodityname == "Hydro" || continue

            if isingoing(arrow)
                inbalance = getbalance(arrow)
            else
                outbalance = getbalance(arrow)
            end
        end

        (inbalance isa Balance && outbalance isa Balance) || error("Hydraulic leveling flow ", getinstancename(getid(obj)), " must have one ingoing and one outgoing Hydro arrow")

        outstorage_obj = _get_storage_for_balance(outbalance, storages)
        instorage_obj = _get_storage_for_balance(inbalance, storages)

        outstorage_obj isa Storage || error("No outgoing storage found for hydraulic leveling flow ", getinstancename(getid(obj)))
        instorage_obj isa Storage || error("No ingoing storage found for hydraulic leveling flow ", getinstancename(getid(obj)))
        haskey(outstorage_obj.metadata, RESERVOIRCURVEKEY) || error("Outgoing storage ", getinstancename(getid(outstorage_obj)), " for hydraulic leveling flow ", getinstancename(getid(obj)), " is missing reservoir curve")
        haskey(instorage_obj.metadata, RESERVOIRCURVEKEY) || error("Ingoing storage ", getinstancename(getid(instorage_obj)), " for hydraulic leveling flow ", getinstancename(getid(obj)), " is missing reservoir curve")

        outstoragename = getinstancename(getid(outstorage_obj))
        instoragename = getinstancename(getid(instorage_obj))
        haskey(startstates, outstoragename) || error("Missing start state for outgoing storage ", outstoragename, " in hydraulic leveling flow ", getinstancename(getid(obj)))
        haskey(startstates, instoragename) || error("Missing start state for ingoing storage ", instoragename, " in hydraulic leveling flow ", getinstancename(getid(obj)))

        outstorage = startstates[outstoragename]
        instorage = startstates[instoragename]

        outcurve = outstorage_obj.metadata[RESERVOIRCURVEKEY]
        incurve = instorage_obj.metadata[RESERVOIRCURVEKEY]

        outheight = yvalue(outcurve, outstorage)
        inheight = yvalue(incurve, instorage)

        baseubparam = getub(obj).param
        baseubparam = baseubparam isa StatefulParam ? baseubparam.param : baseubparam
        baseubparam isa TwoProductParam || error("Flow capacity in hydraulic leveling must be a TwoProductParam for flow ", getinstancename(getid(obj)))
        flowcap = baseubparam.param1
        flowcap isa M3SToMM3Param || error("Flow capacity in hydraulic leveling must have M3SToMM3Param as base capacity for flow ", getinstancename(getid(obj)))

        capdelta = MsTimeDelta(getduration(gethorizon(obj)))
        originalcapacity_mm3 = getparamvalue(flowcap, t, capdelta)

        levelingvolume = 0.0
        targetcapacity_mm3 = 0.0
        if outheight > inheight
            outstorage_at_inheight = xvalue(outcurve, inheight)
            transfer_from_out = max(outstorage - outstorage_at_inheight, 0.0)

            instorage_at_outheight = xvalue(incurve, outheight)
            transfer_to_in = max(instorage_at_outheight - instorage, 0.0)

            levelingvolume = (transfer_from_out + transfer_to_in) * 0.25
            targetcapacity_mm3 = min(originalcapacity_mm3, levelingvolume)
        end

        factor = targetcapacity_mm3 / originalcapacity_mm3

        # @debug "Hydraulic leveling factor for $(getinstancename(getid(obj))) with factor=$factor, outheight=$outheight, inheight=$inheight, levelingvolume=$levelingvolume, originalcapacity_mm3=$originalcapacity_mm3, targetcapacity_mm3=$targetcapacity_mm3"

        getub(obj).param = StatefulParam(TwoProductParam(flowcap, ConstantParam(factor)))
    end

    return
end
