using SmallZarrGroups
using JSON3
using Test
using StaticArrays
using StaticStrings

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
            "S0"=>StaticString{0},
            "U0"=>SVector{0,SmallZarrGroups.CharUTF32},
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
            "S1"=>StaticString{1},
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
    @testset "datetime types" begin
        tests = [
            "M8[ns]",
            "m8[ns]",
            "M8[D]",
            "m8[D]",
        ]
        for teststr in tests
            @test SmallZarrGroups.parse_zarr_type(NATIVE_ORDER*teststr; silence_warnings=true) == SmallZarrGroups.ParsedType(
                julia_type = Int64,
                julia_size = 8,
                byteorder = 1:8,
                alignment = 3,
            )
            @test SmallZarrGroups.parse_zarr_type(OTHER_ORDER*teststr; silence_warnings=true) == SmallZarrGroups.ParsedType(
                julia_type = Int64,
                julia_size = 8,
                byteorder = 8:-1:1,
                alignment = 3,
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
        for (typestr, t) in ("S"=>StaticString, "V"=>(NTuple{N,UInt8} where N))
            for n in 0:1050
                for order in "<>|"
                    @test SmallZarrGroups.parse_zarr_type(order*typestr*string(n)) == staticstringtype(t,n)
                end
            end
        end
        @test SmallZarrGroups.parse_zarr_type("|S100000") == staticstringtype(StaticString,100000)
        @test SmallZarrGroups.parse_zarr_type("|V100000") == staticstringtype((NTuple{N,UInt8} where N),100000)
    end
    @testset "static 32bit char vector" begin
        @test SmallZarrGroups.parse_zarr_type(NATIVE_ORDER*"U1") == SmallZarrGroups.ParsedType(
            julia_type = SVector{1,SmallZarrGroups.CharUTF32},
            julia_size = 4,
            byteorder = 1:4,
            alignment = 2,
        )
        @test SmallZarrGroups.parse_zarr_type(NATIVE_ORDER*"U2") == SmallZarrGroups.ParsedType(
            julia_type = SVector{2,SmallZarrGroups.CharUTF32},
            julia_size = 8,
            byteorder = 1:8,
            alignment = 2,
        )
        @test SmallZarrGroups.parse_zarr_type(NATIVE_ORDER*"U3") == SmallZarrGroups.ParsedType(
            julia_type = SVector{3,SmallZarrGroups.CharUTF32},
            julia_size = 12,
            byteorder = 1:12,
            alignment = 2,
        )
        @test SmallZarrGroups.parse_zarr_type(NATIVE_ORDER*"U3000") == SmallZarrGroups.ParsedType(
            julia_type = SVector{3000,SmallZarrGroups.CharUTF32},
            julia_size = 12000,
            byteorder = 1:12000,
            alignment = 2,
        )
        @test SmallZarrGroups.parse_zarr_type(OTHER_ORDER*"U1") == SmallZarrGroups.ParsedType(
            julia_type = SVector{1,SmallZarrGroups.CharUTF32},
            julia_size = 4,
            byteorder = 4:-1:1,
            alignment = 2,
        )
        @test SmallZarrGroups.parse_zarr_type(OTHER_ORDER*"U2") == SmallZarrGroups.ParsedType(
            julia_type = SVector{2,SmallZarrGroups.CharUTF32},
            julia_size = 8,
            byteorder = [4,3,2,1,8,7,6,5],
            alignment = 2,
        )
        @test SmallZarrGroups.parse_zarr_type(OTHER_ORDER*"U3") == SmallZarrGroups.ParsedType(
            julia_type = SVector{3,SmallZarrGroups.CharUTF32},
            julia_size = 12,
            byteorder = [4,3,2,1,8,7,6,5,12,11,10,9],
            alignment = 2,
        )
        @test SmallZarrGroups.parse_zarr_type(OTHER_ORDER*"U5") == SmallZarrGroups.ParsedType(
            julia_type = SVector{5,SmallZarrGroups.CharUTF32},
            julia_size = 20,
            byteorder = [4,3,2,1,8,7,6,5,12,11,10,9,16,15,14,13,20,19,18,17],
            alignment = 2,
        )
    end
end


@testset "structured type parsing with no shape" begin
    read_parse(s) = SmallZarrGroups.parse_zarr_type(JSON3.read(s))
    @testset "zero fields" begin
        @test read_parse("[]") == SmallZarrGroups.ParsedType(
            julia_type = NamedTuple{(), Tuple{}},
            julia_size = 0,
            zarr_size = 0,
            byteorder = [],
            alignment = 0,
        )
    end
    @testset "one field" begin
        @test read_parse("""[["r", "|u1"]]""") == SmallZarrGroups.ParsedType(
            julia_type = @NamedTuple{r::UInt8},
            julia_size = 1,
            zarr_size = 1,
            byteorder = [1],
            alignment = 0,
        )
        @test read_parse("""[["g", "$(NATIVE_ORDER)u8"]]""") == SmallZarrGroups.ParsedType(
            julia_type = @NamedTuple{g::UInt64},
            julia_size = 8,
            zarr_size = 8,
            byteorder = 1:8,
            alignment = 3,
        )
        @test read_parse("""[["g", "$(OTHER_ORDER)u8"]]""") == SmallZarrGroups.ParsedType(
            julia_type = @NamedTuple{g::UInt64},
            julia_size = 8,
            zarr_size = 8,
            byteorder = 8:-1:1,
            alignment = 3,
        )
    end
    @testset "simple structs" begin
        @test read_parse("""[["r", "|u1"], ["g", "|u1"], ["b", "|u1"]]""") == SmallZarrGroups.ParsedType(
            julia_type = @NamedTuple{r::UInt8,g::UInt8,b::UInt8},
            julia_size = 3,
            zarr_size = 3,
            byteorder = 1:3,
            alignment = 0,
        )
    end
    @testset "struct alignment" begin
        @test read_parse("""[["r", "|u1"], ["g", "$(NATIVE_ORDER)u2"], ["b", "|u1"]]""") == SmallZarrGroups.ParsedType(
            julia_type = @NamedTuple{r::UInt8,g::UInt16,b::UInt8},
            julia_size = 6,
            zarr_size = 4,
            byteorder = [1,3,4,5],
            alignment = 1,
        )
        @test read_parse("""[["r", "|u1"], ["g", "|u1"], ["b", "$(NATIVE_ORDER)u2"]]""") == SmallZarrGroups.ParsedType(
            julia_type = @NamedTuple{r::UInt8,g::UInt8,b::UInt16},
            julia_size = 4,
            zarr_size = 4,
            byteorder = 1:4,
            alignment = 1,
        )
        @test read_parse("""[["r", "|u1"], ["g", "$(NATIVE_ORDER)u4"], ["b", "$(OTHER_ORDER)u2"]]""") == SmallZarrGroups.ParsedType(
            julia_type = @NamedTuple{r::UInt8,g::UInt32,b::UInt16},
            julia_size = 12,
            zarr_size = 7,
            byteorder = [1,5,6,7,8,10,9],
            alignment = 2,
        )
    end
    @testset "nested structs" begin
        @test read_parse("""[["foo", "$(NATIVE_ORDER)f4"], ["bar", [["baz", "$(NATIVE_ORDER)f4"], ["qux", "$(NATIVE_ORDER)i4"]]]]""") == SmallZarrGroups.ParsedType(
            julia_type = NamedTuple{(:foo, :bar), Tuple{Float32, @NamedTuple{baz::Float32, qux::Int32}}},
            julia_size = 12,
            zarr_size = 12,
            byteorder = 1:12,
            alignment = 2,
        )
    end
end

@testset "structured type parsing with shape" begin
    read_parse(s) = SmallZarrGroups.parse_zarr_type(JSON3.read(s))
    @testset "zarr example" begin
        @test read_parse("""[["x", "$(NATIVE_ORDER)f4"], ["y", "$(NATIVE_ORDER)f4"], ["z", "$(NATIVE_ORDER)f4", [2, 2]]]""") == SmallZarrGroups.ParsedType(
            julia_type = NamedTuple{(:x, :y, :z), Tuple{Float32, Float32, SMatrix{2,2,Float32,4}}},
            julia_size = 24,
            zarr_size = 24,
            byteorder = [1,2,3,4, 5,6,7,8, 9,10,11,12, 17,18,19,20, 13,14,15,16, 21,22,23,24,],
            alignment = 2,
        )
    end
    @testset "zero dimensions" begin
        @test read_parse("""[["z", "|u1", []]]""") == SmallZarrGroups.ParsedType(
            julia_type = NamedTuple{(:z,), Tuple{SArray{Tuple{},UInt8,0,1}}},
            julia_size = 1,
            zarr_size = 1,
            byteorder = [1],
            alignment = 0,
        )
    end
    @testset "zero size" begin
        @test read_parse("""[["z", "|u1", [0]]]""") == SmallZarrGroups.ParsedType(
            julia_type = NamedTuple{(:z,), Tuple{SArray{Tuple{0,},UInt8,1,0}}},
            julia_size = 0,
            zarr_size = 0,
            byteorder = [],
            alignment = 0,
        )
    end
    @testset "one size" begin
        @test read_parse("""[["z", "|u1", [1]]]""") == SmallZarrGroups.ParsedType(
            julia_type = NamedTuple{(:z,), Tuple{SArray{Tuple{1,},UInt8,1,1}}},
            julia_size = 1,
            zarr_size = 1,
            byteorder = [1],
            alignment = 0,
        )
    end
    @testset "non square matrix" begin
        @test read_parse("""[["z", "|u1", [2,3]]]""") == SmallZarrGroups.ParsedType(
            julia_type = NamedTuple{(:z,), Tuple{SArray{Tuple{2,3},UInt8,2,6}}},
            julia_size = 6,
            zarr_size = 6,
            byteorder = [1,3,5,2,4,6],
            alignment = 0,
        )
    end
    @testset "non square matrix alignment" begin
        @test read_parse("""[["z", [["z", "|u1"],["b", "<u2"]], [2,3]]]""") == SmallZarrGroups.ParsedType(
            julia_type = NamedTuple{(:z,), Tuple{SArray{Tuple{2,3},NamedTuple{(:z,:b,), Tuple{UInt8,UInt16}},2,6}}},
            julia_size = 24,
            zarr_size = 18,
            byteorder = [1,3,4, 9,11,12, 17,19,20, 5,7,8, 13,15,16, 21,23,24],
            alignment = 1,
        )
    end
    @testset "3d shape" begin
        @test read_parse("""[["z", "|u1", [2,3,2]]]""") == SmallZarrGroups.ParsedType(
            julia_type = NamedTuple{(:z,), Tuple{SArray{Tuple{2,3,2},UInt8,3,12}}},
            julia_size = 12,
            zarr_size = 12,
            byteorder = [1,7,3,9,5,11,2,8,4,10,6,12],
            alignment = 0,
        )
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
        ("BBBBCC==", JSON3.read("""[["r", "|u1"], ["g", "$(NATIVE_ORDER)u2"], ["b", "|u1"]]""")) => [0x04,0x00,0x10,0x41,0x08,0x00],
        ("BBBBCC==", JSON3.read("""[["r", "|u1"], ["g", "$(OTHER_ORDER)u2"], ["b", "|u1"]]""")) => [0x04,0x00,0x41,0x10,0x08,0x00],

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