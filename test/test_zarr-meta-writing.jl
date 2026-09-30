using SmallZarrGroups
using SmallZarrGroups: append_zarr_dtype!, append_int!, zarray_json, parse_zarray, CompressorOptions, level_range
using SmallZarrGroups: COMPRESSOR_NONE, COMPRESSOR_ZSTD
using Random
using Test

@testset "append_zarr_dtype!" begin
    tests = [
        Int64 => "<i8",
        Int32 => "<i4",
        Int16 => "<i2",
        Int8 => "|i1",
        UInt64 => "<u8",
        UInt32 => "<u4",
        UInt16 => "<u2",
        UInt8 => "|u1",
        Bool => "|b1",
        Float64 => "<f8",
        Float32 => "<f4",
        Float16 => "<f2",
        ComplexF16 => "<c4",
        ComplexF32 => "<c8",
        ComplexF64 => "<c16",
        NTuple{0,UInt8} => "|V0",
        NTuple{1,UInt8} => "|V1",
        NTuple{55,UInt8} => "|V55",
    ]
    for (T, str) in tests
        @test append_zarr_dtype!(UInt8[], T) == codeunits(str)
    end
    @test_throws ArgumentError append_zarr_dtype!(UInt8[], Int128)
    @test_throws ArgumentError append_zarr_dtype!(UInt8[], NTuple{2,Int8})
end

@testset "append_int!" begin
    for x in [0, 7, 10, 123, -1, -10, typemax(Int64), Int32(-1)]
        @test String(append_int!(UInt8[], x)) == string(x)
    end
    @test String(append_int!(Vector{UInt8}("a"), 42)) == "a42"
end

@testset "zarray_json" begin
    c = CompressorOptions(COMPRESSOR_ZSTD, 1, 8, false, false)
    @test String(zarray_json(Float64, (10, 20), (5, 20), c)) ==
        """{"zarr_format":2,"fill_value":null,"chunks":[20,5],"order":"C","filters":null,""" *
        """"compressor":{"id":"zstd","level":1},"shape":[20,10],"dtype":"<f8"}"""
    c = CompressorOptions(COMPRESSOR_ZSTD, -1, 2, true, true)
    @test String(zarray_json(Int16, (), (), c)) ==
        """{"zarr_format":2,"fill_value":null,"chunks":[],"order":"F","filters":[{"id":"shuffle","elementsize":2}],""" *
        """"compressor":{"id":"zstd","level":-1},"shape":[],"dtype":"<i2"}"""
    @test occursin("\"compressor\":{\"id\":\"zstd\",\"level\":-131072},", String(zarray_json(UInt8, (1,), (1,), CompressorOptions(COMPRESSOR_ZSTD, -131072, 1, false, false))))
    @test occursin("\"compressor\":null,", String(zarray_json(UInt8, (1,), (1,), CompressorOptions(COMPRESSOR_NONE, 0, 1, false, false))))
    # no filter is written when shuffling does nothing
    @test occursin("\"filters\":null,", String(zarray_json(UInt8, (1,), (1,), CompressorOptions(COMPRESSOR_NONE, 0, 1, false, true))))
end

@testset "parse_zarray reads what zarray_json writes" begin
    for type in (COMPRESSOR_NONE, COMPRESSOR_ZSTD),
            level in extrema(level_range(type)),
            reverse_dims in (false, true),
            byteshuffle in (false, true),
            T in (Bool, Int16, ComplexF64, NTuple{3,UInt8})
        c = CompressorOptions(type, level, sizeof(T), reverse_dims, byteshuffle)
        meta = parse_zarray(zarray_json(T, (7, 0, 3), (2, 1, 3), c))
        @test meta.dtype === T
        @test meta.shape == [7, 0, 3]
        @test meta.chunks == [2, 1, 3]
        @test meta.compressor == c
    end
    # Edge cases, then random cases, of shape, chunks, element type, and compressor.
    cases = Any[
        (Float64, (), (), CompressorOptions(COMPRESSOR_NONE, 0, 8, false, false)),
        (UInt8, (0,), (1,), CompressorOptions(COMPRESSOR_NONE, 0, 1, false, false)),
        (Int64, (1,), (1,), CompressorOptions(COMPRESSOR_ZSTD, 22, 8, true, true)),
        (Int32, (5,), (10,), CompressorOptions(COMPRESSOR_ZSTD, -131072, 4, false, true)),
        (NTuple{0,UInt8}, (0, 0, 0), (1, 1, 1), CompressorOptions(COMPRESSOR_ZSTD, 0, 0, true, false)),
        (NTuple{300,UInt8}, (typemax(Int),), (typemax(Int),), CompressorOptions(COMPRESSOR_ZSTD, 9, 300, false, true)),
        (ComplexF16, (10, 1, 100), (3, 1, 7), CompressorOptions(COMPRESSOR_ZSTD, 0, 4, true, false)),
        (Bool, (1, 2, 3, 4), (4, 3, 2, 1), CompressorOptions(COMPRESSOR_NONE, 0, 1, true, true)),
        (Float16, (9, 10, 99, 100, 999, 1000), (1, 9, 10, 99, 100, 999), CompressorOptions(COMPRESSOR_ZSTD, 5, 2, false, false)),
        (Float64, (3, 4), (2, 2), CompressorOptions(COMPRESSOR_ZSTD, 1, 8, false, true)),
    ]
    rng = Xoshiro(1234)
    types = [Bool, Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64,
        Float16, Float32, Float64, ComplexF16, ComplexF32, ComplexF64, NTuple{0,UInt8}, NTuple{5,UInt8}, NTuple{10,UInt8}]
    rand_dim(rng, lo) = rand(rng, Bool) ? rand(rng, lo:10) : rand(rng, lo:typemax(Int))
    for _ in 1:200000
        T = rand(rng, types)
        type = rand(rng, (COMPRESSOR_NONE, COMPRESSOR_ZSTD))
        c = CompressorOptions(type, rand(rng, level_range(type)), sizeof(T), rand(rng, Bool), rand(rng, Bool))
        N = rand(rng, 0:5)
        push!(cases, (T, ntuple(_ -> rand_dim(rng, 0), N), ntuple(_ -> rand_dim(rng, 1), N), c))
    end
    for (T, shape, chunks, c) in cases
        meta = parse_zarray(zarray_json(T, shape, chunks, c))
        @test meta.dtype === T
        @test meta.shape == collect(Int, shape)
        @test meta.chunks == collect(Int, chunks)
        @test meta.compressor == c
        @test isnothing(meta.fill_value)
        @test meta.dimension_separator == '.'
    end
end
