using SmallZarrGroups
using JSON3
using Test

"Character for native byte order"
const NATIVE_ORDER = (ENDIAN_BOM == 0x04030201) ? '<' : '>'
const OTHER_ORDER = (ENDIAN_BOM == 0x04030201) ? '>' : '<'


@testset "basic type parsing" begin
    @testset "zero byte types" begin
        zerobytetype(t) = SmallZarrGroups.ParsedType(
            julia_type = t,
            type_size = 0,
            in_native_order = true,
        )
        tests = [
            "V0"=>NTuple{0,UInt8},
        ]
        for pair in tests
            for order in "<>|"
                type_str = order*pair[1]
                @test SmallZarrGroups.parse_zarr_type(type_str) == zerobytetype(pair[2])
            end
        end
    end
    @testset "one byte types" begin
        onebytetype(t) = SmallZarrGroups.ParsedType(
            julia_type = t,
            type_size = 1,
            in_native_order = true,
        )
        tests = [
            "b1"=>Bool,
            "i1"=>Int8,
            "u1"=>UInt8,
            "V1"=>NTuple{1,UInt8},
        ]
        for pair in tests
            for order in "<>|"
                type_str = order*pair[1]
                @test SmallZarrGroups.parse_zarr_type(type_str) == onebytetype(pair[2])
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
            @test SmallZarrGroups.parse_zarr_type(NATIVE_ORDER*pair[1]) == SmallZarrGroups.ParsedType(
                julia_type = t,
                type_size = s,
                in_native_order = true,
            )
            @test SmallZarrGroups.parse_zarr_type(OTHER_ORDER*pair[1]) == SmallZarrGroups.ParsedType(
                julia_type = t,
                type_size = s,
                in_native_order = false,
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
            @test SmallZarrGroups.parse_zarr_type(NATIVE_ORDER*pair[1]) == SmallZarrGroups.ParsedType(
                    julia_type = t,
                    type_size = s,
                    in_native_order = true,
            )
            @test SmallZarrGroups.parse_zarr_type(OTHER_ORDER*pair[1]) == SmallZarrGroups.ParsedType(
                julia_type = t,
                type_size = s,
                in_native_order = false,
            )
        end
    end
    @testset "static bytes types" begin
        staticstringtype(t,n) = SmallZarrGroups.ParsedType(
            julia_type = t{n},
            type_size = n,
            in_native_order = true,
        )
        for (typestr, t) in ("V" => (NTuple{N,UInt8} where N),)
            for n in 0:1050
                for order in "<>|"
                    @test SmallZarrGroups.parse_zarr_type(order*typestr*string(n)) == staticstringtype(t,n)
                end
            end
        end
        @test SmallZarrGroups.parse_zarr_type("|V100000") == staticstringtype((NTuple{N,UInt8} where N),100000)
    end
end


@testset "parsing fill value" begin
    tests = Any[
        (nothing, "$(NATIVE_ORDER)f8") => 0.0,
        (nothing, "|u1") => 0x00,
        ("NaN", "$(NATIVE_ORDER)f8") => NaN64,
        ("NaN", "$(NATIVE_ORDER)f4") => NaN32,
        ("NaN", "$(NATIVE_ORDER)f2") => NaN16,
        ("NaN", "$(OTHER_ORDER)f8") => NaN64,
        ("NaN", "$(OTHER_ORDER)f4") => NaN32,
        ("NaN", "$(OTHER_ORDER)f2") => NaN16,
        
        ("Infinity", "$(NATIVE_ORDER)f8") => Inf64,
        ("Infinity", "$(NATIVE_ORDER)f4") => Inf32,
        ("Infinity", "$(NATIVE_ORDER)f2") => Inf16,
        ("Infinity", "$(OTHER_ORDER)f8") => Inf64,
        ("Infinity", "$(OTHER_ORDER)f4") => Inf32,
        ("Infinity", "$(OTHER_ORDER)f2") => Inf16,

        ("-Infinity", "$(NATIVE_ORDER)f8") => -Inf64,
        ("-Infinity", "$(NATIVE_ORDER)f4") => -Inf32,
        ("-Infinity", "$(NATIVE_ORDER)f2") => -Inf16,
        ("-Infinity", "$(OTHER_ORDER)f8") => -Inf64,
        ("-Infinity", "$(OTHER_ORDER)f4") => -Inf32,
        ("-Infinity", "$(OTHER_ORDER)f2") => -Inf16,

        ("BBB=", "$(NATIVE_ORDER)f2") => reinterpret(Float16,[0x04, 0x10])[1],
        ("BBB=", "$(OTHER_ORDER)f2") => reinterpret(Float16,[0x10, 0x04])[1],

        (0, "$(NATIVE_ORDER)f2") => Float16(0.0),
        (1, "$(NATIVE_ORDER)u2") => 0x0001,
        (1.0, "$(NATIVE_ORDER)f2") => Float16(1.0),
        (1, "$(OTHER_ORDER)u2") => 0x0001,
        (1.0, "$(OTHER_ORDER)f2") => Float16(1.0),
        (1.5, "$(OTHER_ORDER)f2") => Float16(1.5),
    ]
    for testpair in tests
        dtype = SmallZarrGroups.parse_zarr_type(testpair[1][2])
        @test SmallZarrGroups.parse_zarr_fill_value(testpair[1][1], dtype) === testpair[2]
    end
end