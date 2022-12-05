"""
The DataElement type we use
"""

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

# To implement DataElement interface 
getelkey(x::DataElement) = ElementKey(x.conceptname, x.typename, x.instancename)

getelvalue(x::DataElement) = x.value

getobjkey(x::DataElement) = Id(x.conceptname, x.instancename)

gettypekey(x::DataElement) = TypeKey(x.conceptname, x.typename)

getobjkey(x::ElementKey) = Id(x.conceptname, x.instancename)
gettypekey(x::ElementKey) = TypeKey(x.conceptname, x.typename)

