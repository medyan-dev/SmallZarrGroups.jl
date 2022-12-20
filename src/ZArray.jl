const DEFAULT_COMPRESSOR = JSON3.read("""
    "compressor": {
        "blocksize": 0,
        "clevel": 5,
        "cname": "lz4",
        "id": "blosc",
        "shuffle": 1
    },
    """)

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
    ComplexF32,
    ComplexF64,
}

function isvalidtype(T::Type)
    isconcretetype(T) && (T <: ZDataTypes)
end

"""
Create a ZArray.

This is just a view of a regular Array with added metadata.

The constructor does not copy the data Array, so do not mutate the
array after creating the ZArray.

# Keywords
- `chunks::Union{Int, Colon, NTuple{N,Union{Int,Colon}}} = -1`:
    The size of chunks that will be compressed.
    If `chunks` is a single element, that value will be used for all dimensions. 
    If `chunks` is `-1`, chunk size will be guessed for balanced random and sequential read performance.
    If `chunks` is `:` or 0, the chunk size will be set to the array size in that dimension.
- `compressor::String = "default"`:
    Only blosc and no compression are supported.
    If `"default"`, `DEFAULT_COMPRESSOR` will be used.
    If `nothing`, no compressor will be used.
    Otherwise, `compressor` must be a json3 object that can be understood by numcodecs https://github.com/zarr-developers/numcodecs
- `attrs::SortedDict{String,Any}=SortedDict{String,Any}()`:
    JSON3 encodable metadata, not copied on construction. 
    This can be modified after creating the ZArray.
"""
mutable struct ZArray
    data::Array{<:ZDataTypes}
    chunks::Vector{Int}
    compressor::Union{Nothing, JSON3.Object}

    attrs::OrderedDict{String,Any}
    function ZArray(data::Array{T,N};
            chunks::Union{Int, Colon, NTuple{N,Union{Int,Colon}}}=-1,
            compressor::Union{Nothing, JSON3.Object}=DEFAULT_COMPRESSOR,
            attrs=OrderedDict{String,Any}(),
        ) where {T, N}
        @argcheck isvalidtype(T)
        real_chunks::Vector{Int} = collect(normalize_chunks(chunks,size(data),Base.elsize(data)))
        new(data, real_chunks, compressor, filters, attrs)
    end
end

"""
Change the array in za.
This doesn't copy the array, so don't resize the array after calling this function.
"""
function setarray!(za::ZArray, data::Array{T,N}; chunks::Union{Int, Colon, NTuple{N,Union{Int,Colon}}}=-1) where {T, N}
    @argcheck isvalidtype(T)
    real_chunks::Vector{Int} = collect(normalize_chunks(chunks,size(data),Base.elsize(data)))
    za.chunks = real_chunks
    za.data = data
    za
end

"""
Return the array stored in za.
This doesn't copy the array, so don't resize the array returned from this function.
"""
function getarray(za::ZArray)
    za.data
end

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
Set the compressor.
"""
function set_compressor!(za::ZArray, compressor::Union{Nothing, JSON3.Object}=DEFAULT_COMPRESSOR)
    za.compressor = compressor
end

get_compressor!(za::ZArray)::Union{Nothing, JSON3.Object} = za.compressor


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
"""
function normalize_chunks(
        chunks::Union{Int, Colon, NTuple{N,Union{Int,Colon}}},
        size::NTuple{N,Int},
        elsize::Int, #in bytes
    )::NTuple{N,Int} where {N}
    if chunks == -1
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
        # This is also from h5py, but the dims are iterated in reverse order because julia.
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
end