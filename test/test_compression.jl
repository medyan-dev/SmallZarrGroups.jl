using SmallZarrGroups
using SmallZarrGroups: CompressorOptions, level_range, default_level, compress, decompress!
using SmallZarrGroups: COMPRESSOR_NONE, COMPRESSOR_ZSTD
using Test

const ALL_COMPRESSORS = (COMPRESSOR_NONE, COMPRESSOR_ZSTD)

@testset "level_range and default_level" begin
    @test level_range(COMPRESSOR_NONE) == 0:0
    @test level_range(COMPRESSOR_ZSTD) == -131072:22
    @test default_level(COMPRESSOR_NONE) == 0
    @test default_level(COMPRESSOR_ZSTD) == 1
    for type in (-1, 2)
        @test_throws ArgumentError level_range(type)
        @test_throws ArgumentError default_level(type)
    end
end

@testset "CompressorOptions" begin
    c = CompressorOptions(COMPRESSOR_ZSTD, 9, 8, true, false)
    @test (c.type, c.level, c.itemsize, c.reverse_dims, c.byteshuffle) === (COMPRESSOR_ZSTD, Int32(9), Int32(8), true, false)
    # levels are clamped
    @test CompressorOptions(COMPRESSOR_NONE, 1, 8, false, false).level == 0
    @test CompressorOptions(COMPRESSOR_ZSTD, -200000, 8, false, false).level == -131072
    @test CompressorOptions(COMPRESSOR_ZSTD, 23, 8, false, false).level == 22
    @test CompressorOptions(COMPRESSOR_ZSTD, big(2)^70, 8, false, false).level == 22
    @test_throws ArgumentError CompressorOptions(2, 0, 8, false, false)
    @test_throws ArgumentError CompressorOptions(COMPRESSOR_NONE, 0, -1, false, false)
    @test_throws ArgumentError CompressorOptions(COMPRESSOR_NONE, 0, 2^31, false, false)
end

@testset "CompressorOptions byteshuffle" begin
    @test CompressorOptions(COMPRESSOR_NONE, 0, 2, false, true).byteshuffle
    @test !CompressorOptions(COMPRESSOR_NONE, 0, 2, false, false).byteshuffle
    # Shuffling does nothing for element sizes of one or zero bytes.
    @test !CompressorOptions(COMPRESSOR_NONE, 0, 1, false, true).byteshuffle
    @test !CompressorOptions(COMPRESSOR_NONE, 0, 0, false, true).byteshuffle
end

@testset "compress and decompress!" begin
    src = repeat(rand(UInt8, 100), 10)
    # zstd has too many levels to test them all.
    test_levels(type) = type == COMPRESSOR_ZSTD ? (-131072, -100, -1, 0, 1, 3, 22) : level_range(type)
    for type in ALL_COMPRESSORS, level in test_levels(type), itemsize in (1, 8)
        c = CompressorOptions(type, level, itemsize, false, false)
        dst = zeros(UInt8, length(src))
        decompress!(c, dst, compress(c, src))
        @test dst == src
    end
    @test compress(CompressorOptions(COMPRESSOR_NONE, 0, 1, false, false), src) == src
    for type in ALL_COMPRESSORS
        c = CompressorOptions(type, default_level(type), 1, false, false)
        @test_throws "decoded size" decompress!(c, zeros(UInt8, 10), compress(c, zeros(UInt8, 11)))
    end
end
