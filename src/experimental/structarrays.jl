using StructArrays

"""
Convert a nested StructArray into a ZGroup
All propertynames must be Integer or Symbol.
The data can be loaded back with [`read_nested_struct_array!`](@ref)
Any subdata with sizeof(eltype) == 0 will be ignored
"""
function write_nested_struct_array(data::StructArray)::ZGroup
    group = ZGroup()
    for (i, pname) in enumerate(propertynames(data))
        (pname isa Union{Integer,Symbol}) || error("all propertynames must be Integer or Symbol")
        subdata = getproperty(data,pname)
        if subdata isa StructArray
            subgroup = write_nested_struct_array(subdata)
            #note, the group cannot be called string(pname) because it may not be ASCII
            attrs(subgroup)["name"] = string(pname)
            group["$i"] = subgroup
        else
            if sizeof(eltype(subdata)) != 0
                #TODO add compressor options, maybe as some task local context?
                group["$i"] = subdata
                attrs(group["$i"])["name"] = string(pname)
            end
        end
    end
    group
end


"""
load a nested StructArray from a ZGroup into a preallocated StructArray.
The properties saved in the group will over write data in the StructArray with the same propertynames
Loading is based purely on the "name" attribute which will be parsed
as an Int or Symbol property name.
subgroups correspond to a nested StructArray.
"""
function read_nested_struct_array!(data::StructArray, group::ZGroup)
    for child in values(children(group))
        namerepr = attrs(child)["name"]
        !isempty(namerepr) || error("property name empty")
        pname = if isdigit(namerepr[begin]) # Assume property name is an Int
            parse(Int, namerepr)
        else # Assume property name is a symbol
            Symbol(namerepr)
        end
        if child isa ZArray
            newchilddata = getarray(child)
            oldchilddata = getproperty(data,pname)
            axes(newchilddata) == axes(oldchilddata) || error("data is $(axes(data)), ZGroup is $(axes(newchilddata))")
            copy!(oldchilddata,newchilddata)
        elseif child isa ZGroup
            oldchilddata = getproperty(data,pname)
            read_nested_struct_array!(oldchilddata, child)
        else
            error("unreachable") # COV_EXCL_LINE
        end
    end
end