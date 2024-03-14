"""
Here we define the getmodelobjects function, which compiles data elements into model objects.
The parts and steps are describe below:

DataElements: see data_types.jl

INCLUDEELEMENT:
Each data element has an INCLUDEELEMENT function that will include it into lowlevel or toplevel,
or another object in toplevel/lowlevel. Toplevel is a list of objects that will end up in the final 
model object list (i.e. Flow, Balance, SoftBound etc...), while lowlevel is a temporary storage 
of objects that will be put into the toplevel objects (i.e. RHSTerms, Capacity, TimeVector etc...). 
When including an element, first we check if all the dependencies of the data element have been
created (in toplevel or lowlevel). If that is the case, the object will be built (also important to 
validate that all the inputs behave as expected) and put into toplevel, lowlevel or other objects 
inside one of toplevel/lowlevel.

Naming convention: All functions named include + OBJECTNAME + !
    (see for example includePositiveCapacity! in trait_capacity.jl) 

Function signature: 

    (ok, needed_objkeys) = f(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value)
    
    where ok::Bool if true if the object was successfully included, and false if one or more 
    dependencies are missing (throw error for other types of failure, such as validation failures)
    
    needed_objkeys is a Vector{Id} containing all objects that the function needs in order
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
           (such as validation failures) should throw errors.


getmodelobjects() consist of 3 elements:

    check_duplicates(elements)
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

TODO: Better error messages
TODO: This description is messy?
"""


INCLUDEELEMENT = Dict()

# TODO: Complete
# To have better error messages
ELEMENTFAILED  = Dict()

# Limit error output
MAXPRINTERRORS = 10000

function getmodelobjects(elements::Vector{DataElement}; validate::Bool=true, deps=false)
    validate == true && validate_elements(elements)
    check_duplicates(elements)
    modelobjects = include_all_elements(elements)
    assemble!(modelobjects)
    return modelobjects
end

function check_duplicates(elements::Vector{DataElement})
    seen = Set{DataElement}()
    dups = Set{DataElement}()

    for element in elements
        k = getelkey(element)
        if k in seen
            push!(seen, k)
        else
            push!(dups, k)
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

    numelements = length(elements)

    while true
        numbefore = length(completed)

        include_some_elements!(completed, toplevel, lowlevel, elements)

        numafter = length(completed)
        
        if numafter == numelements
            return toplevel
            
        elseif numbefore == numafter
            msg = build_error_message(completed, toplevel, lowlevel, elements)
            error(msg)
        end
    end    
end

function include_some_elements!(completed, toplevel, lowlevel, elements)
    INCLUDEELEMENT::Dict

    for element in elements

        elkey = getelkey(element)

        if !(elkey in completed)
            typekey = gettypekey(element)

            if !haskey(INCLUDEELEMENT, typekey)
                error("No INCLUDEELEMENT function for $typekey")
            end

            func = INCLUDEELEMENT[typekey]

            elvalue = getelvalue(element)

            ok = func(toplevel, lowlevel, elkey, elvalue)

            ok && push!(completed, elkey)
        end
    end
end

function build_error_message(completed, toplevel, lowlevel, elements)
    MAXPRINTERRORS::Int

    errors = Dict()

    numshow = MAXPRINTERRORS #min(MAXPRINTERRORS, length(errors))

    numelements = length(elements)

    numfailed = add_good_error_messages!(errors, numshow, completed, toplevel, lowlevel, elements)

    numfailed += maybe_add_some_default_error_messages!(errors, numshow, elements, completed)

    msg = join(values(errors), "\n")

    msg = "Failed to include $numfailed of $numelements elements (showing $numshow):\n$msg"

    return msg
end

function add_good_error_messages!(errors, numshow, completed, toplevel, lowlevel, elements)
    ELEMENTFAILED::Dict

    numfailed = 0

    for element in elements
        elkey = getelkey(element)

        if !(elkey in completed)
        
            typekey = gettypekey(element)

            if (length(errors) < numshow) && haskey(ELEMENTFAILED, typekey)
                numfailed += 1
                func = ELEMENTFAILED[typekey]
                elvalue = getelvalue(element)
                msg = func(toplevel, lowlevel, elkey, elvalue)
                errors[elkey] = msg
            end

        end

        if length(errors) == numshow
            break
        end                
    end
    return numfailed
end

function maybe_add_some_default_error_messages!(errors, numshow, elements, completed)
    numfailed = 0

    if length(errors) < numshow
        for element in elements

            elkey = getelkey(element)

            if !(elkey in completed) && !(elkey in keys(errors))
                numfailed += 1
                msg = "Failed to include $elkey"
                errors[elkey] = msg
            end

            if length(errors) == numshow
                break
            end

        end
    end

    return numfailed
end

function assemble!(modelobjects::Dict)
    completed = Set()
    while true
        numbefore = length(completed)

        for obj in values(modelobjects)
            if !(getid(obj) in completed)
                ok = assemble!(obj)
                ok && push!(completed, getid(obj))
            end
        end

        numafter = length(completed)

        if length(modelobjects) == numafter
            return modelobjects

        elseif numbefore == numafter
            # TODO: Better error message
            error("Some objects could not be made")

        end
    end
end

function elements_to_df(elements)
    return DataFrame(
        conceptname=[e.conceptname for e in elements], 
        typename=[e.typename for e in elements], 
        instancename=[e.instancename for e in elements], 
        value = [e.value for e in elements]
    )
end

function add_extra_col(df)
    function add_dict_as_columns(df_input)
        df_dict = DataFrame()
        for d in df_input
            df_dict = vcat(df_dict, DataFrame(d))
        end
        return df_dict
    end
    df_extra = hcat(df, add_dict_as_columns(df.value))
    return select!(df_extra, Not(:value))
end

function check_ref(all_instancenames, type_df, col)
    # fields that are strings but not reference
    if (col in ["conceptname", "instancename", 
                "typename", "Residualhint", 
                "Name", "Direction", 
                "WhichConcept", "value_type", 
                "Bound"])
        return
    end
    reference_does_not_exist = .!in.(type_df[!, col], Ref(all_instancenames))
    no_refs = type_df[reference_does_not_exist, :]
    
    # since instancename is not unique at this point (should be?) 
    # some dataelements could reference elements with same name
    # this prevents it to be validated if it references itself
    no_refs = no_refs[no_refs[!, col] .!= no_refs.instancename, :]
    
    if ~isempty(no_refs)
        return (col, no_refs)
    end
    return nothing
end

function validate_refrences(df)
    all_instancenames = Set(df.instancename)
    df = df[typeof.(df.value) .== Dict{Any, Any}, :]
    df[!, "value"] = _remove_non_string_dict_values.(df.value)
    df[!, "value_type"] = join.(sort.(collect.((keys.(df.value)))))
    missing_refs = []
    for value_type in unique(df.value_type)
        type_df = add_extra_col(df[df.value_type.==value_type, :])
        for col in names(type_df)
            refs = check_ref(all_instancenames, type_df, col)
            if !isnothing(refs)
                push!(missing_refs, refs)
            end
        end
    end
    return missing_refs
end

function _remove_non_string_dict_values(element_value::Dict)
    value = copy(element_value)
    for (key, val) in value
        if typeof(val) != String
            delete!(value, key)
        end
    end
    return value
end

function validate_elements(elements)
    df = elements_to_df(elements)
    checks = validate_refrences(df)
    errors = false
    for check in checks
        if size(check[2])[1] == 0
            continue
        end
        for element in eachrow(check[2])
            println("Missing instancename referenced by $(element["instancename"])($(element["conceptname"]))")
            println("$(element[check[1]]) was not found in data elements")
            errors = true
        end
    end
    if errors
        error("Found data elements problems")
    end
end
