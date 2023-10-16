# Parse zarr array meta data descriptions.

using ArgCheck
import JSON3
import Base64

"Usually 8, maybe this could be 4 on a 32 bit machine?"
const DOUBLE_ALIGN = (sizeof(Tuple{Float64,Int8}) == 16) ? 3 : 2

const ALIGNMENT_LOOKUP = (0, 1, 2, DOUBLE_ALIGN) 

"Character for native byte order"
const NATIVE_ORDER = ENDIAN_BOM == 0x04030201 ? '<' : '>'
"Character for other byte order"
const OTHER_ORDER = ENDIAN_BOM == 0x04030201 ? '>' : '<'


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

    # "`zarr_size == julia_size && byteorder == 1:julia_size`"
    # just_copy::Bool
end

function Base.:(==)(a::ParsedType, b::ParsedType)
    all(x->isequal(x...), ((getfield(a, k),getfield(b, k)) for k ∈ fieldnames(ParsedType)))
end

"""
Parse a basic zarr typestr.
"""
function parse_zarr_type(typestr::String; silence_warnings=false)::ParsedType
    byteorder = typestr[1]
    typechar = typestr[2]
    # note need to strip non digits because of datetime units
    # This is usually the number of bytes, but if typechar is 'U' it is number of bytes/4 for some stupid reason.
    numthings = parse(Int,rstrip(!isdigit, typestr[3:end]))
    units = lstrip(isdigit, typestr[3:end])[begin+1:end-1]
    @argcheck byteorder in "<>|"
    @argcheck typechar in "biufcV"
    @argcheck numthings ≥ 0
    # actual number of bytes
    if typechar == 'b'
        @argcheck numthings == 1
        return ParsedType(;
            julia_type = Bool,
            julia_size = 1,
            byteorder = [1],
            alignment = 0,
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
        )
    elseif typechar == 'f'
        @argcheck numthings in 2:8
        @argcheck count_ones(numthings) == 1
        @argcheck byteorder in "<>"
        in_native_order = (byteorder == NATIVE_ORDER)
        tz = trailing_zeros(numthings)
        return ParsedType(;
            julia_type = (Float16, Float32, Float64)[tz],
            julia_size = numthings,
            byteorder = in_native_order ? (1:numthings) : (numthings:-1:1),
            alignment = ALIGNMENT_LOOKUP[tz+1],
        )
    elseif typechar == 'c'
        @argcheck numthings in 4:16
        @argcheck count_ones(numthings) == 1
        @argcheck byteorder in "<>"
        in_native_order = (byteorder == NATIVE_ORDER)
        tz = trailing_zeros(numthings)
        return ParsedType(;
            julia_type = (ComplexF16, ComplexF32, ComplexF64)[tz - 1],
            julia_size = numthings,
            byteorder = in_native_order ? (1:numthings) : [numthings÷2:-1:1; numthings:-1:numthings÷2+1;],
            alignment = ALIGNMENT_LOOKUP[tz],
        )
    elseif typechar == 'V'
        return ParsedType(;
            julia_type = NTuple{numthings, UInt8},
            julia_size = numthings,
            byteorder = 1:numthings,
            alignment = 0,
        )
    else
        error("Unreachable")
    end
end

"""
Parse a structured zarr typestr
"""
function parse_zarr_type(descr::JSON3.Array; silence_warnings=false)::ParsedType
    error("Structured types not supported")
end


"""
Return the fill value in bytes that should be copied to the julia type.
"""
function parse_zarr_fill_value(fill_value::Union{String,Nothing}, dtype::ParsedType)::Vector{UInt8}
    if isnothing(fill_value)
        zeros(UInt8, dtype.julia_size)
    elseif (fill_value in ("NaN","Infinity","-Infinity")) && (dtype.julia_type <: AbstractFloat)
        reinterpret(UInt8,[parse(dtype.julia_type, fill_value)])
    else
        zarr_bytes = Base64.base64decode(fill_value)
        @argcheck length(zarr_bytes) == dtype.zarr_size
        output = zeros(UInt8, dtype.julia_size)
        for i in 1:dtype.zarr_size
            output[dtype.byteorder[i]] = zarr_bytes[i]
        end
        output
    end
end

"""
Return the fill value in bytes that should be copied to the julia type.
"""
function parse_zarr_fill_value(fill_value::Union{Bool,Float64,Int64}, dtype::ParsedType)::Vector{UInt8}
    if iszero(fill_value) # If its zero just set all bytes to zero.
        zeros(UInt8, dtype.julia_size)
    else
        reinterpret(UInt8,[convert(dtype.julia_type, fill_value)])
    end
end


"""
Zarr Version 2 Array meta data
https://zarr.readthedocs.io/en/stable/spec/v2.html#arrays
"""
Base.@kwdef struct ParsedMetaData
    shape::Vector{Int}
    chunks::Vector{Int}
    dtype::ParsedType
    compressor::Union{Nothing, JSON3.Object}
    fill_value::Vector{UInt8}
    is_column_major::Bool
    dimension_separator::Char='.'
end

function parse_zarr_metadata(metadata::JSON3.Object)::ParsedMetaData
    @argcheck metadata["zarr_format"] == 2
    shape = collect(Int, metadata["shape"])
    chunks = collect(Int, metadata["chunks"])
    @argcheck length(shape)==length(chunks)
    @argcheck all(≥(0), shape)
    @argcheck all(≥(0), chunks)
    if all(>(0), shape)
        @argcheck all(>(0), chunks)
    end
    dtype = parse_zarr_type(metadata["dtype"])
    compressor = metadata["compressor"]
    filters = metadata["filters"]
    @argcheck isnothing(filters) || isempty(filters)
    fill_value = parse_zarr_fill_value(metadata["fill_value"], dtype)
    order = metadata["order"]
    @argcheck order in ("C", "F")
    is_column_major = order == "F"
    dimension_separator = get(Returns("."), metadata, "dimension_separator")[1]
    ParsedMetaData(;
        shape,
        chunks,
        dtype,
        compressor,
        fill_value,
        is_column_major,
        dimension_separator,
    )
end
