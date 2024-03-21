"""
Description of the input system in TuLiPa.

Why data elements and model objects:
    TuLiPa is a for creating model objects that work well with LP problems. 
    To work well with LP problems, model objects tend to have a complicated 
    nested structure with a lot of shared lowlevel objects. While such nested 
    structure is good for LP problems, we found it too complicated to be used 
    by end users to create datasets. We want such a end user system to be 
    extensible, composable and modular, and this suggests to use a flat 
    structure instead of a nested one. The solution we arrived at was to have 
    an data elements with a very flat structure, and a compiler 
    (the getmodelobjects function) that would transform simple data elements 
    into the complicated and nested model objects.

Nice properties of data elements:
    The flat structure of data elements have some nice properties. For once, 
    we find it relatively easy to port datasets from other sources. Another 
    nice property is that since a dataset is just a Vector{DataElement}, 
    it is easy to store parts of a dataset in different files and merge them 
    together when needed. E.g. we have aggregated and detailed versions of 
    our hydropower dataset and can easily swich between these without 
    having to modify other parts of the dataset. 

In short, the system works like this: 
    The getmodelobjects function takes a Vector{DataElement}, use functions 
    stored in the INCLUDEELEMENT function registry to handle data elements 
    representing different types, and finally puts everything together and 
    returns a Dict{Id, Any} of model objects. 

You can extend the system:
    The getmodelobjects function can only handle data elements that are 
    registered in the INCLUDEELEMENT function registry. We have added 
    getmodelobjects support to all objects defined in TuLiPa that makes 
    sense to store in a end user dataset. See timevectors.jl or obj_balance.jl 
    for some examples of functions stored in INCLUDEELEMENT. The system is 
    extensible. End users can define new model objects, and add getmodelobjects 
    support to them by defining an appropriate function and store it the
    INCLUDEELEMENT function registry.

The impotance of the INCLUDEELEMENT function registry:
    It is very important that the functions stored in INCLUDEELEMENT have a 
    particular signature and behaviour. If not, the getmodelobjects will fail, 
    or even worse, silently return errouneous results. Fortunately, it is not too 
    hard to define compliant INCLUDEELEMENT functions. The next section explanins 
    the INCLUDEELEMENT function interface. 

The INCLUDEELEMENT function interface:
    Usage:
    You define new model object (M) and an appropriate function (f). Methods to f 
    implicitly define data element (E) and ways transform E to M. You then register 
    f in the INCLUDEELEMENT function registry. Now, the getmodelobjects function 
    will be able to use f to create M from E. 

    Signature:
    An INCLUDEELEMENT function (f) should have the following signature:
        (ok, deps) = f(toplevel, lowlevel, elkey, value)
    With possible types:
        ok::Bool
        deps::Vector{Id}
        deps::Tuple{Vector{String}, Vector{Id}}
        toplevel::Dict{Id, Any}
        lowlevel::Dict{Id, Any}
        elkey::ElementKey
        value::Any

    Naming: 
    You can name INCLUDEELEMENT functions (f in above signature) however you want, 
    but we use the convention:
            include + [object type] + ! 
    to name such functions in TuLiPa (e.g. includeInfiniteTimeVector!).

    On the behaviour of an INCLUDEELEMENT function:
    - Should return all possible dependencies, also when f returns 
      early with ok=false

    - Should validate dependencies and throw useful errors

    - If ok=false for other reasons than missing dependencies, 
      return dependencies with type Tuple{Vector{String}, Vector{Id}}, 
      where the Vector{String} part is error messages explaining what went wrong. 
      (The first part is the usual vector with all possible dependencies.) 
      Most INCLUDEELEMENT functions does not need this, but some do. 
      For an example, see the definition of includeHydroRamping! in the 
      file trait_ramping.jl.

    - Should either modify lowlevel, toplevel or both. One example could be 
      to create and object and store it in either lowlevel 
      (see e.g. includeInfiniteTimeVector!) or toplevel 
      (see e.g. includeBaseBalance!). Another example could be to create
      an object and store it in an existing toplevel object 
      (see e.g. includePositiveCapacity!). 
      A final example could be to create an object
      and both store it into an an existing toplevel object, 
      and store the object itself in e.g. lowlevel (see e.g. includeBaseRHSTerm!).

    Registration: 
    To register a function (f) in the INCLUDEELEMENT registry, add this line to 
    the source file below the definitions of your model object and the function f:
        INCLUDEELEMENT[TypeKey("YourConceptName", "YourTypeName")] = f
    Where: 
        "YourConceptName" should be the concept name your model object
        belongs to (e.g. "Flow" or "TimeVector"). 
        "YourTypeName" should be the concrete type of your model object
        (e.g. "BaseFlow" or "InfiniteTimeVector"). 
    In TuLiPa, we usually define INCLUDEELEMENT functions and register them at 
    the bottom of source files (see e.g. timevectors.jl).

Other notes that may be useful:
- Some data elements re-use existing types 
  (e.g. OneYearTimeVector in timevectors.jl)
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

# to have more readable signatures
const ElementIx = Int

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
validate_modelobjects(modelobjects::Dict{Id, Any}) = nothing

function assemble!(modelobjects::Dict{Id, Any})
    completed = Set{Id}()
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
            error_assemble(modelobjects, completed)
        end
    end
end

function compact_dependencies(dependencies::Dict{ElementKey, Vector{Id}}, elements::Vector{DataElement})
    dependencies = objkeys_to_elkeys(dependencies, elements)
    ix_map = Dict(getelkey(e) => i for (i, e) in enumerate(elements))
    out = Dict{ElementKey, Vector{ElementIx}}()
    for (k, elkeys) in dependencies
        out[k] = sort([ix_map[j] for j in elkeys])
    end
    return out
end

function include_all_elements(elements::Vector{DataElement})
    toplevel = Dict{Id, Any}()
    lowlevel = Dict{Id, Any}()
    completed = Set{ElementKey}()
    dependencies = Dict{ElementKey, Any}()

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

function include_some_elements!(completed::Set{ElementKey}, dependencies::Dict{ElementKey, Any}, toplevel::Dict{Id, Any}, lowlevel::Dict{Id, Any}, elements::Vector{DataElement})
    for element in elements
        elkey = getelkey(element)

        (elkey in completed) && continue

        typekey = gettypekey(element)

        if !haskey(INCLUDEELEMENT, typekey)
            error("No INCLUDEELEMENT function for $typekey")
        end

        func = INCLUDEELEMENT[typekey]

        elvalue = getelvalue(element)

        ret = func(toplevel, lowlevel, elkey, elvalue)
        
        if !(typeof(ret) <: Tuple{Bool, Any})
            error("Unexpected return type for $elkey. Expected <:Tuple{Bool, Any}}, got $(typeof(ret))")
        end

        (ok, needed_objkeys) = ret

        dependencies[elkey] = needed_objkeys

        ok && push!(completed, elkey)
    end
end

# TODO: Change assemble! interface to support better error messages (i.e. informing why assemble failed)?
function error_assemble(modelobjects::Dict{Id, Any}, completed::Set{Id})
    messages = String[]
    for id in keys(modelobjects)
        (id in completed) && continue
        s = "Could not assemble $id"
        push!(messages, s)
    end
    msg = join(messages, "\n")
    msg = "Found $(length(messages)) errors:\n$msg"
    error(msg)
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

function error_include_all_elements(completed::Set{ElementKey}, dependencies::Dict{ElementKey, Any})
    (errors, dependencies) = parse_error_dependencies(dependencies, elements)

    failed = Set{ElementKey}(k for k in keys(dependencies) if !(k in completed))
    root_causes = Set{ElementKey}(k for k in failed if does_not_depend_on_failed(k, dependencies, failed))

    messages = String[]
    for k in failed
        if haskey(errors, k)
            for s in errors[k]
                push!(messages, s)
            end
        end
    end
    for k in root_causes
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

    msg = join(messages, "\n")
    msg = "Found $(length(messages)) errors:\n$msg"

    error(msg)
end

function parse_error_dependencies(dependencies::Dict{ElementKey, Any}, elements::Vector{DataElement})
    (errors, dependencies) = split_dependencies(dependencies)
    dependencies = objkeys_to_elkeys(dependencies, elements)
    return (errors, dependencies)
end

function split_dependencies(dependencies::Dict{ElementKey, Any})
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

function objkeys_to_elkeys(dependencies::Dict{ElementKey, Vector{Id}}, elements::Vector{DataElement})
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

function does_not_depend_on_failed(k::ElementKey, dependencies::Dict{ElementKey, Vector{ElementKey}}, failed::Set{ElementKey})
    if haskey(dependencies, k)
        for elkey in dependencies[k]
            if elkey in failed
                return false
            end
        end
    end
    return true
end
