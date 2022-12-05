# Here we define the getmodelobjects function, which compiles data elements into model objects

# Function registers
#   Naming convention: All functions named include + OBJECTNAME + !
#
#   Function signature: 
#     f(toplevel::Dict, lowlevel::Dict, elkey::ElementKey, value)::Bool
#
#   Intended behavior: 
#     1) Should include some element by modifying either toplevel or lowlevel
#     2) Should return as early as possible
#     3) Should validate inputs and give good error messages 
INCLUDEELEMENT = Dict()

# TODO: Complete
# To have better error messages
ELEMENTFAILED  = Dict()

# Limit error output
MAXPRINTERRORS = 10000

function getmodelobjects(elements::Vector{DataElement})
    check_duplicates(elements)
    
    modelobjects = include_all_elements(elements)

    assemble!(modelobjects)

    return modelobjects
end

function check_duplicates(elements)
    function nonunique(v)
        seen = Dict{eltype(v), Ref{Int}}()
        [x for x in v if 2 == (get!(()->Ref(0), seen, x)[]+=1)]
    end
    
    all = Vector()

    for element in elements
        elkey = getelkey(element)
        push!(all,elkey)
    end

    duplicates = nonunique(all)
    if length(duplicates) > 0
        display(duplicates)
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
            ok = assemble!(obj)
            ok && push!(completed, getid(obj))
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
