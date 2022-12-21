# Parse zarr array meta data descriptions.

using ArgCheck
using StaticArrays
using StaticStrings
import JSON3
import Base64

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
    elseif (typechar == 'm') | (typechar == 'M')
        @argcheck byteorder in "<>"
        @argcheck numthings == 8
        silence_warnings || @warn "timedelta64 and datatime64 not supported, converting to Int64"
        in_native_order = (byteorder == NATIVE_ORDER)
        tz = trailing_zeros(numthings)
        return ParsedType(;
            julia_type = Int64,
            julia_size = 8,
            byteorder = in_native_order ? (1:8) : (8:-1:1),
            alignment = ALIGNMENT_LOOKUP[4],
        )
    elseif typechar == 'S'
        return ParsedType(;
            julia_type = StaticString{numthings},
            julia_size = numthings,
            byteorder = 1:numthings,
            alignment = 0,
        )
    elseif typechar == 'U'
        @argcheck (byteorder in "<>") || iszero(numthings)
        in_native_order = (byteorder == NATIVE_ORDER) || iszero(numthings)
        _byteorder = if in_native_order
            collect(1:numthings*4)
        else
            collect(Iterators.flatten((4+4i,3+4i,2+4i,1+4i) for i in 0:numthings-1))
        end
        return ParsedType(;
            julia_type = SVector{numthings, Char},
            julia_size = numthings*4,
            byteorder = _byteorder,
            alignment = iszero(numthings) ? 0 : 2,
        )
    elseif typechar == 'V'
        return ParsedType(;
            julia_type = NTuple{numthings, UInt8},
            julia_size = numthings,
            byteorder = 1:numthings,
            alignment = 0,
        )
    end
end

"""
Parse a structured zarr typestr
"""
function parse_zarr_type(descr::JSON3.Array; silence_warnings=false)::ParsedType
    current_byte = 0
    max_alignment = 0
    byteorder = Int[]
    feldnames = Symbol[]
    feldtypes = Type[]
    for feld in descr
        name::String = feld[1]
        parsed_type::ParsedType = if length(feld) == 3
            # Parse static array field.
            @argcheck feld[3] isa JSON3.Array
            shape::Vector{Int} = collect(Int,feld[3])
            el_type = parse_zarr_type(feld[2]; silence_warnings)
            el_size = el_type.julia_size
            zarr_el_size = el_type.zarr_size
            array_byteorder = Vector{Int}(undef, el_type.zarr_size*prod(shape))
            # This thing converts a row major linear index to a column major index.
            # This is needed because numpy static arrays are always in row major order
            # and Julia static arrays are always in column major order.
            converter_thing = PermutedDimsArray(LinearIndices(Tuple(shape)),reverse(1:length(shape)))
            for i in 1:length(converter_thing)
                column_major_idx_0::Int = converter_thing[i] - 1
                local byte_offset::Int = column_major_idx_0*el_size
                array_byteorder[(1+zarr_el_size*(i-1)):(zarr_el_size*i)] .= el_type.byteorder .+ byte_offset
            end
            ParsedType(;
                julia_type = SArray{Tuple{shape...,}, el_type.julia_type, length(shape), prod(shape)},
                julia_size = el_size*prod(shape),
                zarr_size = length(byteorder),
                byteorder = array_byteorder,
                alignment = el_type.alignment,
            )
        elseif length(feld) == 2
            parse_zarr_type(feld[2]; silence_warnings)
        else
            error("field must have 2 or three elements")
        end
        push!(feldnames, Symbol(name))
        push!(feldtypes, parsed_type.julia_type)
        alignment = parsed_type.alignment
        max_alignment = max(max_alignment, alignment)
        num_padding = 2^alignment - mod1(current_byte,2^alignment)
        current_byte += num_padding
        @assert iszero(mod(current_byte, 2^alignment))
        append!(byteorder, parsed_type.byteorder .+ current_byte)
        current_byte += parsed_type.julia_size
    end
    num_padding = 2^max_alignment - mod1(current_byte,2^max_alignment)
    current_byte += num_padding
    ParsedType(;
        julia_type = NamedTuple{(feldnames...,), Tuple{feldtypes...,}},
        julia_size = current_byte,
        zarr_size = length(byteorder),
        byteorder,
        alignment = max_alignment,
    )
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
function parse_zarr_fill_value(fill_value::Union{Float64,Int64}, dtype::ParsedType)::Vector{UInt8}
    reinterpret(UInt8,[convert(dtype.julia_type, fill_value)])
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
    @argcheck isnothing(compressor) || compressor.id == "blosc"
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
