using SmallZarrGroups
using SmallZarrGroups: ZArray, CompressorOptions, normalize_chunks
using SmallZarrGroups: COMPRESSOR_NONE, COMPRESSOR_ZSTD
using DataStructures: OrderedDict
using Test

@testset "ZArray keyword constructor" begin
    data = rand(Float32, 100, 30)
    z = ZArray(data)
    @test parent(z) === data
    @test z.chunks == normalize_chunks(-1, size(data), 4)
    @test z.compressor == CompressorOptions(COMPRESSOR_ZSTD, 1, 4, false, true)
    @test isempty(attrs(z))

    a = OrderedDict{String,Any}("foo" => 1)
    z = ZArray(data; chunks=(10, :), compressor=COMPRESSOR_NONE, level=9, reverse_dims=true, byteshuffle=false, attrs=a)
    @test z.chunks == (10, 30)
    @test z.compressor == CompressorOptions(COMPRESSOR_NONE, 0, 4, true, false)
    @test attrs(z) === a

    # zero length dimensions have a chunk size of 1
    @test ZArray(zeros(3, 0)).chunks == (3, 1)
    @test ZArray(zeros(3, 0); chunks=(2, 0)).chunks == (2, 1)

    # shuffling 1 byte elements does nothing
    @test !ZArray(rand(UInt8, 3); compressor=COMPRESSOR_ZSTD, byteshuffle=true).compressor.byteshuffle
    # zero dimensional arrays are not compressed, shuffled, or reversed
    @test ZArray(fill(1.5); compressor=COMPRESSOR_ZSTD, level=9, reverse_dims=true, byteshuffle=true).compressor ==
        CompressorOptions(COMPRESSOR_NONE, 0, 8, false, false)
    @test_throws ArgumentError ZArray(fill(1.5); compressor=2)

    # by default arrays of 64 bytes or less are not compressed or shuffled
    @test ZArray(rand(Float64, 8)).compressor == CompressorOptions(COMPRESSOR_NONE, 0, 8, false, false)
    @test ZArray(rand(Float64, 9)).compressor == CompressorOptions(COMPRESSOR_ZSTD, 1, 8, false, true)
    @test ZArray(rand(UInt8, 64)).compressor == CompressorOptions(COMPRESSOR_NONE, 0, 1, false, false)
    @test ZArray(rand(UInt8, 65)).compressor == CompressorOptions(COMPRESSOR_ZSTD, 1, 1, false, false)
    @test ZArray(zeros(Float64, 100, 0)).compressor == CompressorOptions(COMPRESSOR_NONE, 0, 8, false, false)
    # an explicit compressor is used regardless of size
    @test ZArray(rand(Float64, 2); compressor=COMPRESSOR_ZSTD).compressor == CompressorOptions(COMPRESSOR_ZSTD, 1, 8, false, true)
    @test ZArray(data; compressor=COMPRESSOR_NONE).compressor == CompressorOptions(COMPRESSOR_NONE, 0, 4, false, false)
    # zero dimensional arrays are never compressed, even with large elements
    @test ZArray(fill(ntuple(Returns(0x00), 100))).compressor == CompressorOptions(COMPRESSOR_NONE, 0, 100, false, false)

    # the default level depends on the compressor
    @test ZArray(data; compressor=COMPRESSOR_NONE).compressor.level == 0
    @test ZArray(data; compressor=COMPRESSOR_ZSTD).compressor.level == 1

    @test_throws ArgumentError ZArray(data; compressor=2)
    @test ZArray(data; compressor=COMPRESSOR_ZSTD, level=100).compressor.level == 22
    @test_throws ArgumentError ZArray(data; chunks=(-2, 3))
    @test_throws ArgumentError ZArray(["not", "bits"])
    @test_throws ArgumentError ZArray(rand(Int128, 3))
end
