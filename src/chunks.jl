# Moving chunks between arrays and encoded bytes.

using ChunkCodecCore: encode, decode!, ShuffleCodec

"""
Return the key of the chunk at Julia order `index`, relative to the array.
"""
function chunk_key(index::CartesianIndex, separator::Char)::String
    # Zero dimensional arrays have a single chunk named "0".
    isempty(Tuple(index)) && return "0"
    join(reverse(Tuple(index) .- 1), separator)
end

"""
Return the strides of a column major array of size `sz`.
"""
column_major_strides(sz::NTuple{N,Int}) where {N} = Base.front(cumprod((1, sz...)))

"""
Return the strides of a chunk buffer in Julia dimension order.
"""
function chunk_strides(chunks::NTuple{N,Int}, reverse_dims::Bool)::NTuple{N,Int} where {N}
    if reverse_dims
        reverse(column_major_strides(reverse(chunks)))
    else
        column_major_strides(chunks)
    end
end

"""
Return the number of bytes in the buffer of a chunk of size `chunks` with elements of `itemsize` bytes.
Throw an `OverflowError` if it does not fit in an `Int`.
"""
function chunk_nbytes(itemsize::Int, chunks::NTuple{N,Int})::Int where {N}
    # Empty arrays are normalized elsewhere.
    @argcheck all(≥(1), chunks)
    foldl(Base.Checked.checked_mul, chunks; init=itemsize)
end

"""
Return the block of bytes copied between an array of size `shape` with elements of `itemsize` bytes
and the buffer of the chunk at `index`.

The block has an extra first dimension for the bytes of each element.
Return the byte offset of the block in the array, the byte strides of the array and of the chunk buffer,
and the size of the block, which is the part of the chunk inside the array.
"""
function chunk_byte_layout(
        itemsize::Int, shape::NTuple{N,Int}, chunks::NTuple{N,Int}, reverse_dims::Bool, index::CartesianIndex{N},
    ) where {N}
    # Empty arrays are normalized elsewhere.
    @argcheck all(≥(1), chunks)
    # The chunk must start inside the array.
    start = Base.Checked.checked_mul.(Tuple(index) .- 1, chunks)
    @argcheck all(0 .≤ start .< shape)
    data_strides = column_major_strides((itemsize, shape...))
    buffer_strides = (1, (chunk_strides(chunks, reverse_dims) .* itemsize)...)
    offset = sum((0, start...) .* data_strides)
    sizes = (itemsize, min.(chunks, shape .- start)...)
    offset, data_strides, buffer_strides, sizes
end

"""
Copy the part of `data` covered by the chunk at `index` into the chunk buffer `chunk`.
Parts of the chunk outside `data` are set to zero.
"""
function copy_to_chunk!(
        chunk::Vector{UInt8}, data::Array{T,N}, chunks::NTuple{N,Int}, reverse_dims::Bool, index::CartesianIndex{N},
    ) where {T, N}
    @argcheck isvalidtype(T)
    data_c = Base.cconvert(Ptr{T}, data)
    GC.@preserve data_c unsafe_copy_to_chunk!(
        chunk, Ptr{UInt8}(Base.unsafe_convert(Ptr{T}, data_c)), sizeof(T), size(data), chunks, reverse_dims, index,
    )
    chunk
end

# Outlined from copy_to_chunk! to avoid overspecialization
function unsafe_copy_to_chunk!(
        chunk::Vector{UInt8}, data::Ptr{UInt8}, itemsize::Int, shape::NTuple{N,Int},
        chunks::NTuple{N,Int}, reverse_dims::Bool, index::CartesianIndex{N},
    ) where {N}
    @argcheck length(chunk) == chunk_nbytes(itemsize, chunks)
    offset, data_strides, buffer_strides, sizes = chunk_byte_layout(itemsize, shape, chunks, reverse_dims, index)
    if Base.tail(sizes) != chunks
        fill!(chunk, 0x00)
    end
    chunk_c = Base.cconvert(Ptr{UInt8}, chunk)
    GC.@preserve chunk_c unsafe_strided_copy!(
        Base.unsafe_convert(Ptr{UInt8}, chunk_c), buffer_strides,
        data + offset, data_strides,
        sizes,
    )
    chunk
end

"""
Copy the chunk buffer `chunk` into the part of `data` covered by the chunk at `index`.
"""
function copy_from_chunk!(
        data::Array{T,N}, chunk::Vector{UInt8}, chunks::NTuple{N,Int}, reverse_dims::Bool, index::CartesianIndex{N},
    ) where {T, N}
    @argcheck isvalidtype(T)
    data_c = Base.cconvert(Ptr{T}, data)
    GC.@preserve data_c unsafe_copy_from_chunk!(
        Ptr{UInt8}(Base.unsafe_convert(Ptr{T}, data_c)), sizeof(T), size(data), chunk, chunks, reverse_dims, index,
    )
    data
end

# Outlined from copy_from_chunk! to avoid overspecialization
function unsafe_copy_from_chunk!(
        data::Ptr{UInt8}, itemsize::Int, shape::NTuple{N,Int}, chunk::Vector{UInt8},
        chunks::NTuple{N,Int}, reverse_dims::Bool, index::CartesianIndex{N},
    ) where {N}
    @argcheck length(chunk) == chunk_nbytes(itemsize, chunks)
    offset, data_strides, buffer_strides, sizes = chunk_byte_layout(itemsize, shape, chunks, reverse_dims, index)
    chunk_c = Base.cconvert(Ptr{UInt8}, chunk)
    GC.@preserve chunk_c unsafe_strided_copy!(
        data + offset, data_strides,
        Base.unsafe_convert(Ptr{UInt8}, chunk_c), buffer_strides,
        sizes,
    )
    nothing
end

"""
Return the encoded bytes of the chunk buffer `chunk`.
"""
function encode_chunk(c::CompressorOptions, chunk::Vector{UInt8})::Vector{UInt8}
    if c.byteshuffle
        compress(c, encode(ShuffleCodec(c.itemsize), chunk))
    else
        compress(c, chunk)
    end
end

"""
Decode the encoded bytes `src` into the chunk buffer `chunk`.
"""
function decode_chunk!(chunk::Vector{UInt8}, c::CompressorOptions, src::Vector{UInt8})
    if c.byteshuffle
        shuffled = similar(chunk)
        decompress!(c, shuffled, src)
        decode!(ShuffleCodec(c.itemsize), chunk, shuffled)
    else
        decompress!(c, chunk, src)
    end
    chunk
end
