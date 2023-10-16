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
            julia_size = 0,
            zarr_size = 0,
            byteorder = [],
            alignment = 0,
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
            julia_size = 1,
            zarr_size = 1,
            byteorder = [1],
            alignment = 0,
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
                julia_size = s,
                byteorder = 1:s,
                alignment = trailing_zeros(s),
            )
            @test SmallZarrGroups.parse_zarr_type(OTHER_ORDER*pair[1]) == SmallZarrGroups.ParsedType(
                julia_type = t,
                julia_size = s,
                byteorder = s:-1:1,
                alignment = trailing_zeros(s),
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
                    julia_size = s,
                    byteorder = 1:s,
                    alignment = trailing_zeros(hs),
            )
            @test SmallZarrGroups.parse_zarr_type(OTHER_ORDER*pair[1]) == SmallZarrGroups.ParsedType(
                julia_type = t,
                julia_size = s,
                byteorder = [(hs:-1:1); (s:-1:(hs+1));],
                alignment = trailing_zeros(hs),
            )
        end
    end
    @testset "static bytes types" begin
        staticstringtype(t,n) = SmallZarrGroups.ParsedType(
            julia_type = t{n},
            julia_size = n,
            byteorder = 1:n,
            alignment = 0,
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
    tests = [
        (nothing, "$(NATIVE_ORDER)f8") => zeros(UInt8, 8),
        (nothing, "|u1") => zeros(UInt8, 1),
        ("NaN", "$(NATIVE_ORDER)f8") => collect(reinterpret(UInt8,[NaN64])),
        ("NaN", "$(NATIVE_ORDER)f4") => collect(reinterpret(UInt8,[NaN32])),
        ("NaN", "$(NATIVE_ORDER)f2") => collect(reinterpret(UInt8,[NaN16])),
        ("NaN", "$(OTHER_ORDER)f8") => collect(reinterpret(UInt8,[NaN64])),
        ("NaN", "$(OTHER_ORDER)f4") => collect(reinterpret(UInt8,[NaN32])),
        ("NaN", "$(OTHER_ORDER)f2") => collect(reinterpret(UInt8,[NaN16])),
        
        ("Infinity", "$(NATIVE_ORDER)f8") => collect(reinterpret(UInt8,[Inf64])),
        ("Infinity", "$(NATIVE_ORDER)f4") => collect(reinterpret(UInt8,[Inf32])),
        ("Infinity", "$(NATIVE_ORDER)f2") => collect(reinterpret(UInt8,[Inf16])),
        ("Infinity", "$(OTHER_ORDER)f8") => collect(reinterpret(UInt8,[Inf64])),
        ("Infinity", "$(OTHER_ORDER)f4") => collect(reinterpret(UInt8,[Inf32])),
        ("Infinity", "$(OTHER_ORDER)f2") => collect(reinterpret(UInt8,[Inf16])),

        ("-Infinity", "$(NATIVE_ORDER)f8") => collect(reinterpret(UInt8,[-Inf64])),
        ("-Infinity", "$(NATIVE_ORDER)f4") => collect(reinterpret(UInt8,[-Inf32])),
        ("-Infinity", "$(NATIVE_ORDER)f2") => collect(reinterpret(UInt8,[-Inf16])),
        ("-Infinity", "$(OTHER_ORDER)f8") => collect(reinterpret(UInt8,[-Inf64])),
        ("-Infinity", "$(OTHER_ORDER)f4") => collect(reinterpret(UInt8,[-Inf32])),
        ("-Infinity", "$(OTHER_ORDER)f2") => collect(reinterpret(UInt8,[-Inf16])),

        ("BBB=", "$(NATIVE_ORDER)f2") => [0x04, 0x10],
        ("BBB=", "$(OTHER_ORDER)f2") => [0x10, 0x04],

        (0, "$(NATIVE_ORDER)f2") => [0x00, 0x00],
        (1, "$(NATIVE_ORDER)u2") => [0x01, 0x00],
        (1.0, "$(NATIVE_ORDER)f2") => [0x00, 0x3c],
        (1, "$(OTHER_ORDER)u2") => [0x01, 0x00],
        (1.0, "$(OTHER_ORDER)f2") => [0x00, 0x3c],
        (1.5, "$(OTHER_ORDER)f2") => [0x00, 0x3e],
    ]
    for testpair in tests
        dtype = SmallZarrGroups.parse_zarr_type(testpair[1][2])
        @test SmallZarrGroups.parse_zarr_fill_value(testpair[1][1], dtype) == testpair[2]
    end
end