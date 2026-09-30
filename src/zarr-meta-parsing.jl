# Parsing zarr array metadata.

import Base64

# Only little endian hosts and little endian zarr data are supported.
@assert ENDIAN_BOM == 0x04030201 "SmallZarrGroups only supports little endian hosts"

"""
    parse_zarr_dtype(typestr::String)::DataType

Return the Julia type of a zarr dtype string, for example `Float64` for `"<f8"`.
"""
function parse_zarr_dtype(typestr::String)::DataType
    @argcheck length(typestr) ≥ 3
    byteorder = typestr[1]
    typechar = typestr[2]
    @argcheck byteorder in "<>|"
    @argcheck typechar in "biufcV"
    n = parse(Int, typestr[3:end]) # number of bytes
    @argcheck n ≥ 0
    if typechar == 'b'
        @argcheck n == 1
        Bool
    elseif typechar == 'i'
        @argcheck n in (1, 2, 4, 8)
        @argcheck byteorder == '<' || n == 1 "big endian data is not supported"
        (Int8, Int16, Int32, Int64)[trailing_zeros(n) + 1]
    elseif typechar == 'u'
        @argcheck n in (1, 2, 4, 8)
        @argcheck byteorder == '<' || n == 1 "big endian data is not supported"
        (UInt8, UInt16, UInt32, UInt64)[trailing_zeros(n) + 1]
    elseif typechar == 'f'
        @argcheck n in (2, 4, 8)
        @argcheck byteorder == '<' "big endian data is not supported"
        (Float16, Float32, Float64)[trailing_zeros(n)]
    elseif typechar == 'c'
        @argcheck n in (4, 8, 16)
        @argcheck byteorder == '<' "big endian data is not supported"
        (ComplexF16, ComplexF32, ComplexF64)[trailing_zeros(n) - 1]
    else # typechar == 'V'
        NTuple{n, UInt8}
    end
end

"""
Return the `T` with all zero bytes.
"""
zero_fill(::Type{T}) where {T<:Number} = zero(T)
zero_fill(::Type{NTuple{N, UInt8}}) where {N} = ntuple(Returns(0x00), Val(N))

"""
    parse_zarr_fill_value(::Type{T}, fill_value)::T

Return the JSON `fill_value` of an array with element type `T`.
"""
function parse_zarr_fill_value(::Type{T}, fill_value::String)::T where {T}
    if T <: AbstractFloat && fill_value == "NaN"
        convert(T, NaN)
    elseif T <: AbstractFloat && fill_value == "Infinity"
        convert(T, Inf)
    elseif T <: AbstractFloat && fill_value == "-Infinity"
        convert(T, -Inf)
    else
        # Base64 encoded little endian bytes.
        bytes = Base64.base64decode(fill_value)
        @argcheck length(bytes) == sizeof(T)
        sizeof(T) == 0 ? reinterpret(T, ()) : only(reinterpret(T, bytes))
    end
end
function parse_zarr_fill_value(::Type{T}, fill_value::Union{Nothing, Real})::T where {T}
    if isnothing(fill_value) || iszero(fill_value)
        zero_fill(T)
    else
        convert(T, fill_value)
    end
end
# zarr-python writes complex fill values as a list of the real and imaginary parts.
function parse_zarr_fill_value(::Type{Complex{T}}, fill_value::AbstractVector)::Complex{T} where {T}
    @argcheck length(fill_value) == 2
    Complex{T}(parse_zarr_fill_value(T, fill_value[1]), parse_zarr_fill_value(T, fill_value[2]))
end
function parse_zarr_fill_value(::Type{T}, fill_value)::T where {T}
    throw(ArgumentError("fill_value $(repr(fill_value)) is not supported"))
end

# The contents of a `.zarray` file, before validation.
# https://zarr-specs.readthedocs.io/en/latest/v2/v2.0.html#arrays
# Unknown keys are ignored.
# `fill_value` has type `Any` because it is parsed after the dtype is known.
# Parsing is lenient
JSON.@defaults struct CompressorJSON
    id::String
    level::Union{Nothing, Int} = nothing
end
JSON.@defaults struct FilterJSON
    id::String
    elementsize::Union{Nothing, Int} = nothing
end
JSON.@defaults struct ZarrayJSON
    zarr_format::Int
    shape::Vector{Int}
    chunks::Vector{Int}
    dtype::String
    fill_value::Any
    order::Char
    compressor::Union{Nothing, CompressorJSON}
    filters::Union{Nothing, Vector{FilterJSON}}
    dimension_separator::Char = '.'
end

"""
Validated `.zarray` metadata, with `shape` and `chunks` in Julia order.
Chunk sizes are at least 1.
"""
struct ZarrayMetadata
    dtype::DataType
    shape::Vector{Int}
    chunks::Vector{Int}
    fill_value::Any
    dimension_separator::Char
    compressor::CompressorOptions
end

"""
    parse_zarray(bytes::Vector{UInt8})::ZarrayMetadata

Parse and validate the contents of a `.zarray` file.

Out of range values that are only used for encoding, like the compression level, are clamped instead of rejected.
"""
function parse_zarray(bytes::Vector{UInt8})::ZarrayMetadata
    z = JSON.parse(bytes, ZarrayJSON)
    @argcheck z.zarr_format == 2
    @argcheck length(z.shape) == length(z.chunks)
    @argcheck all(≥(0), z.shape)
    @argcheck all(≥(0), z.chunks)
    if all(>(0), z.shape)
        @argcheck all(>(0), z.chunks)
    end
    @argcheck z.order ∈ ('C', 'F')
    @argcheck z.dimension_separator ∈ ('.', '/')
    dtype = parse_zarr_dtype(z.dtype)
    itemsize = sizeof(dtype)
    type, level = parse_compressor(z.compressor)
    compressor = CompressorOptions(type, level, itemsize, z.order == 'F', parse_byteshuffle(z.filters, itemsize))
    # Chunk sizes of 0 are only allowed in arrays with no elements, where chunks aren't read,
    # so they are normalized to 1.
    z.chunks .= max.(z.chunks, 1)
    # Like Zarr.jl, dimensions are reversed so that the
    # fastest changing dimension is first in Julia.
    ZarrayMetadata(dtype, reverse!(z.shape), reverse!(z.chunks), z.fill_value, z.dimension_separator, compressor)
end

"""
Return the compressor type and level.

The level is the default level if it is missing or `null`.
Out of range levels are clamped by the `CompressorOptions` constructor.
"""
function parse_compressor(c::Union{Nothing, CompressorJSON})::Tuple{Int32, Int}
    isnothing(c) && return (COMPRESSOR_NONE, 0)
    type, level = if c.id == "zstd"
        # The zstd checksum option is ignored, zstd frames record if they have a checksum.
        COMPRESSOR_ZSTD, c.level
    else
        throw(ArgumentError("$(c.id) compressor not supported yet"))
    end
    type, something(level, default_level(type))
end

"""
Return `true` if the filters are the byte shuffle filter, `false` if there are no filters.
Any other filters are not supported.
"""
function parse_byteshuffle(filters::Union{Nothing, Vector{FilterJSON}}, itemsize::Int)::Bool
    (isnothing(filters) || isempty(filters)) && return false
    @argcheck length(filters) == 1 "only a single shuffle filter is supported"
    filter = only(filters)
    @argcheck filter.id == "shuffle" "$(filter.id) filter not supported"
    @argcheck filter.elementsize == itemsize "shuffle elementsize not equal to the dtype size is not supported"
    true
end
