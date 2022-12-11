using StorageTrees
using JSON3
using Test
using StaticArrays
using StaticStrings

"Character for native byte order"
const NATIVE_ORDER = (ENDIAN_BOM == 0x04030201) ? '<' : '>'
const OTHER_ORDER = (ENDIAN_BOM == 0x04030201) ? '>' : '<'


@testset "basic type parsing" begin
    @testset "zero byte types" begin
        zerobytetype(t) = StorageTrees.ParsedType(
            julia_type = t,
            julia_size = 0,
            zarr_size = 0,
            byteorder = [],
            alignment = 0,
            just_copy = true,
        )
        tests = [
            "S0"=>StaticString{0},
            "U0"=>NTuple{0,Char},
            "V0"=>NTuple{0,UInt8},
        ]
        for pair in tests
            for order in "<>|"
                type_str = order*pair[1]
                @test StorageTrees.parse_zarr_type(type_str) == zerobytetype(pair[2])
            end
        end
    end
    @testset "one byte types" begin
        onebytetype(t) = StorageTrees.ParsedType(
            julia_type = t,
            julia_size = 1,
            zarr_size = 1,
            byteorder = [1],
            alignment = 0,
            just_copy = true,
        )
        tests = [
            "b1"=>Bool,
            "i1"=>Int8,
            "u1"=>UInt8,
            "S1"=>StaticString{1},
            "V1"=>NTuple{1,UInt8},
        ]
        for pair in tests
            for order in "<>|"
                type_str = order*pair[1]
                @test StorageTrees.parse_zarr_type(type_str) == onebytetype(pair[2])
            end
        end
    end
    @testset "int and float types" begin
        tests = [
            "i2"=>(Int16),
            "i4"=>(Int32),
            "i8"=>(Int64),
            "u2"=>(UInt16),
            "u4"=>(UInt32),
            "u8"=>(UInt64),
            "f2"=>(Float16),
            "f4"=>(Float32),
            "f8"=>(Float64),
        ]
        for pair in tests
            t = pair[2]
            s = sizeof(t)
            @test StorageTrees.parse_zarr_type(NATIVE_ORDER*pair[1]) == StorageTrees.ParsedType(
                julia_type = t,
                julia_size = s,
                byteorder = 1:s,
                alignment = trailing_zeros(s),
                just_copy = true,
            )
            @test StorageTrees.parse_zarr_type(OTHER_ORDER*pair[1]) == StorageTrees.ParsedType(
                julia_type = t,
                julia_size = s,
                byteorder = s:-1:1,
                alignment = trailing_zeros(s),
                just_copy = false,
            )
        end
    end
    @testset "complex types" begin
        tests = [
            "c4"=>ComplexF16,
            "c8"=>ComplexF32,
            "c16"=>ComplexF64,
        ]
        for pair in tests
            t = pair[2]
            s = sizeof(t)
            hs = s÷2
            @test StorageTrees.parse_zarr_type(NATIVE_ORDER*pair[1]) == StorageTrees.ParsedType(
                    julia_type = t,
                    julia_size = s,
                    byteorder = 1:s,
                    alignment = trailing_zeros(hs),
                    just_copy = true,
            )
            @test StorageTrees.parse_zarr_type(OTHER_ORDER*pair[1]) == StorageTrees.ParsedType(
                julia_type = t,
                julia_size = s,
                byteorder = [(hs:-1:1); (s:-1:(hs+1));],
                alignment = trailing_zeros(hs),
                just_copy = false,
            )
        end
    end
    @testset "datetime types" begin
        tests = [
            "M8[ns]",
            "m8[ns]",
        ]
        for teststr in tests
            @test StorageTrees.parse_zarr_type(NATIVE_ORDER*teststr) == StorageTrees.ParsedType(
                julia_type = Int64,
                julia_size = 8,
                byteorder = 1:8,
                alignment = 3,
                just_copy = true,
            )
            @test StorageTrees.parse_zarr_type(OTHER_ORDER*teststr) == StorageTrees.ParsedType(
                julia_type = Int64,
                julia_size = 8,
                byteorder = 8:-1:1,
                alignment = 3,
                just_copy = false,
            )
        end
    end
end