"""
Here we store functions that classify or manipulate the model objects after they are fully put together

Assumptions: 
 - Main model objects are Storage, Flow or Balance
 - Other model objects belong to a main model object i.e. supporting getparent(obj) -> object of type Storage, or Flow or Balance

 TODO: Clean up this file
"""

# kan ikke ha hvilke som helst modellobjekter
# Virker bare når modelobjects er Flow, Balance, Storage og Trait (til en av disse tre)
# Kan ikke ha Cuts, eller andre en til mange traits
function getmainmodelobjects(modelobjects::Dict)
    MAINTYPES = Union{Storage, Flow, Balance}
    d = Dict()
    for (id, obj) in modelobjects
        if obj isa MAINTYPES
            if !haskey(d, obj)
                d[obj] = Set()
            end
        else
            mainobj = getparent(obj)

            if !((obj isa SimpleSingleCuts) || (obj isa EndValues))
                if !(mainobj isa MAINTYPES)
                    error("Main model object for $id is not $MAINTYPES. Got $(typeof(mainobj))")
                end

                if !haskey(modelobjects, getid(mainobj))
                    error("Main model object for $id with id $(getid(mainobj)) does not exist in supplied model objects")
                end

                if !haskey(d, mainobj)
                    d[mainobj] = Set()
                end
                push!(d[mainobj], obj)
            end
        end
    end
    return d
end

function get_main_paths(storagesystem)
end

function aggregate_balances(modelobjects::Dict, aggbalances::Dict{String, Vector{String}})
    # check that no balance is in more than one aggbalance
    # check that no aggbalances are empty
    # What do we do if some of the balances are e.g. storage balances?
    # What do we do if some of the balances are e.g. exogen balances?
    # What do we do if some of the balances have different commodity?
    # what to do if aggbalance has same name as an existing balance?
    # error if balance in aggbalance does not exist in modelobjects
    # return copy of modelobjects with aggregated balances
    # remove internal transmission, make internal losses into demand
end

function calculate_storage_durations(modelobjects, storages)
end

function isingoingflow(x)
    x isa Flow || return false

    arrows = getarrows(x)
    length(arrows) == 1 || return false

    a = first(arrows)

    return isingoing(a)
end

function isoutgoingflow(x)
    x isa Flow || return false

    arrows = getarrows(x)
    length(arrows) == 1 || return false

    a = first(arrows)

    return !isingoing(a)
end

function istransmissionvariable(x)
    x isa Flow || return false

    arrows = getarrows(x)
    length(arrows) == 2 || return false

    a1 = first(arrows)
    a2 = last(arrows)

    b1 = getbalance(a1)
    b2 = getbalance(a2)

    b1 == b2 && return false

    getcommodity(b1) == getcommodity(b2) || return false

    isingoing(a1) == isingoing(a2) && return false

    l1 = getlag(a1)
    l2 = getlag(a2)
    !isnothing(l1) && isdiffertial(l1) && return false
    !isnothing(l2) && isdiffertial(l2) && return false
    
    return true
end

function getstorages(modelobjects::Dict)
    [x for x in values(modelobjects) if x isa Storage]
end

function getstorages(modelobjects::Vector)
    [x for x in modelobjects if x isa Storage]
end

function getbalanceflows(modelobjects::Dict)
    d = Dict{Balance, Set{Flow}}()
    for obj in values(modelobjects)
        if obj isa Flow 
            for a in getarrows(obj)
                b = getbalance(a)
                if !haskey(d, b)
                    d[b] = Set()
                end
                push!(d[b], obj)
            end
        end
    end
    return d
end

function getbalanceflows(modelobjects::Vector)
    d = Dict{Balance, Set{Flow}}()
    for obj in modelobjects
        if obj isa Flow 
            for a in getarrows(obj)
                b = getbalance(a)
                if !haskey(d, b)
                    d[b] = Set()
                end
                push!(d[b], obj)
            end
        end
    end
    return d
end

# kan ikke ha hvilke som helst modellobjekter
function getstoragesystems(modelobjects::Dict)
    storages = Set(getstorages(modelobjects))
    storagebalances = Dict(getbalance(s) => s for s in storages)
    balanceflows = getbalanceflows(modelobjects)
    traits = getmainmodelobjects(modelobjects)

    systems = []
    while length(storages) > 0
        completed = Set()

        storage = pop!(storages)

        push!(completed, storage)

        commodity = getcommodity(getbalance(storage))

        remaining = Set()
        push!(remaining, getbalance(storage))

        while length(remaining) > 0
            obj = pop!(remaining)

            push!(completed, obj)

            if obj isa Balance
                if haskey(storagebalances, obj)
                    astorage = storagebalances[obj]
                    if !(astorage in completed)
                        push!(completed, astorage)
                        (astorage in storages) && delete!(storages, astorage)
                    end
                end

                for flow in balanceflows[obj] 
                    if !(flow in completed)
                        push!(remaining, flow)
                    end
                end
            
            else 
                @assert obj isa Flow
                for arrow in getarrows(obj)
                    abalance = getbalance(arrow)
                    if getcommodity(abalance) == commodity
                        if !(abalance in completed)
                            push!(remaining, abalance)
                        end
                    end
                end
            end
        end

        for obj in collect(completed)
            for trait in traits[obj]
                push!(completed, trait)
            end
        end

        push!(systems, collect(completed))
    end
    return systems
end

# TODO: Replace inputted hint with getemptyduration(storage) -> Time to empty in ms starting with full storage
function getshorttermstoragesystems(storagesystems::Vector, durationcutoff::Period)
    ret = []
    
    for storagesystem in storagesystems
        isshortterm = true
        for obj in storagesystem
            (obj isa Storage) || continue

            timedelta = getstoragehint(obj)

            if timedelta !== nothing
                if getduration(timedelta) >= durationcutoff
                    isshortterm = false
                    break
                end
            else
                isshortterm = false
                break
            end
        end

        if isshortterm
            push!(ret, storagesystem)
        end
    end

    return ret
end

function getlongtermstoragesystems(storagesystems::Vector, durationcutoff::Period)
    ret = []
    
    for storagesystem in storagesystems
        islongterm = true
        for obj in storagesystem
            (obj isa Storage) || continue

            timedelta = getstoragehint(obj)

            if timedelta !== nothing
                if getduration(timedelta) < durationcutoff
                    islongterm = false
                    break
                end
            end
        end

        if islongterm
            push!(ret, storagesystem)
        end
    end

    return ret
end

function getstoragesystems_full!(storagesystems::Vector) # including powerbalances
    for storagesystem in storagesystems
        for obj in storagesystem
            if obj isa Flow
                for arrow in getarrows(obj)
                    balance = getbalance(arrow)
                    if !(balance in storagesystem)
                        push!(storagesystem, balance)
                    end
                end
            end
        end
    end

    return storagesystems
end

function removestoragesystems!(modelobjects::Dict, durationcutoff)
    storagesystems = getstoragesystems(modelobjects)
    shorttermstoragesystems = getshorttermstoragesystems(storagesystems, durationcutoff)
    for shorttermstoragesystem in shorttermstoragesystems
        for obj in shorttermstoragesystem
            delete!(modelobjects,getid(obj))
        end
    end
end

function getshorttermstorages(modelobjects::Vector, durationcutoff)
    modelobjectsdict = Dict{Id,Any}() # TODO: Quick fix... decide if modelobjects should always be vector or dict (latter preferred)
    for obj in modelobjects
        modelobjectsdict[getid(obj)] = obj
    end

    shorttermstorages = Storage[]

    storagesystems = getstoragesystems(modelobjectsdict)
    shorttermstoragesystems = getshorttermstoragesystems(storagesystems, durationcutoff)
    for shorttermstoragesystem in shorttermstoragesystems
        for obj in shorttermstoragesystem
            if obj isa Storage
                push!(shorttermstorages, obj)
            end
        end
    end

    return shorttermstorages
end

#-------------------------------------
function getbalances(modelobjects::Dict, commodityid::Id)
    balances = Set()
    for obj in values(modelobjects)
        if obj isa Balance
            if getid(getcommodity(obj)) == commodityid
                push!(balances,obj)
            end
        end
    end
    return balances
end

function getbalances(modelobjects::Vector)
    balances = Set()
    for obj in values(modelobjects)
        if obj isa Balance
            push!(balances,obj)
        end
    end
    return balances
end

function getpowersystems(modelobjects::Dict)
    storages = getstorages(modelobjects)
    storagebalances = Dict(getbalance(s) => s for s in storages)
    
    balances = getbalances(modelobjects, Id(COMMODITY_CONCEPT,"Power"))
    balanceflows = getbalanceflows(modelobjects)
    traits = getmainmodelobjects(modelobjects)

    systems = Dict()
    while length(balances) > 0
        completed = Set()

        balance = pop!(balances)

        push!(completed, balance)

        commodity = getcommodity(balance)

        remaining = Set{Any}(balanceflows[balance])

        while length(remaining) > 0
            obj = pop!(remaining)

            push!(completed, obj)

            if obj isa Flow
                for arrow in getarrows(obj)
                    abalance = getbalance(arrow)
                    if getcommodity(abalance) != commodity
                        if !(abalance in completed)
                            push!(remaining, abalance)
                        end
                    end
                end 
            elseif obj isa Balance
                if haskey(storagebalances, obj)
                    astorage = storagebalances[obj]
                    if !(astorage in completed)
                        push!(remaining, astorage)
                    end
                end

                for flow in balanceflows[obj] 
                    if !(flow in completed)
                        push!(remaining, flow)
                    end
                end
            end
        end

        for obj in completed
            if haskey(traits, obj)
                for trait in traits[obj]
                    push!(completed, trait)
                end
            end
        end

        systems[balance] = completed
    end
    return systems
end

function getpowerobjects(modelobjects, arealist)
    objects = Set()
    powersystems = getpowersystems(modelobjects)
    for area in arealist
        balancename = "PowerBalance_" * area
        for obj in powersystems[modelobjects[Id(BALANCE_CONCEPT,balancename)]]
            push!(objects, obj)
        end
    end
    return collect(objects)
end

# -------------- remove other areas from residualload ---------------
function residualloadareas!(modelobjects, arealist)
    areaobjects = getpowerobjects(modelobjects, arealist)

    for obj in values(modelobjects)
        obj isa Balance || continue
        isexogen(obj) && continue
        getinstancename(getid(getcommodity(obj))) == "Power" || continue
        obj in areaobjects && continue # what order should the check be in?
        for rhs_term in getrhsterms(obj)
            isconstant(rhs_term) && continue
            setmetadata!(rhs_term, RESIDUALHINTKEY, false)
        end
    end
end

# -------------------------------------
function mapbalancesupply(modelobjects) # replace with is simple mc
    mapping_balance_supply = Dict()
    for obj in values(modelobjects)
        if obj isa BaseFlow
            arrows = getarrows(obj)
            if (hascost(obj)) & (length(arrows) == 1)
                arrow = arrows[1]
                if isingoing(arrow)
                    balance = getbalance(arrow)
                    if ~haskey(mapping_balance_supply,balance)
                        mapping_balance_supply[balance] = [obj]
                    else
                        push!(mapping_balance_supply[balance],obj)
                    end
                end
            end
        end
    end
    return mapping_balance_supply
end

function aggregatesupplycurve!(modelobjects, numclusters) # TODO: Can add rules for when to cluster. Now if numplants > numclusters.
    
    mapping_balance_supply = mapbalancesupply(modelobjects)

    for (balance, plants) in mapping_balance_supply
        if length(plants) > numclusters
            balanceinstance = getinstancename(getid(balance))
            flows = Flow[]
            for plant in plants
                push!(flows,plant)
                delete!(modelobjects,getid(plant))
            end
            
            newname = "PlantAgg_" * balanceinstance
            newid = Id(AGGSUPPLYCURVE_CONCEPT,newname)
            modelobjects[newid] = BaseAggSupplyCurve(newid, balance, flows, numclusters)
        end
    end
end

#------------------------
replacebalance!(x::Any, coupling, modelobjects) = error("Function replacebalance! not implemented for $(typeof(x))")
replacebalance!(x::BaseBalance, coupling, modelobjects) = nothing
replacebalance!(x::ExogenBalance, coupling, modelobjects) = nothing
replacebalance!(x::SimpleStartUpCost, coupling, modelobjects) = nothing
replacebalance!(x::StartEqualStop, coupling, modelobjects) = nothing
replacebalance!(x::BaseSoftBound, coupling, modelobjects) = nothing
replacebalance!(x::TransmissionRamping, coupling, modelobjects) = nothing # handled in replacebalance!(x::BaseFlow

function replacebalance!(x::BaseStorage, coupling, modelobjects)
    if haskey(coupling, getbalance(x))
        setbalance!(x, coupling[getbalance(x)])
    end
end

function replacebalance!(x::BaseFlow, coupling, modelobjects)
    mainmodelobjects = getmainmodelobjects(modelobjects)

    replacer = BaseBalance[]
    for arrow in getarrows(x)
        if haskey(coupling, getbalance(arrow))
            setbalance!(arrow, coupling[getbalance(arrow)])
            push!(replacer, getbalance(arrow))
        end
    end
    
    if (length(replacer) > 1) & (length(Set(replacer)) == 1) # if line now inside aggregated area
        for arrow in getarrows(x)
            if !isnothing(arrow.loss)
                rhsname = string("TransmLoss", getinstancename(getid(arrow)))
                id = Id(RHSTERM_CONCEPT, rhsname)
                param = TransmissionLossRHSParam(getub(x), getloss(arrow)) # assumes conversion = 1
                rhsterm = BaseRHSTerm(id, param, false) 
                setmetadata!(rhsterm, RESIDUALHINTKEY, false) # don't include in residual load
                addrhsterm!(getbalance(arrow), rhsterm)
            end
        end
        delete!(modelobjects, getid(x))
        for minor in mainmodelobjects[x]
            delete!(modelobjects, getid(minor))
        end
    elseif length(replacer) > 0
        assemble!(x) # needed? commodity/horizon should not be updated
    end
end

function aggzone!(modelobjects, aggzonedict)
    aggzonedict1 = Dict()
    for (newid,oldbalances) in aggzonedict

        newbalance = BaseBalance(newid,getcommodity(oldbalances[1])) # assumes same commodity

        for oldbalance in oldbalances
            aggzonedict1[oldbalance] = newbalance
            for rhsterm in getrhsterms(oldbalance)
                addrhsterm!(newbalance,rhsterm)
            end
            delete!(modelobjects,getid(oldbalance))
        end    

        assemble!(newbalance)
        modelobjects[newid] = newbalance
    end

    #println(string("Modelobjects after removing balances: ", length(modelobjects)))
    
    for obj in values(modelobjects)
        replacebalance!(obj, aggzonedict1, modelobjects)
    end
end

#-----------------------

# TODO: Finish
function transform_simple_demand_to_supply!(modelobjects::Dict)
    # also check that no special traits

    must_reassemble = Set()

    for (id, obj) in modelobjects
        (obj isa Flow)           || continue

        arrows = getarrows(obj)
        length(arrows) == 1      || continue

        arrow = first(arrows)
        isindirection(arrow)     && continue

        hascost(obj)             || continue
        hasub(obj)               || continue

        # push demand capacity to RHSTerm in flow balance
        # add balance to must_reassemble

        # replace demand flow with supply flow
        # add flow to must_reassemble

    end

    for id in must_reassemble
        obj = modelobjects[id]
        assemble!(obj)
    end
end


function find_groupable_balances(modelobjects::Dict, method)
    # find subsystems within same commodity with no storage and good connection
    # (challange is fast good estimate of 'good connection')
    # Error if modelobjects contain AggSupplyCurve
end


function aggregate_equal_flows!(modelobjects::Dict, method)
end

function simplify_external_balances!(modelobjects::Dict, method)
    # Find balances with one supply and one demand with cap > sum(line cap)

    # If lines have loss, add supply price to import and export
    # else: make net export and use price 

    # delete supply, demand and balance
    # if two-lines (import/export) are replaced with netexport, delete import and export

end



