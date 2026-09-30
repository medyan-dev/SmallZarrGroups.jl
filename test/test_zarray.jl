using SmallZarrGroups
using SmallZarrGroups: ZArray, CompressorOptions, normalize_chunks
using SmallZarrGroups: COMPRESSOR_NONE, COMPRESSOR_ZLIB, COMPRESSOR_BLOSC_LZ4, DEFAULT_COMPRESSOR
using DataStructures: OrderedDict
using Test

@testset "ZArray keyword constructor" begin
    data = rand(Float32, 100, 30)
    z = ZArray(data)
    @test parent(z) === data
    @test z.chunks == normalize_chunks(-1, size(data), 4)
    @test z.compressor == CompressorOptions(DEFAULT_COMPRESSOR, 5, 4, false, false)
    @test DEFAULT_COMPRESSOR == COMPRESSOR_BLOSC_LZ4
    @test isempty(attrs(z))

    a = OrderedDict{String,Any}("foo" => 1)
    z = ZArray(data; chunks=(10, :), compressor=COMPRESSOR_ZLIB, level=9, reverse_dims=true, byteshuffle=true, attrs=a)
    @test z.chunks == (10, 30)
    @test z.compressor == CompressorOptions(COMPRESSOR_ZLIB, 9, 4, true, true)
    @test attrs(z) === a

    # zero length dimensions have a chunk size of 1
    @test ZArray(zeros(3, 0)).chunks == (3, 1)
    @test ZArray(zeros(3, 0); chunks=(2, 0)).chunks == (2, 1)

    # shuffling 1 byte elements does nothing
    @test !ZArray(rand(UInt8, 3); byteshuffle=true).compressor.byteshuffle
    # zero dimensional arrays are not compressed, shuffled, or reversed
    @test ZArray(fill(1.5); compressor=COMPRESSOR_ZLIB, level=9, reverse_dims=true, byteshuffle=true).compressor ==
        CompressorOptions(COMPRESSOR_NONE, 0, 8, false, false)
    @test_throws ArgumentError ZArray(fill(1.5); compressor=4)

    # the default level depends on the compressor
    @test ZArray(data; compressor=COMPRESSOR_NONE).compressor.level == 0
    @test ZArray(data; compressor=COMPRESSOR_ZLIB).compressor.level == 1

    @test_throws ArgumentError ZArray(data; compressor=4)
    @test ZArray(data; compressor=COMPRESSOR_ZLIB, level=10).compressor.level == 9
    @test_throws ArgumentError ZArray(data; chunks=(-2, 3))
    @test_throws ArgumentError ZArray(["not", "bits"])
    @test_throws ArgumentError ZArray(rand(Int128, 3))
end
