
const ZDataTypes = Union{
    Bool,
    Int8,
    Int16,
    Int32,
    Int64,
    UInt8,
    UInt16,
    UInt32,
    UInt64,
    Float16,
    Float32,
    Float64,
    ComplexF16,
    ComplexF32,
    ComplexF64,
    NTuple{N, UInt8} where N,
}

function isvalidtype(T::Type)::Bool
    isbitstype(T) && (
        (T <: ZDataTypes)
    )
end

"""
    ZArray(data::Array{T,N}; kwargs...)

Create a ZArray.

This is just a view of a regular Array with added metadata.

Like Zarr.jl, the dimensions are reversed relative to the Zarr metadata and
other languages such as Python. For example, a Julia array with size `(2, 3)`
is stored with `"shape": [3, 2]`, and `A[i, j]` in Julia is `a[j-1, i-1]` in Python.

The constructor does not copy the data Array, so do not mutate the
array after creating the ZArray.

# Keywords
- `chunks::Union{Int, Colon, NTuple{N,Union{Int,Colon}}} = -1`:
    The size of chunks that will be compressed.
    If `chunks` is a single element, that value will be used for all dimensions. 
    If `chunks` is `-1`, chunk size will be guessed: arrays up to 8 MiB are a single chunk,
    and larger arrays are split by repeatedly halving the largest chunk dimension,
    giving chunks between 4 and 8 MiB.
    If `chunks` is `:` or 0, the chunk size will be set to the array size in that dimension.
    Chunk sizes are at least 1, including for zero length dimensions.
- `compressor::Integer = sizeof(data) > 64 ? COMPRESSOR_ZSTD : COMPRESSOR_NONE`:
    Either `COMPRESSOR_NONE` or `COMPRESSOR_ZSTD`.
    By default small arrays are not compressed, because the compressor's overhead
    is larger than the bytes saved.
    Ignored for zero dimensional arrays, which like in zarr-python are not compressed.
- `level::Integer = default_level(compressor)`:
    Compression level, clamped to `level_range(compressor)`.
- `reverse_dims::Bool = false`:
    If `true`, chunks are stored with dimensions reversed relative to Julia's memory layout, Zarr `"F"` order.
    Ignored for zero dimensional arrays.
- `byteshuffle::Bool = compressor == COMPRESSOR_ZSTD`:
    If `true`, the numcodecs shuffle filter is applied before compressing.
    Ignored for 1 byte element types and zero dimensional arrays, where shuffling does nothing.
- `attrs::OrderedDict{String,Any} = OrderedDict{String,Any}()`:
    JSON encodable metadata, not copied on construction. 
    This can be modified after creating the ZArray.
"""
mutable struct ZArray{T,N} <: AbstractArray{T,N}
    data::Array{T,N}
    chunks::NTuple{N,Int}
    compressor::CompressorOptions
    attrs::OrderedDict{String,Any}
    function ZArray(
            data::Array{T,N},
            chunks::NTuple{N,Int},
            compressor::CompressorOptions;
            attrs=OrderedDict{String,Any}(),
        ) where {T, N}
        @assert isvalidtype(T)
        @assert all(≥(1), chunks)
        @assert compressor.itemsize == sizeof(T)
        new{T,N}(data, chunks, compressor, attrs)
    end
end

function ZArray(data::Array{T,N};
        chunks::Union{Int, Colon, NTuple{N,Union{Int,Colon}}}=-1,
        compressor::Integer=(sizeof(data) > 64 ? COMPRESSOR_ZSTD : COMPRESSOR_NONE),
        level::Integer=default_level(compressor),
        reverse_dims::Bool=false,
        byteshuffle::Bool=(compressor == COMPRESSOR_ZSTD),
        attrs=OrderedDict{String,Any}(),
    ) where {T, N}
    @argcheck isvalidtype(T)
    c = CompressorOptions(compressor, level, sizeof(T), reverse_dims, byteshuffle)
    if N == 0
        # Like zarr-python, zero dimensional arrays are not compressed.
        # Shuffling and reversing dimensions also do nothing to a single element.
        c = CompressorOptions(COMPRESSOR_NONE, 0, sizeof(T), false, false)
    end
    ZArray(data, normalize_chunks(chunks, size(data), sizeof(T)), c; attrs)
end

"""
Return the array stored in za.
This doesn't copy the array, so don't resize the array returned from this function.
"""
function getarray(za::ZArray)
    za.data
end

function Base.parent(za::ZArray)
    za.data
end

## Abstract Array interface
Base.size(za::ZArray, args...; kwargs...) = size(parent(za), args...; kwargs...)
Base.getindex(za::ZArray, args...; kwargs...) = getindex(parent(za), args...; kwargs...)
Base.IndexStyle(::Type{<:ZArray}) = IndexLinear()
Base.setindex!(za::ZArray, args...; kwargs...) = setindex!(parent(za), args...; kwargs...)
# Base.strides(za::ZArray) = strides(parent(za))
# Base.unsafe_convert(t::Type{<:Ptr}, za::ZArray) = Base.unsafe_convert(t, parent(za))
# Base.elsize(::Type{A}) where {T, A<:ZArray{T}} = Base.elsize(Array{T})
# Base.stride(za::ZArray, i::Int) = Base.stride(parent(za), i::Int)


function Base.collect(za::ZArray)::Array
    collect(za.data)
end

function Base.collect(element_type::Type, za::ZArray)::Array
    collect(element_type, za.data)
end


"""
Return the mutable SortedDict of attributes.
"""
attrs(za::ZArray) = za.attrs


"""
Return a normalized chunk size.
# Arguments
- `chunks::Union{Int, Colon, NTuple{N,Union{Int,Colon}}}`:
    The size of chunks that will be compressed.
    If `chunks` is a single element, that value will be used for all dimensions. 
    If `chunks` is `-1`, chunk size will be guessed: arrays up to 8 MiB are a single chunk,
    and larger arrays are split by repeatedly halving the largest chunk dimension,
    giving chunks between 4 and 8 MiB.
    If an element of `chunks` is `:` or 0, the chunk size will be set to the array size in that dimension.
- `size::NTuple{N,Int}`: array size.
- `elsize::Int`: sizeof array elements in bytes.

Chunk sizes are at least 1, including for zero length dimensions.
"""
function normalize_chunks(
        chunks::Union{Int, Colon, NTuple{N,Union{Int,Colon}}},
        size::NTuple{N,Int},
        elsize::Int, #in bytes
    )::NTuple{N,Int} where {N}
    raw_chunks::NTuple{N,Int} = if chunks == -1
        # Balanced chunking
        # The limit is large because arrays are usually loaded whole.
        CHUNK_MAX = 8*1024*1024  # 8 MiB
        target_bytes = max(CHUNK_MAX, elsize)
        # Repeatedly halve the largest chunk dimension, so small dimensions
        # are only split once every other dimension is as small.
        # Ties go to the last Julia dimension, the first Zarr dimension.
        _chunks = size
        while prod(_chunks)*elsize > target_bytes
            idx = findlast(==(maximum(_chunks)), _chunks)::Int
            _chunks = Base.setindex(_chunks, cld(_chunks[idx], 2), idx)
        end
        _chunks
    # elseif chunks == -2
    #     # Sequential Read chunking
    #     # Here we ignore random read performance, and just make sure chunks are under 64 MB
    #     # Chunks will also not do any tiling.
    #     CHUNK_MAX = 64*1024*1024  # Hard upper limit
    #     if prod(size)*elsize ≤ CHUNK_MAX
    #         # This also handles the case of zero sized elements or dimensions.
    #         size
    #     else
    #         target_els = ceil(Int, CHUNK_MAX/elsize)
    #         # Modified from:
    #         # https://github.com/meggart/DiskArrays.jl/blob/68c815096fe40f370152b11732b900f07ad4b608/src/chunks.jl#L291-L304
    #         ii = searchsortedfirst(cumprod(collect(size)), target_els)
    #         ntuple(N) do idim
    #             if idim < ii
    #                 size[idim]
    #             elseif idim > ii
    #                 1
    #             else
    #                 ceil(Int, size[idim] / ceil(Int, prod(size[1:idim]) / target_els))
    #             end
    #         end
    #     end
    else
        fill_chunks::NTuple{N,Union{Int,Colon}} = if chunks isa Union{Int,Colon}
            ntuple(Returns(chunks), N)
        else
            chunks
        end
        expanded_chunks::NTuple{N,Int} = ntuple(N) do i
            (fill_chunks[i] == Colon() || fill_chunks[i] == 0) ? size[i] : fill_chunks[i]
        end
        @argcheck all(≥(0), expanded_chunks)
        expanded_chunks
    end
    max.(raw_chunks, 1)
end