"""
The DataElement type we use
"""

struct Element <: DataElement
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

# To implement DataElement interface 
getelkey(x::Element) = ElementKey(x.conceptname, x.typename, x.instancename)

getelvalue(x::Element) = x.value

getobjkey(x::Element) = Id(x.conceptname, x.instancename)

gettypekey(x::Element) = TypeKey(x.conceptname, x.typename)

getobjkey(x::ElementKey) = Id(x.conceptname, x.instancename)
gettypekey(x::ElementKey) = TypeKey(x.conceptname, x.typename)

