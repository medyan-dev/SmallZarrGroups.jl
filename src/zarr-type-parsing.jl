# Parse zarr type descriptions.

using ArgCheck
using StaticArrays
using StaticStrings

"Usually 8, maybe this could be 4 on a 32 bit machine?"
const DOUBLE_ALIGN = (sizeof(Tuple{Float64,Int8}) == 16) ? 3 : 2

const ALIGNMENT_LOOKUP = (0, 1, 2, DOUBLE_ALIGN) 

"Character for native byte order"
const NATIVE_ORDER = ENDIAN_BOM == 0x04030201 ? '<' : '>'



Base.@kwdef struct ParsedType
    "Julia type that this type represents. This must be an isbits type"
    julia_type::Type

    "Number of bytes julia type takes."
    julia_size::Int64

    "Number of bytes the type takes up in zarr.
    This can differ from `julia_size` because in zarr structs are packed,
    In Julia structs are aligned. See:
    https://en.wikipedia.org/wiki/Data_structure_alignment"
    zarr_size::Int64 = julia_size

    "How bytes should be copied from the zarr type to the julia type.
    Has length equal to `zarr_size`"
    byteorder::Vector{Int64}

    "Alignment requirements for this type:
    0 is 1 byte, 1 is 2 byte, 2 is 4 byte, 3 is 8 byte"
    alignment::Int

    "`zarr_size == julia_size && byteorder == 1:julia_size`"
    just_copy::Bool
end

function Base.:(==)(a::ParsedType, b::ParsedType)
    all(x->isequal(x...), ((getfield(a, k),getfield(b, k)) for k ∈ fieldnames(ParsedType)))
end

"""
Parse a basic zarr typestr.
"""
function parse_zarr_type(typestr::String)::ParsedType
    byteorder = typestr[1]
    typechar = typestr[2]
    # note need to strip non digits because of datetime units
    # This is usually the number of bytes, but if typechar is 'U' it is number of bytes/4 for some stupid reason.
    numthings = parse(Int,rstrip(!isdigit, typestr[3:end]))
    units = lstrip(isdigit, typestr[3:end])[begin+1:end-1]
    @argcheck byteorder in "<>|"
    @argcheck typechar in "biufcmMSUV"
    @argcheck numthings ≥ 0
    @argcheck (typechar in "mM") ⊻ isempty(units)
    @argcheck units in ("","Y","M","W","D","h","m","s","ms","μs","us","ns","ps","fs","as")
    # actual number of bytes
    if typechar == 'b'
        @argcheck numthings == 1
        return ParsedType(;
            julia_type = Bool,
            julia_size = 1,
            byteorder = [1],
            alignment = 0,
            just_copy = true,
        )
    elseif typechar == 'i'
        @argcheck numthings in 1:8
        @argcheck count_ones(numthings) == 1
        @argcheck (byteorder in "<>") || isone(numthings)
        in_native_order = (byteorder == NATIVE_ORDER) || isone(numthings)
        tz = trailing_zeros(numthings)
        return ParsedType(;
            julia_type = (Int8, Int16, Int32, Int64)[tz+1],
            julia_size = numthings,
            byteorder = in_native_order ? (1:numthings) : (numthings:-1:1),
            alignment = ALIGNMENT_LOOKUP[tz+1],
            just_copy = in_native_order,
        )
    elseif typechar == 'u'
        @argcheck numthings in 1:8
        @argcheck count_ones(numthings) == 1
        @argcheck (byteorder in "<>") || isone(numthings)
        in_native_order = (byteorder == NATIVE_ORDER) || isone(numthings)
        tz = trailing_zeros(numthings)
        return ParsedType(;
            julia_type = (UInt8, UInt16, UInt32, UInt64)[tz+1],
            julia_size = numthings,
            byteorder = in_native_order ? (1:numthings) : (numthings:-1:1),
            alignment = ALIGNMENT_LOOKUP[tz+1],
            just_copy = in_native_order,
        )
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
        return ParsedType(;
            julia_type = StaticString{numthings},
            julia_size = numthings,
            byteorder = 1:numthings,
            alignment = 0,
            just_copy = true,
        )
    elseif typechar == 'U'
        @argcheck byteorder in "<>"
        in_native_order = (byteorder == NATIVE_ORDER)
        byteorder = if (byteorder == NATIVE_ORDER)
            collect(1:numthings*4)
        else
            collect(Iterators.flatten((4+4i,3+4i,2+4i,1+4i) for i in 0:2))
        end
        return ParsedType(;
            julia_type = NTuple{numthings, Char},
            julia_size = numthings*4,
            byteorder,
            alignment = 2,
            just_copy = in_native_order,
        )
    elseif typechar == 'V'
        return ParsedType(;
            julia_type = NTuple{numthings, UInt8},
            julia_size = numthings,
            byteorder = 1:numthings,
            alignment = 0,
            just_copy = true,
        )
    end
end

