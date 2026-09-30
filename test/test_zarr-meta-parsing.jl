using SmallZarrGroups
using SmallZarrGroups: parse_zarr_dtype, parse_zarr_fill_value, parse_zarray, CompressorOptions
using SmallZarrGroups: COMPRESSOR_NONE, COMPRESSOR_ZLIB, COMPRESSOR_GZIP, COMPRESSOR_BLOSC_LZ4
using JSON
using Test

@testset "parse_zarr_dtype" begin
    # one byte types allow any byte order
    for (str, T) in ["b1"=>Bool, "i1"=>Int8, "u1"=>UInt8, "V0"=>NTuple{0,UInt8}, "V1"=>NTuple{1,UInt8}]
        for byteorder in "<>|"
            @test parse_zarr_dtype(byteorder*str) === T
        end
    end
    # larger types must be little endian
    for (str, T) in [
            "i2"=>Int16, "i4"=>Int32, "i8"=>Int64,
            "u2"=>UInt16, "u4"=>UInt32, "u8"=>UInt64,
            "f2"=>Float16, "f4"=>Float32, "f8"=>Float64,
            "c4"=>ComplexF16, "c8"=>ComplexF32, "c16"=>ComplexF64,
        ]
        @test parse_zarr_dtype("<"*str) === T
        @test_throws ArgumentError parse_zarr_dtype(">"*str)
        @test_throws ArgumentError parse_zarr_dtype("|"*str)
    end
    for n in 0:1050, byteorder in "<>|"
        @test parse_zarr_dtype(byteorder*"V"*string(n)) === NTuple{n,UInt8}
    end
    @test parse_zarr_dtype("|V100000") === NTuple{100000,UInt8}
    for str in ["", "<f", "<f3", "<i16", "<b2", "<U4", "<M8[ns]", "=f8", "<fx"]
        @test_throws ArgumentError parse_zarr_dtype(str)
    end
end

@testset "parse_zarr_fill_value" begin
    tests = [
        (Float64, nothing) => 0.0,
        (UInt8, nothing) => 0x00,
        (NTuple{2,UInt8}, nothing) => (0x00, 0x00),
        (NTuple{0,UInt8}, nothing) => (),
        (NTuple{2,UInt8}, 0) => (0x00, 0x00),
        (NTuple{0,UInt8}, 0) => (),
        (Float64, "NaN") => NaN64,
        (Float32, "NaN") => NaN32,
        (Float16, "NaN") => NaN16,
        (Float64, "Infinity") => Inf64,
        (Float32, "Infinity") => Inf32,
        (Float16, "Infinity") => Inf16,
        (Float64, "-Infinity") => -Inf64,
        (Float32, "-Infinity") => -Inf32,
        (Float16, "-Infinity") => -Inf16,
        (Float16, "BBB=") => reinterpret(Float16, 0x1004),
        (UInt16, "BBB=") => 0x1004,
        (NTuple{2,UInt8}, "BBB=") => (0x04, 0x10),
        (Float16, 0) => Float16(0.0),
        (UInt16, 1) => 0x0001,
        (Float16, 1.0) => Float16(1.0),
        (Bool, true) => true,
        (Bool, 1) => true,
        (Bool, 0) => false,
        (UInt64, big(typemax(UInt64))) => typemax(UInt64),
        (ComplexF64, [1.5, -2.0]) => ComplexF64(1.5, -2.0),
        (ComplexF32, Any[0.0, 0.0]) => ComplexF32(0.0, 0.0),
        (ComplexF64, Any[0, 1]) => ComplexF64(0.0, 1.0),
        (ComplexF16, Any["NaN", "-Infinity"]) => ComplexF16(NaN16, -Inf16),
    ]
    for ((T, fill_value), expected) in tests
        @test parse_zarr_fill_value(T, fill_value) === expected
    end
    @test_throws ArgumentError parse_zarr_fill_value(UInt16, "AA==")
    @test_throws ArgumentError parse_zarr_fill_value(Float64, [1.0, 2.0])
    @test_throws ArgumentError parse_zarr_fill_value(ComplexF64, [1.0])
    @test_throws ArgumentError parse_zarr_fill_value(ComplexF64, [1.0, 2.0, 3.0])
    @test_throws InexactError parse_zarr_fill_value(UInt8, -1)
end

const BASE_ZARRAY = Dict{String,Any}(
    "zarr_format" => 2,
    "shape" => [4, 6],
    "chunks" => [2, 3],
    "dtype" => "<f8",
    "fill_value" => nothing,
    "order" => "C",
    "compressor" => nothing,
    "filters" => nothing,
)

"""
Parse `BASE_ZARRAY` with the keyword arguments replacing its keys.
"""
function parse_with(; kwargs...)
    parse_zarray(Vector{UInt8}(JSON.json(merge(BASE_ZARRAY, Dict(string(k) => v for (k, v) in kwargs)))))
end

@testset "parse_zarray" begin
    meta = parse_with()
    @test meta.dtype === Float64
    @test meta.shape == [6, 4]
    @test meta.chunks == [3, 2]
    @test isnothing(meta.fill_value)
    @test meta.dimension_separator == '.'
    @test meta.compressor == CompressorOptions(COMPRESSOR_NONE, 0, 8, false, false)
    @test parse_with(fill_value="NaN").fill_value == "NaN"
    @test parse_with(extra_key=[1, 2]).dtype === Float64

    @testset "array keys" begin
        @test parse_with(order="F").compressor.reverse_dims
        @test parse_with(dimension_separator="/").dimension_separator == '/'
        # chunk sizes of 0 are allowed in arrays with no elements, and are normalized to 1
        @test parse_with(shape=[0, 6], chunks=[0, 3]).shape == [6, 0]
        @test parse_with(shape=[0, 6], chunks=[0, 3]).chunks == [3, 1]
        @test parse_with(shape=[], chunks=[]).shape == []
        for bad in [
                (; zarr_format=3),
                (; order="K"),
                (; order="CF"),
                (; dimension_separator="-"),
                (; dimension_separator="//"),
                (; shape=[4], chunks=[2, 3]),
                (; shape=[-1, 6]),
                (; chunks=[-1, 3]),
                (; chunks=[0, 3]),
                (; dtype="<f3"),
            ]
            @test_throws ArgumentError parse_with(; bad...)
        end
        missing_order = filter(p -> p.first != "order", BASE_ZARRAY)
        @test_throws ArgumentError parse_zarray(Vector{UInt8}(JSON.json(missing_order)))
    end

    @testset "compressor" begin
        compressor(json) = parse_with(;compressor=json).compressor
        c = compressor(Dict("id" => "zlib", "level" => 3))
        @test (c.type, c.level) == (COMPRESSOR_ZLIB, 3)
        c = compressor(Dict("id" => "gzip", "level" => -1))
        @test (c.type, c.level) == (COMPRESSOR_GZIP, -1)
        # Any blosc becomes lz4, and blosc's internal shuffle is ignored.
        c = compressor(Dict("id" => "blosc", "cname" => "zstd", "clevel" => 7, "shuffle" => 2, "blocksize" => 64))
        @test c == CompressorOptions(COMPRESSOR_BLOSC_LZ4, 7, 8, false, false)
        # Levels are clamped, or the default if they are missing or null.
        @test compressor(Dict("id" => "zlib")).level == 1
        levels = [nothing => 1, 3 => 3, 100 => 9, -5 => -1, 2.0 => 2]
        for (level, expected) in levels
            @test compressor(Dict("id" => "zlib", "level" => level)).level == expected
        end
        # Levels that aren't integers are rejected.
        @test_throws InexactError compressor(Dict("id" => "zlib", "level" => 2.5))
        @test_throws InexactError compressor(Dict("id" => "zlib", "level" => big(2)^70))
        @test_throws MethodError compressor(Dict("id" => "zlib", "level" => "5"))
        @test compressor(Dict("id" => "blosc", "clevel" => 100)).level == 9
        @test compressor(Dict("id" => "blosc")).level == 5
        @test_throws "ja3sfdsdhgw compressor not supported yet" compressor(Dict("id" => "ja3sfdsdhgw"))
        @test_throws "field `id` has no default" compressor(Dict("level" => 1))
    end

    @testset "filters" begin
        @test !parse_with(filters=[]).compressor.byteshuffle
        @test parse_with(filters=[Dict("id" => "shuffle", "elementsize" => 8)]).compressor.byteshuffle
        # shuffling 1 byte elements does nothing, so it's normalized away
        @test !parse_with(dtype="|u1", filters=[Dict("id" => "shuffle", "elementsize" => 1)]).compressor.byteshuffle
        @test_throws "elementsize" parse_with(filters=[Dict("id" => "shuffle", "elementsize" => 4)])
        @test_throws "elementsize" parse_with(filters=[Dict("id" => "shuffle")])
        @test_throws "field `id` has no default" parse_with(filters=[Dict("elementsize" => 8)])
        @test_throws "delta filter not supported" parse_with(filters=[Dict("id" => "delta", "dtype" => "<f8")])
        shuffle = Dict("id" => "shuffle", "elementsize" => 8)
        @test_throws "single shuffle filter" parse_with(filters=[shuffle, shuffle])
    end
end
