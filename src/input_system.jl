"""
Our design goals for the input system:
  Extensible: 
    Users can add their own data elements and model objects.
    Just register an appropriate function for your type
    of object in the INCLUDEELEMENT function registry. 
    Look at already defined types for examples on how to
    do this (e.g. see timevectors.jl)

  Low-memory: 
    Data elements can refer to other data elements. This allow us to
    compile model objects that points to the same data. 
    E.g. several objects can view the same column in a large table 
    with weather profile data.

  Composable: 
    A dataset is just a Vector{DataElement}. It is easy to store parts
    of a dataset in different files and merge them together when needed. 
    E.g. we have aggregated and detailed versions of our hydropower dataset 
    and can easily swich between these without having to modify other 
    parts of the dataset. 

  Modular: 
    Users can change type of object within same concept. 
    Add new behaviour with minimal changes to a dataset.
    E.g. Replace a BaseArrow with a SegmentedArrow to 
    give a Flow new behaviour.

In this file we define:
- The DataElement type, related key types and functions on these
- The INCLUDEELEMENT function registry used by the getmodelobjects function
- The getmodelobjects function, which compiles data elements into model objects

Interface for INCLUDEELEMENT functions (f):
  Function signature:
    (ok, deps) = f(toplevel, lowlevel, elkey, value)
    where:
      ok:
        Bool where true if the data element was successfully included
      deps:
        Vector{Id} or Tuple{Vector{String}, Vector{Id}}. The Vector{Id} part
        is all possible objects that needs to exist in toplevel or lowlevel in order
        to successfully include the element in question. Note that a include-fail may
        list more (possibly) needed objects compared to include-success. This is because 
        there may be several options
            
  Naming convention for function f:
    include + [object name] + !
    (e.g. includeInfiniteTimeVector!)

"""

# ---- The DataElement type, related key types and functions on these ----

struct DataElement
    conceptname::String
    typename::String
    instancename::String
    value::Any
end

struct ElementKey
    conceptname::String
    typename::String
    instancename::String
end

struct TypeKey
    conceptname::String
    typename::String
end

struct Id
    conceptname::String
    instancename::String
end

getinstancename(x::Id) = x.instancename
getconceptname(x::Id) = x.conceptname
getname(x::Id) = "$(x.conceptname)$(x.instancename)"

getobjkey(x::ElementKey) = Id(x.conceptname, x.instancename)
gettypekey(x::ElementKey) = TypeKey(x.conceptname, x.typename)

getelkey(x::DataElement) = ElementKey(x.conceptname, x.typename, x.instancename)
getelvalue(x::DataElement) = x.value
getobjkey(x::DataElement) = Id(x.conceptname, x.instancename)
gettypekey(x::DataElement) = TypeKey(x.conceptname, x.typename)


# ---- The INCLUDEELEMENT function registry used by the getmodelobjects function ----

const INCLUDEELEMENT = Dict{TypeKey, Function}()

# ---- The getmodelobjects function, which compiles data elements into model objects ----

function getmodelobjects(elements::Vector{DataElement}; validate::Bool=true, deps::Bool=false)
    error_if_duplicates(elements)
    (modelobjects, dependencies) = include_all_elements(elements)
    assemble!(modelobjects)
    if validate
        validate_modelobjects(modelobjects)
    end
    if deps
        dependencies = compact_dependencies(dependencies, elements)
        return (modelobjects, dependencies)
    end
    return modelobjects
end

# TODO: Rule out empty balance objects
# TODO: Add more stuff
validate_modelobjects(modelobjects) = nothing

function assemble!(modelobjects::Dict)
    completed = Set()
    while true
        numbefore = length(completed)

        for obj in values(modelobjects)
            id = getid(obj)
            (id in completed) && continue
            ok = assemble!(obj)
            ok && push!(completed, id)
        end

        numafter = length(completed)

        if length(modelobjects) == numafter
            return modelobjects

        elseif numbefore == numafter
            # TODO: Change all assemble! to support better error messages 
            #       (use same idea as in include_some_elements!)
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

        (elkey in completed) && continue

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
        if length(missing_deps) > 0
            for d in missing_deps
                s = "Element $k may have failed due to missing dependency $d"
                push!(messages, s)
            end
        else
            if !haskey(errors, k)
                s = "Element $k failed due to unknown reason"
                push!(messages, s)
            end
        end
    end
    return messages
end
