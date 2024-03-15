"""
Here we define the getmodelobjects function, which compiles data elements into model objects.

The parts and steps are described below:

DataElements: see data_types.jl

INCLUDEELEMENT:
    Each data element has an INCLUDEELEMENT function that will include it into lowlevel or toplevel,
    or another object in toplevel/lowlevel. 
    
    Toplevel is a list of objects that will end up in the final 
    model object list (i.e. Flow, Balance, SoftBound etc...), while lowlevel is a temporary storage 
    of objects that will be put into the toplevel objects (i.e. RHSTerms, Capacity, TimeVector etc...). 

    When including an element, first we check if all the dependencies of the data element have been
    created (in toplevel or lowlevel). If that is the case, the object will be built (also important to 
    validate that all the inputs behave as expected) and put into toplevel, lowlevel or other objects 
    inside one of toplevel/lowlevel.

    Naming convention: 
        All functions named include + OBJECTNAME + !
        (see for example includePositiveCapacity! in trait_capacity.jl) 

    Function signature: 

        (ok, needed_objkeys) = f(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value)
        
        where ok::Bool if true if the object was successfully included, and false if one or more 
        dependencies are missing (throw error for other types of failure, such as validation failures)
        
        needed_objkeys is a Vector{Id} (normal case) or 
        Tuple{Vector{String}, Vector{Id}} (special case to handle errors)
        containing all objects that the function needs in order
        to successfully execute, and was added because we needed it for two things: 
            1. To add this behaviour to the  getmodelobjects
            (objects, dependencies) = getmodelobjects(data_elements, deps=true)
            which enables us to find all data elements that belongs to a subset of
            objects. We needed this to minimize data transfers to cores in JulES.

            2. To add better error messages in getmodelobjects. When getmodelobjects fails
            to compile all data elements into model objects, we can use needed_objkeys to 
            figure out why a data element failed. This will in turn enable us to find
            root causes, e.g. if one missing object causes several layers of failures
            because many objects depend on it, and other objects depend on the objects that 
            depend on it, and so on. In such case we can give a good error message informing
            only about the root cause. This is much better than the old verson, which just
            listed all objects that failed, even though most of them failed because of the
            same (root cause) object. This left it to the user to figure out the root cause,
            which is very time consuming. 
            
            Note that for this to work correctly, the INCLUDEELEMENT-functions 
            must always return all its dependencies. Furthermore, 
            the INCLUDEELEMENT-functions must return ok=false only when one or 
            more dependencies are missing. Other types of failures 
            (such as validation failures) should throw errors, or use the special
            dependency type Tuple{Vector{String}, Vector{Id}} where the 
            Vector{String} part contains error messages.

    NB! Note about needed_objkeys: a failing elemnt may return larger set of dependencies
        than a non-failing element. This is because some dependencies can be one of multiple
        options, and we don't know which one when the element fails. E.g. if an element depends
        on a Price object, this could refer to a Price element or a Param element 
        (if so it will be converted into a Price object). For a non-failing element we know
        which one it is, and only return this as dependency. If the element fails, we have 
        to return both object keys.

The getmodelobjects function consist of 3 elements:
    error_if_duplicates(elements)
        There should be no duplicates in the data elements. Throw error if duplicates.

    include_all_elements(elements)
        This function loops through all the data elements and runs their INCLUDEELEMENT function. This is
        an iterative process where data elements are converted to objects when all their dependencies have
        been created. This iteration stops when no more objects are included in the list of completed 
        data elements. If some data elements failed to be included there is an error message with the list
        of these, else return toplevel.

    assemble!(modelobjects)
        When all the information has been included in the model objects in toplevel, they can be assembled. 
        This could be for example finding the horizon of a Flow (variable) based on all the Balances it is 
        connected to. This is also an iterative process similar to the one in include_all_elements(elements), 
        because some model objects depend on others being assembled before they can be assembled themselves.
        - NB! Pushing modelobjects to list in assemble! should only be done after we have checked that all 
              associated modelobjects are assembled. Mixing this order can lead to modelobjects being partially 
              assembled several times, and therefore duplicated elements.

"""

# TODO: Document usage for all kwargs
# TODO: Explain better why dependencies types Vector{Id}/Tuple{Vector{String}, Vector{Id}}

const INCLUDEELEMENT = Dict{TypeKey, Function}()

# TODO: remove kwarg validate::Bool=true ? INCLUDEELEMENT-function always do validation. Can do advanced validation on modelobjects, but this is hard and not top priority.
function getmodelobjects(elements::Vector{DataElement}; validate::Bool=true, deps::Bool=false)
    error_if_duplicates(elements)
    (modelobjects, dependencies) = include_all_elements(elements)
    assemble!(modelobjects)
    if deps
        dependencies = compact_dependencies(dependencies, elements)
        return (modelobjects, dependencies)
    else
        return modelobjects
    end
end

function error_if_duplicates(elements::Vector{DataElement})
    seen = Set{ElementKey}()
    dups = Set{ElementKey}()

    for element in elements
        k = getelkey(element)
        if k in seen
            push!(dups, k)
        else
            push!(seen, k)
        end
    end

    if length(dups) > 0
        display(dups)
        error("Duplicated elkeys")
    end
end

function include_all_elements(elements)
    toplevel = Dict()
    lowlevel = Dict()
    completed = Set()
    dependencies = Dict()

    numelements = length(elements)

    while true
        numbefore = length(completed)

        include_some_elements!(completed, dependencies, toplevel, lowlevel, elements)

        numafter = length(completed)
        
        if numafter == numelements
            return (toplevel, dependencies)
            
        elseif numbefore == numafter
            error_include_all_elements(completed, dependencies)
        end
    end    
end

function include_some_elements!(completed, dependencies, toplevel, lowlevel, elements)
    for element in elements
        elkey = getelkey(element)

        if !(elkey in completed)
            typekey = gettypekey(element)

            if !haskey(INCLUDEELEMENT, typekey)
                error("No INCLUDEELEMENT function for $typekey")
            end

            func = INCLUDEELEMENT[typekey]

            elvalue = getelvalue(element)

            (ok, needed_objkeys) = func(toplevel, lowlevel, elkey, elvalue)

            dependencies[elkey] = needed_objkeys

            ok && push!(completed, elkey)
        end
    end
end

function error_include_all_elements(completed, dependencies)
    (errors, dependencies) = parse_error_dependencies(dependencies, elements)
    messages = root_causes(dependencies, errors, completed)
    msg = join(messages, "\n")
    msg = "Found $(length(messages)) errors:\n$msg"
    error(msg)
end

function parse_error_dependencies(dependencies, elements)
    (errors, dependencies) = split_dependencies(dependencies)
    dependencies = objkeys_to_elkeys(dependencies, elements)
    return (errors, dependencies)
end

function split_dependencies(dependencies)
    errs = Dict{ElementKey, Vector{String}}()
    deps = Dict{ElementKey, Vector{Id}}()
    for (elkey, d) in dependencies
        if d isa Tuple
            (error_messages, id_vector) = d
            errs[elkey] = error_messages
            deps[elkey] = id_vector
        else
            deps[elkey] = d
        end
    end
    return (errs, deps)
end

function objkeys_to_elkeys(dependencies, elements)
    d = Dict{ElementKey, Vector{ElementKey}}()
    m = Dict{Id, ElementKey}()
    for e in elements
        m[Id(e.conceptname, e.instancename)] = getelkey(e)
    end
    for (k, id_vector) in dependencies
        d[k] = ElementKey[m[id] for id in id_vector]
    end
    return d
end

function root_causes(dependencies, errors, completed)
    failed = Set(k for k in keys(dependencies) if !(k in completed))
    roots = Set(k for k in failed if does_not_depend_on_failed(k, dependencies, failed))
    return error_messages(dependencies, errors, completed, failed, roots)
end

function does_not_depend_on_failed(k, dependencies, failed)
    for j in get(dependencies, k, ElementKey[])
        if j in failed
            return false
        end
    end
    return true
end

function error_messages(dependencies, errors, completed, failed, roots)
    messages = String[]
    for k in failed
        if haskey(errors, k)
            for s in errors[k]
                push!(messages, s)
            end
        end
    end
    for k in roots
        missing_deps = [d for d in get(dependencies, k, ElementKey[]) if !(d in completed)]
        if length(missing_deps) > 1
            for d in missing_deps
                s = "Element $k may have failed due to missing dependency $d"
                push!(messages, s)
            end
        elseif length(missing_deps) == 1
            d = missing_deps[1]
            s = "Element $k failed due to missing dependency $d"
            push!(messages, s)
        else
            if !haskey(errors, k)
                s = "Element $k failed due to unknown reason"
                push!(messages, s)
            end
        end
    end
    return messages
end

function assemble!(modelobjects::Dict)
    completed = Set()
    while true
        numbefore = length(completed)

        for obj in values(modelobjects)
            id = getid(obj)
            if !(id in completed)
                ok = assemble!(obj)
                ok && push!(completed, id)
            end
        end

        numafter = length(completed)

        if length(modelobjects) == numafter
            return modelobjects

        elseif numbefore == numafter
            # TODO: Change all assemble! to support better error messages (same idea as in include_some_elements!)
            error("Some objects could not be made")

        end
    end
end

function compact_dependencies(dependencies::Dict{ElementKey, Vector{Id}}, elements)
    dependencies = objkeys_to_elkeys(dependencies, elements)
    ix_map = Dict(getelkey(e) => i for (i, e) in enumerate(elements))
    out = Dict{ElementKey, Vector{Int}}()
    for (k, elkeys) in dependencies
        out[k] = sort([ix_map[j] for j in elkeys])
    end
    return out
end
