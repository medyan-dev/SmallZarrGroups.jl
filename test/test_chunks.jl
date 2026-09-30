using SmallZarrGroups
using SmallZarrGroups: chunk_key, column_major_strides, chunk_strides, chunk_nbytes, chunk_byte_layout
using SmallZarrGroups: copy_to_chunk!, copy_from_chunk!, encode_chunk, decode_chunk!
using SmallZarrGroups: CompressorOptions, default_level
using SmallZarrGroups: COMPRESSOR_NONE, COMPRESSOR_ZLIB, COMPRESSOR_GZIP, COMPRESSOR_BLOSC_LZ4, COMPRESSOR_ZSTD
using Test

"""
Reference chunk buffer: the chunk's part of `data`, zero padded, then permuted if `reverse_dims`.
"""
function reference_chunk(data::Array{T,N}, chunks, reverse_dims, index) where {T,N}
    chunk = zeros(T, chunks...)
    start = (Tuple(index) .- 1) .* chunks .+ 1
    stop = min.(start .+ chunks .- 1, size(data))
    region = stop .- start .+ 1
    chunk[range.(1, region)...] = data[range.(start, stop)...]
    vec(reverse_dims ? permutedims(chunk, N:-1:1) : chunk)
end

@testset "chunk_key" begin
    @test chunk_key(CartesianIndex(), '.') == "0"
    @test chunk_key(CartesianIndex(1, 1), '.') == "0.0"
    # zarr order is reversed
    @test chunk_key(CartesianIndex(2, 3, 1), '.') == "0.2.1"
    @test chunk_key(CartesianIndex(2, 3, 1), '/') == "0/2/1"
end

@testset "column_major_strides and chunk_strides" begin
    @test column_major_strides(()) == ()
    @test column_major_strides((5,)) == (1,)
    @test column_major_strides((2, 3, 4)) == strides(zeros(2, 3, 4))
    @test chunk_strides((2, 3, 4), false) == (1, 2, 6)
    @test chunk_strides((2, 3, 4), true) == (12, 4, 1)
    @test chunk_strides((), true) == ()
end

@testset "chunk_nbytes" begin
    @test chunk_nbytes(2, ()) == 2
    @test chunk_nbytes(2, (4, 3)) == 24
    @test chunk_nbytes(0, (4, 3)) == 0
    # the product must not wrap around
    @test_throws OverflowError chunk_nbytes(1, (2^62, 4))
    @test_throws OverflowError chunk_nbytes(2, (2^62, 1))
end

@testset "chunk_byte_layout" begin
    shape = (10, 7)
    chunks = (4, 3)
    # With 2 byte elements, the byte strides of the array are (1, 2, 20).
    offset(i, j) = (LinearIndices(shape)[i, j] - 1)*2
    @test chunk_byte_layout(2, shape, chunks, false, CartesianIndex(1, 1)) == (0, (1, 2, 20), (1, 2, 8), (2, 4, 3))
    @test chunk_byte_layout(2, shape, chunks, true, CartesianIndex(1, 1)) == (0, (1, 2, 20), (1, 6, 2), (2, 4, 3))
    @test chunk_byte_layout(2, shape, chunks, false, CartesianIndex(2, 2)) == (offset(5, 4), (1, 2, 20), (1, 2, 8), (2, 4, 3))
    # partial chunk at the edge
    @test chunk_byte_layout(2, shape, chunks, false, CartesianIndex(3, 3)) == (offset(9, 7), (1, 2, 20), (1, 2, 8), (2, 2, 1))
    @test chunk_byte_layout(2, (), (), false, CartesianIndex()) == (0, (1,), (1,), (2,))
    # the index must be in the grid of chunks
    @test_throws ArgumentError chunk_byte_layout(2, shape, chunks, false, CartesianIndex(4, 1))
    @test_throws ArgumentError chunk_byte_layout(2, shape, chunks, false, CartesianIndex(0, 1))
    @test_throws ArgumentError chunk_byte_layout(2, (0, 7), chunks, false, CartesianIndex(1, 1))
    @test_throws ArgumentError chunk_byte_layout(2, shape, (typemax(Int), 3), false, CartesianIndex(2, 1))
    @test_throws OverflowError chunk_byte_layout(2, shape, (typemax(Int), 3), false, CartesianIndex(3, 1))
    # chunks must be positive
    @test_throws ArgumentError chunk_byte_layout(2, shape, (0, 3), false, CartesianIndex(1, 1))
end

@testset "copy_to_chunk! and copy_from_chunk!" begin
    for (shape, chunks) in [
            ((), ()),
            ((7,), (3,)),
            ((10, 7), (4, 3)),
            ((4, 5), (4, 5)),
            ((5, 6, 7), (2, 3, 4)),
            ((2, 5), (3, 2)), # every chunk is partial
            ((1,), (1,)),
            ((1,), (10,)),
            ((2, 2, 2), (7, 7, 7)),
            ((2, 2, 2), (2, 2, 7)),
            ((5, 6, 7), (1, 1, 1)),
        ]
        for dataT in (Int8, Int16)
            data = rand(dataT, shape)
            for reverse_dims in (false, true)
                loaded = zeros(dataT, shape...)
                chunk = Vector{UInt8}(undef, sizeof(dataT)*prod(chunks))
                for index in CartesianIndices(cld.(shape, chunks))
                    # stale data from a previous chunk must not leak into the padding
                    fill!(chunk, 0xff)
                    copy_to_chunk!(chunk, data, chunks, reverse_dims, index)
                    @test reinterpret(dataT, chunk) == reference_chunk(data, chunks, reverse_dims, index)
                    copy_from_chunk!(loaded, chunk, chunks, reverse_dims, index)
                end
                @test loaded == data
            end
        end
    end
    # the chunk buffer must hold exactly one chunk
    data = zeros(Int16, 4)
    @test_throws ArgumentError copy_to_chunk!(zeros(UInt8, 4), data, (4,), false, CartesianIndex(1))
    @test_throws ArgumentError copy_from_chunk!(data, zeros(UInt8, 9), (4,), false, CartesianIndex(1))
    @test_throws ArgumentError copy_to_chunk!(zeros(UInt8, 8), data, (4,), false, CartesianIndex(2))
    @test_throws ArgumentError copy_from_chunk!(data, zeros(UInt8, 8), (4,), false, CartesianIndex(2))
    # element types Zarr does not support
    @test_throws ArgumentError copy_to_chunk!(zeros(UInt8, 8), [Some("a")], (1,), false, CartesianIndex(1))
end

@testset "encode_chunk and decode_chunk!" begin
    for T in (UInt8, Int16, Float64, NTuple{3, UInt8})
        chunk = rand(UInt8, 60*sizeof(T))
        for type in (COMPRESSOR_NONE, COMPRESSOR_ZLIB, COMPRESSOR_GZIP, COMPRESSOR_BLOSC_LZ4, COMPRESSOR_ZSTD), byteshuffle in (false, true)
            c = CompressorOptions(type, default_level(type), sizeof(T), false, byteshuffle)
            decoded = similar(chunk)
            @test decode_chunk!(decoded, c, encode_chunk(c, chunk)) == chunk
        end
        # The byte shuffle moves byte j of element e to j*60 + e.
        c = CompressorOptions(COMPRESSOR_NONE, 0, sizeof(T), false, true)
        @test encode_chunk(c, chunk) == vec(permutedims(reshape(chunk, sizeof(T), :)))
    end
end
