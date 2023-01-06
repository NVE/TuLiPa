"""
The DataElement type we use has:
- Conceptname which is the abstract type of the element
- Typename which is the concrete type of the element
- Instancename which is the unique name of the element
- Value which is the information the element holds. A dictionary in our datasets

The data elements are stored in a flat structure where each data element
holds its information and possibly references to other dataelements 
they are linked to (for example can an upper capacity hold references 
to its parameter (stored in another data element), and references to 
the variable this upper capacity should be included in 
(see data_elements_to_objects.jl)).
"""

struct DataElement
    conceptname::String
    typename::String
    instancename::String
    value::Any # TODO: Change to data
end

# Different keys
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

# ID interface
getinstancename(x::Id) = x.instancename
getconceptname(x::Id) = x.conceptname
getname(x::Id) = "$(x.conceptname)$(x.instancename)" 

# ElementKey interface
getobjkey(x::ElementKey) = Id(x.conceptname, x.instancename)
gettypekey(x::ElementKey) = TypeKey(x.conceptname, x.typename)

# Dataelement interface
getelkey(x::DataElement) = ElementKey(x.conceptname, x.typename, x.instancename)
getelvalue(x::DataElement) = x.value
getobjkey(x::DataElement) = Id(x.conceptname, x.instancename)
gettypekey(x::DataElement) = TypeKey(x.conceptname, x.typename)

function getelement(elements::Vector{DataElement},instancename::String)
    for element in elements
        element.instancename == instancename && return element
    end
    display(instancename)
    error("Element not in list")
end

# Functions to read dataset stored in JSON as a list of tuples (after JSON.parsefile())
# TODO: Make more robust
# TODO: Assumes datetime format...
function getelements(tupleelements::Vector{Any}, path="")
    elements = DataElement[]
    for element in tupleelements
        push!(elements, getelement(element...; path))
    end
    return elements
end

function getelement(concept, concrete, instance, pairs...; path="") # should be adapted to dataset
    d = Dict()
    for (k, v) in pairs
        if concrete == "VectorTimeIndex"
            v = [DateTime(i,dateformat"yyyy-mm-dd HH:MM:SS") for i in v]
        elseif (concrete == "RangeTimeIndex") & (k == "Start")
            v = DateTime(v,dateformat"yyyy-mm-dd HH:MM:SS")
        elseif concrete == "VectorTimeValues"
            v = v |> Vector{Float64}
        elseif (concrete == "BaseTable") & (k == "Matrix")
            v = CSV.read(joinpath(path, v), header=0, DataFrame) |> Matrix{Float64} # read csv
        elseif (concrete == "BaseTable") & (k == "Names")
            v = v |> Vector{String}
        elseif (k == "Period") | (k == "NumPeriods") | (k == "Steps") # BaseHorizon and MsTimeDelta and RangeTimeIndex and storagehint
            v = v |> Int64    
        elseif v isa Int
            v = v |> Float64
        end
        d[k] = v
    end
    return DataElement(concept, concrete, instance, d)
end







