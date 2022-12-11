# Convert between julia and numpy type descriptions.

using ArgCheck
using StaticArrays
using StaticStrings


"""
Convert a basic zarr typestr to its endianness, and julia type.
"""
function typestr_to_julia_type(typestr::String)::Tuple{Char, Type}
    byteorder = typestr[1]
    typechar = typestr[2]
    # note need to strip non digits because of datetime units
    # This is usually the number of bytes, but if typechar is 'U' it is number of bytes/4 for some stupid reason.
    numthings = Parse(Int,rstrip(!isdigit, typestr[3:end]))
    units = lstrip(isdigit, typestr[3:end])[begin+1:end-1]
    @argcheck byteorder in "<>|"
    @argcheck typechar in "biufcmMSUV"
    @argcheck numthings ≥ 0
    @argcheck typechar in "mM" ⊻ isempty(units)
    @argcheck units in ("","Y","M","W","D","h","m","s","ms","μs","us","ns","ps","fs","as")
    # normalized byte order, | if possible.
    normbyteorder::Char = byteorder
    # actual number of bytes
    numbytes::Int64 = numthings
    julia_type::Type = if typechar == 'b'
        @argcheck numthings == 1
        normbyteorder = '|'
        Bool
    elseif typechar == 'i'
        @argcheck numthings in 1:8
        @argcheck count_ones(numthings) == 1
        @argcheck byteorder in "<>" || isone(numthings)
        normbyteorder = numthings == 1 ? '|' : byteorder
        (Int8, Int16, Int32, Int64)[trailing_zeros(numthings)+1]
    elseif typechar == 'u'
        @argcheck numthings in 1:8
        @argcheck count_ones(numthings) == 1
        @argcheck byteorder in "<>" || isone(numthings)
        normbyteorder = numthings == 1 ? '|' : byteorder
        (UInt8, UInt16, UInt32, UInt64)[trailing_zeros(numthings)+1], byteorder, numthings
    elseif typechar == 'f'
        @argcheck numthings in 2:8
        @argcheck count_ones(numthings) == 1
        @argcheck byteorder in "<>"
        (Float16, Float32, Float64)[trailing_zeros(numthings)]
    elseif typechar == 'c'
        @argcheck numthings in 4:16
        @argcheck count_ones(numthings) == 1
        @argcheck byteorder in "<>"
        (ComplexF16, ComplexF32, ComplexF64)[trailing_zeros(numthings)-1]
    elseif typechar == 'm'
        @argcheck byteorder in "<>"
        @argcheck numthings == 8
        @warn "timedelta64 not supported, converting to Int64"
        Int64
    elseif typechar == 'M'
        @argcheck byteorder in "<>"
        @argcheck numthings == 8
        @warn "datatime64 not supported, converting to Int64"
        Int64
    elseif typechar == 'S'
        normbyteorder = '|'
        StaticString{numthings}
    elseif typechar == 'U'
        @argcheck byteorder in "<>"
        numbytes = numthings*4
        NTuple{numthings, Char}
    elseif typechar == 'V'
        normbyteorder = '|'
        NTuple{numthings, UInt8}
    end
    normbyteorder, julia_type
end

"""
Convert a structured data type to a NamedTuple.

The nodes are NamedTuple, and the leaves are basic types, 
or SArrays of basic types.
"""
function descr_to_julia_type(descr)::NamedTuple
    
end


