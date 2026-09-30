# Writing zarr array metadata.

"""
    append_zarr_dtype!(b::Vector{UInt8}, T::Type)

Append the zarr dtype string of `T` to `b`, for example `"<f8"` for `Float64`.
"""
function append_zarr_dtype!(b::Vector{UInt8}, T::Type)
    typechar = if T === Bool
        UInt8('b')
    elseif T <: Union{Int8, Int16, Int32, Int64}
        UInt8('i')
    elseif T <: Union{UInt8, UInt16, UInt32, UInt64}
        UInt8('u')
    elseif T <: Union{Float16, Float32, Float64}
        UInt8('f')
    elseif T <: Union{ComplexF16, ComplexF32, ComplexF64}
        UInt8('c')
    elseif T <: (NTuple{N, UInt8} where N)
        UInt8('V')
    else
        throw(ArgumentError("type $(T) cannot be saved in a zarr array"))
    end
    byteorder = if (sizeof(T) == 1 || typechar == UInt8('V'))
        UInt8('|')
    else
        UInt8('<')
    end
    push!(b, byteorder)
    push!(b, typechar)
    append_int!(b, sizeof(T))
end

append_str!(b::Vector{UInt8}, s::String) = append!(b, codeunits(s))

"""
Append the decimal digits of `x` to `b`.
"""
function append_int!(b::Vector{UInt8}, x::Integer)
    x < 0 && push!(b, UInt8('-'))
    x = Base.uabs(x)
    n = ndigits(x)
    resize!(b, length(b) + n)
    for i in lastindex(b):-1:lastindex(b)-n+1
        b[i] = UInt8('0') + UInt8(x % 10)
        x ÷= 10
    end
    b
end

"""
Append the JSON array of `dims`, reversed into zarr order.
"""
function append_dims!(b::Vector{UInt8}, dims::NTuple{N,Int}) where {N}
    push!(b, UInt8('['))
    for i in N:-1:1
        append_int!(b, dims[i])
        i > 1 && push!(b, UInt8(','))
    end
    push!(b, UInt8(']'))
end

"""
Append the numcodecs compressor JSON.
"""
function append_compressor!(b::Vector{UInt8}, c::CompressorOptions)
    if c.type == COMPRESSOR_NONE
        append_str!(b, "null")
    elseif c.type == COMPRESSOR_ZLIB
        append_str!(b, "{\"id\":\"zlib\",\"level\":")
        append_int!(b, c.level)
        append_str!(b, "}")
    elseif c.type == COMPRESSOR_GZIP
        append_str!(b, "{\"id\":\"gzip\",\"level\":")
        append_int!(b, c.level)
        append_str!(b, "}")
    elseif c.type == COMPRESSOR_BLOSC_LZ4
        append_str!(b, "{\"id\":\"blosc\",\"blocksize\":0,\"clevel\":")
        append_int!(b, c.level)
        append_str!(b, ",\"cname\":\"lz4\",\"shuffle\":1}")
    elseif c.type == COMPRESSOR_ZSTD
        append_str!(b, "{\"id\":\"zstd\",\"level\":")
        append_int!(b, c.level)
        append_str!(b, "}")
    else
        error("unreachable") # COV_EXCL_LINE
    end
end

"""
Append the numcodecs filters JSON.
"""
function append_filters!(b::Vector{UInt8}, c::CompressorOptions)
    if c.byteshuffle
        append_str!(b, "[{\"id\":\"shuffle\",\"elementsize\":")
        append_int!(b, c.itemsize)
        append_str!(b, "}]")
    else
        append_str!(b, "null")
    end
end

"""
    zarray_json(T::Type, shape::NTuple{N,Int}, chunks::NTuple{N,Int}, c::CompressorOptions)::Vector{UInt8}

Return the contents of the `.zarray` file of an array with element type `T`.
`shape` and `chunks` are in Julia order.
"""
function zarray_json(T::Type, shape::NTuple{N,Int}, chunks::NTuple{N,Int}, c::CompressorOptions)::Vector{UInt8} where {N}
    b = sizehint!(UInt8[], 256)
    append_str!(b, "{\"zarr_format\":2,\"fill_value\":null,\"chunks\":")
    append_dims!(b, chunks)
    append_str!(b, ",\"order\":")
    append_str!(b, c.reverse_dims ? "\"F\"" : "\"C\"")
    append_str!(b, ",\"filters\":")
    append_filters!(b, c)
    append_str!(b, ",\"compressor\":")
    append_compressor!(b, c)
    append_str!(b, ",\"shape\":")
    append_dims!(b, shape)
    append_str!(b, ",\"dtype\":\"")
    append_zarr_dtype!(b, T)
    append_str!(b, "\"}")
    b
end
