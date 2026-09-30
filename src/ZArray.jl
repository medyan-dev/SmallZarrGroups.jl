
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
    If `chunks` is `-1`, chunk size will be guessed for balanced random and sequential read performance.
    If `chunks` is `:` or 0, the chunk size will be set to the array size in that dimension.
    Chunk sizes are at least 1, including for zero length dimensions.
- `compressor::Integer = DEFAULT_COMPRESSOR`:
    Either `COMPRESSOR_NONE` or `COMPRESSOR_ZSTD`.
    Ignored for zero dimensional arrays, which like in zarr-python are not compressed.
- `level::Integer = default_level(compressor)`:
    Compression level, clamped to `level_range(compressor)`.
- `reverse_dims::Bool = false`:
    If `true`, chunks are stored with dimensions reversed relative to Julia's memory layout, Zarr `"F"` order.
    Ignored for zero dimensional arrays.
- `byteshuffle::Bool = true`:
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
        compressor::Integer=DEFAULT_COMPRESSOR,
        level::Integer=default_level(compressor),
        reverse_dims::Bool=false,
        byteshuffle::Bool=true,
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
    If `chunks` is `-1`, chunk size will be guessed for balanced random and sequential read performance.
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
        # guess chunk size for strictly negative dims.
        # From https://www.pytables.org/usersguide/optimization.html
        # Ideally chunksize should be 128KB to 512KB
        # >128KB to have good sequential read performance.
        # <512KB to have good random read performance.
        # heuristic from zarr-python adapted for julia
        # https://github.com/zarr-developers/zarr-python/blob/42da4aa2b2d6b6e79a6f3d6629e3d1837af8e9b9/zarr/util.py#L74
        #     """
        #     Guess an appropriate chunk layout for an array, given its shape and
        #     the size of each element in bytes.  Will allocate chunks only as large
        #     as CHUNK_MAX.  Chunks are generally close to some power-of-2 fraction of
        #     each axis, slightly favoring bigger values for the first index.
        #     Undocumented and subject to change without warning.
        #     """
        CHUNK_BASE = 256*1500  # Multiplier by which chunks are adjusted
        CHUNK_MIN = 128*1024  # Soft lower limit (128k)
        CHUNK_MAX = 64*1024*1024  # Hard upper limit
        data_bytes = prod(size)*elsize
        target_bytes = clamp(CHUNK_BASE*(data_bytes*2^-20)^(1/log2(10)), CHUNK_MIN, CHUNK_MAX)
        target_bytes = max(target_bytes, elsize)
        # This is also from h5py, but the dims are iterated in reverse order because
        # Julia dimensions are the reverse of the Zarr dimensions.
        # Repeatedly loop over the dims, dividing the chunks size by 2.
        _chunks = size
        idx = Int(N)
        while prod(_chunks)*elsize > target_bytes
            # shrink chunk size if possible
            if _chunks[idx] > 1
                _chunks = Base.setindex(_chunks, ceil(Int,_chunks[idx]/2), idx)
            end
            idx = mod1(idx-1, Int(N))
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