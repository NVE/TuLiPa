"""
Description of the input system in TuLiPa.

In short, the system works like this: 
    The getmodelobjects function takes a Vector{DataElement} as input, 
    use functions stored in the INCLUDEELEMENT function registry to 
    handle data elements representing different types, and finally puts 
    everything together and returns a Dict{Id, Any} of model objects. 

Why data elements and model objects:
    To work well with LP problems, model objects tend to have a complicated 
    nested structure with a lot of shared lowlevel objects. While such nested 
    structure is good for LP problems, we found it too complicated to be used 
    by end users to create datasets. We wanted an input system that was 
    extensible, composable and modular, and this suggested to use a flat 
    structure instead of a nested one. 

Some nice properties of data elements:
    Easy to port datasets from other sources. Since data elements are small
    and use references to other data elements, it is usually a matter of 
    looping over objects in the source, create needed data elements 
    and add them as you go.

    Easy to store dataset in replaceable parts. E.g. have different 
    hydropower datasets with different aggregation levels.
    E.g. have exogeneous or endogenous represenation of the 
    continental power system.
    
    Easy to add functionality. E.g. give an existing Flow element 
    SoftBound constraint by adding SoftBound data elements referring 
    to the Flow element. E.g. replace BaseArrow with SegmentedArrow
    to model PQ-curves for an existing Flow element.

We have already added INCLUDEELEMENT functions to many objects:
    We have added INCLUDEELEMENT functions to all objects defined in TuLiPa 
    that makes sense to store in a end user dataset. See timevectors.jl 
    or obj_balance.jl for some examples of functions stored in INCLUDEELEMENT.         

But you can extend the system:
    You can define new objects and add getmodelobjects support to them by 
    defining an appropriate function and store it the INCLUDEELEMENT 
    function registry.

INCLUDEELEMENT functions must behave a certain way:
    It is very important that the functions stored in INCLUDEELEMENT have a 
    particular signature and behaviour. If not, the getmodelobjects function
    will fail, or even worse, silently return errouneous results. Fortunately, 
    it is not too hard to define compliant INCLUDEELEMENT functions. The next 
    section explanins the INCLUDEELEMENT function interface. 

The INCLUDEELEMENT function interface:
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
      (see e.g. includeInfiniteTimeVector! in timevectors.jl) or toplevel 
      (see e.g. includeBaseBalance! in obj_balance.jl). Another example could be to create
      an object and store it in an existing toplevel object 
      (see e.g. includePositiveCapacity! in trait_capacity.jl). 
      A final example could be to create an object
      and both store it into an an existing toplevel object, 
      and store the object itself in e.g. lowlevel 
      (see e.g. includeBaseRHSTerm! in trait_rhsterm.jl).

    Registration: 
    To register a function (f) in the INCLUDEELEMENT registry, add this line to 
    the source file below the definitions of your model object and the function f:
        INCLUDEELEMENT[TypeKey("YourConceptName", "YourTypeName")] = f
    Where: 
        "YourConceptName" should be the concept name your model object
        belongs to (e.g. "Flow" or "TimeVector"). Note, it must not be an
        existing concept. You can create a new concept as well.
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

"""
Compiles data elements into model objects. 

Inputs:
  elements::Vector{DataElement}

Optional keyword arguments:
  validate::Bool - true by default. If true we call the validate_modelobjects 
                   function on modelobjects before returning

  deps::Bool - false by default. When true, we return (modelobjects, dependencies)
               where dependencies::Dict{ElementKey, Vector{Int}} containing
               information about which indices in elements are direct dependencies
               of elements. This can be used to identify all elements belonging to
               a subset of data elements or model objects. E.g. we use til to find
               all data elements belonging to model objects in a storage system. 

"""
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

function compact_dependencies(dependencies::Dict{ElementKey, Any}, elements::Vector{DataElement})
    (errors, dependencies, missings) = split_dependencies(dependencies, elements)

    @assert all(length(x) == 0 for x in values(missings))
    @assert all(length(x) == 0 for x in values(errors))

    ix_map = Dict(getelkey(e) => i for (i, e) in enumerate(elements))

    out = Dict{ElementKey, Vector{Int}}()
    for (k, elkeys) in dependencies
        out[k] = sort([ix_map[j] for j in elkeys])
    end

    return out
end

# function get_deep_dependencies(elements, direct_dependencies; concepts::Union{Nothing, Vector{String}} = nothing)
#     refs = get_referenced_by(elements, direct_dependencies)
#     d = Dict{eltype(elements), Set{Int}}()
#     for e in elements
#         seen = Set{Int}()
#         update_deep_dependencies(d, e, elements, direct_dependencies, seen, refs, concepts)
#     end
#     for (i, e) in enumerate(elements)
#         push!(d[e], i)
#     end
#     return Dict(k => sort(collect(v)) for (k, v) in d)
# end
 
# function update_deep_dependencies(d, e, elements, direct_dependencies, seen, refs, concepts)
#     deep_dependencies = Set{Int}()
#     for i in direct_dependencies[getelkey(e)]
#         for j in get_candidates(i, elements, refs, concepts)
#             if j in seen
#                 continue
#             else
#                 push!(seen, j)
#             end
#             dep = elements[j]
#             if !haskey(d, dep)
#                 update_deep_dependencies(d, dep, elements, direct_dependencies, seen, refs, concepts)
#             end
#             push!(deep_dependencies, j)
#             for k in d[dep]
#                 push!(deep_dependencies, k)
#             end
#         end
#     end
#     d[e] = deep_dependencies
#     return
# end
 
# function get_referenced_by(elements, direct_dependencies)
#     d = Dict{eltype(elements), Set{Int}}()
#     ei = Dict(getelkey(e) => i for (i, e) in enumerate(elements))
#     for (e, direct_deps) in direct_dependencies
#         i = ei[e]
#         for j in direct_deps
#             if !haskey(d, elements[j])
#                 d[elements[j]] = Set{Int}()
#             end
#             push!(d[elements[j]], i)
#         end
#     end
#     return d
# end
 
# function get_candidates(i, elements, refs, concepts)
#     candidates = Set{Int}([i])
#     if isnothing(concepts)
#         for j in refs[i]
#             push!(candidates, j)
#         end
#     else
#         for j in refs[elements[i]]
#             if elements[j].conceptname in concepts
#                 push!(candidates, j)
#             end
#         end
#     end
#     return candidates
# end

function get_deep_dependencies(elements, direct_dependencies)
    d = Dict{eltype(elements), Set{Int}}()
    for e in elements
        seen = Set{Int}()        
        update_deep_dependencies(e, d, elements, direct_dependencies, seen)
    end
    for (i, e) in enumerate(elements)
        push!(d[e], i)
    end
    return Dict(k => sort(collect(v)) for (k, v) in d)
end
 
function update_deep_dependencies(e, d, elements, direct_dependencies, seen)
    deep_dependencies = Set{Int}()
    for i in direct_dependencies[getelkey(e)]
        if (i in seen) || (i > length(elements))
            continue
        else
            push!(seen, i)
        end
        dep = elements[i]
        if !haskey(d, dep)
            update_deep_dependencies(dep, d, elements, direct_dependencies, seen)
        end
        push!(deep_dependencies, i)
        for j in d[dep]
            push!(deep_dependencies, j)
        end
    end
    d[e] = deep_dependencies
    return
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
            error_include_all_elements(completed, dependencies, elements)
        end
    end    
end

function include_some_elements!(completed::Set{ElementKey}, dependencies::Dict{ElementKey, Any}, toplevel::Dict{Id, Any}, lowlevel::Dict{Id, Any}, elements::Vector{DataElement})
    for element in elements
        elkey = getelkey(element)

        (elkey in completed) && continue

        typekey = gettypekey(element)

        error_if_unknown_element_type(typekey)

        func = INCLUDEELEMENT[typekey]

        elvalue = getelvalue(element)

        ret = func(toplevel, lowlevel, elkey, elvalue)

        error_if_unexpected_return_type(ret, elkey)

        (ok, needed_objkeys) = ret

        # important to store this every iteration because
        # needed_objkeys can change between iterations
        dependencies[elkey] = needed_objkeys

        ok && push!(completed, elkey)
    end
end

function error_if_unknown_element_type(typekey)
    if !haskey(INCLUDEELEMENT, typekey)
        error("No INCLUDEELEMENT function for $typekey")
    end
end

function error_if_unexpected_return_type(ret, elkey::ElementKey)
    if !(typeof(ret) <: Tuple{Bool, Any})
        s1 = "Unexpected INCLUDEELEMENT function return type for\n$elkey\n"
        s2 = "Expected T <: Tuple{Bool, Any}}, got $(typeof(ret))."
        msg = string(s1, s2)
        error(msg)
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
    n = length(messages)
    s = n > 1 ? "s" : ""
    msg = join(messages, "\n")
    msg = "Found $n error$s:\n$msg"
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
        lines = join(dups, "\n -> ")
        msg = "Found duplicated elkeys:\n$lines"
        error(msg)
    end
end

function error_include_all_elements(completed::Set{ElementKey}, dependencies::Dict{ElementKey, Any}, elements::Vector{DataElement})
    (errors, dependencies, missings) = split_dependencies(dependencies, elements)

    assert_all_elkeys_in_dependencies(dependencies, elements)

    failed = Set{ElementKey}(k for k in keys(dependencies) if !(k in completed))

    root_causes = Set{ElementKey}(k for k in failed if does_not_depend_on_failed(k, dependencies, failed))

    messages = String[]

    known_cause = Set{ElementKey}()

    for (k, m_vec) in errors
        length(m_vec) > 0 || continue
        for m in m_vec
            push!(messages, m)
        end
        push!(known_cause, k)
    end

    reportable_missings = Set{Id}()
    for (k, id_vec) in missings
        (k in root_causes) || continue
        length(id_vec) > 0 || continue
        for id in id_vec
            push!(reportable_missings, id)
        end
        push!(known_cause, k)
    end
    for id in reportable_missings
        m = "Missing element $id"
        push!(messages, m)
    end

    for k in root_causes
        (k in known_cause) && continue
        m = "$k failed due to unknown reason (not missing dependency)"
        push!(messages, m)
    end

    messages = [string(" -> ", m) for m in messages]

    msg = join(messages, "\n")
    n = length(messages)
    f = length(failed)
    e = length(elements)
    ns = (n > 1) ? "s" : ""
    fs = (f > 1) ? "s" : ""
    es = (e > 1) ? "s" : ""
    msg = "Failed to compile $f element$fs (of $e element$es in total). Found $n root cause$ns:\n$msg\n"

    error(msg)
end

"""
Added because the dependency system relies on this assumption
being true, and we want to get failing tests if we in the
future make changes that violate this assumption.
"""
function assert_all_elkeys_in_dependencies(dependencies, elements)
    E = Set{ElementKey}()
    for e in elements
        push!(E, getelkey(e))
    end
    D = Set(keys(dependencies))
    @assert E == D
end

function split_dependencies(dependencies::Dict{ElementKey, Any}, elements::Vector{DataElement})
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

    (deps, missings) = objkeys_to_elkeys(deps, elements)

    return (errs, deps, missings)
end

function objkeys_to_elkeys(dependencies::Dict{ElementKey, Vector{Id}}, elements::Vector{DataElement})
    elkey_dependencies = Dict{ElementKey, Vector{ElementKey}}()
    missing_ids = Dict{ElementKey, Vector{Id}}()

    id_to_elkey = Dict{Id, ElementKey}()
    for e in elements
        id = Id(e.conceptname, e.instancename)
        id_to_elkey[id] = getelkey(e)
    end

    for (k, id_vector) in dependencies
        missing_vec = Id[]
        elkey_vec = ElementKey[]
        for id in id_vector
            if haskey(id_to_elkey, id)
                elkey = id_to_elkey[id]
                push!(elkey_vec, elkey)
            else
                push!(missing_vec, id)
            end
        end
        elkey_dependencies[k] = elkey_vec
        missing_ids[k] = missing_vec
    end

    return (elkey_dependencies, missing_ids)
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

# TODO: Rule out empty balance objects
# TODO: Add more stuff
function validate_modelobjects(modelobjects::Dict{Id, Any})
    nothing
end
