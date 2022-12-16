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
        )
        tests = [
            "S0"=>StaticString{0},
            "U0"=>SVector{0,Char},
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
            )
            @test StorageTrees.parse_zarr_type(OTHER_ORDER*pair[1]) == StorageTrees.ParsedType(
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
            @test StorageTrees.parse_zarr_type(NATIVE_ORDER*pair[1]) == StorageTrees.ParsedType(
                    julia_type = t,
                    julia_size = s,
                    byteorder = 1:s,
                    alignment = trailing_zeros(hs),
            )
            @test StorageTrees.parse_zarr_type(OTHER_ORDER*pair[1]) == StorageTrees.ParsedType(
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
            @test StorageTrees.parse_zarr_type(NATIVE_ORDER*teststr; silence_warnings=true) == StorageTrees.ParsedType(
                julia_type = Int64,
                julia_size = 8,
                byteorder = 1:8,
                alignment = 3,
            )
            @test StorageTrees.parse_zarr_type(OTHER_ORDER*teststr; silence_warnings=true) == StorageTrees.ParsedType(
                julia_type = Int64,
                julia_size = 8,
                byteorder = 8:-1:1,
                alignment = 3,
            )
        end
    end
    @testset "static bytes types" begin
        staticstringtype(t,n) = StorageTrees.ParsedType(
            julia_type = t{n},
            julia_size = n,
            byteorder = 1:n,
            alignment = 0,
        )
        for (typestr, t) in ("S"=>StaticString, "V"=>(NTuple{N,UInt8} where N))
            for n in 0:1050
                for order in "<>|"
                    @test StorageTrees.parse_zarr_type(order*typestr*string(n)) == staticstringtype(t,n)
                end
            end
        end
        @test StorageTrees.parse_zarr_type("|S100000") == staticstringtype(StaticString,100000)
        @test StorageTrees.parse_zarr_type("|V100000") == staticstringtype((NTuple{N,UInt8} where N),100000)
    end
    @testset "static 32bit char vector" begin
        @test StorageTrees.parse_zarr_type(NATIVE_ORDER*"U1") == StorageTrees.ParsedType(
            julia_type = SVector{1,Char},
            julia_size = 4,
            byteorder = 1:4,
            alignment = 2,
        )
        @test StorageTrees.parse_zarr_type(NATIVE_ORDER*"U2") == StorageTrees.ParsedType(
            julia_type = SVector{2,Char},
            julia_size = 8,
            byteorder = 1:8,
            alignment = 2,
        )
        @test StorageTrees.parse_zarr_type(NATIVE_ORDER*"U3") == StorageTrees.ParsedType(
            julia_type = SVector{3,Char},
            julia_size = 12,
            byteorder = 1:12,
            alignment = 2,
        )
        @test StorageTrees.parse_zarr_type(NATIVE_ORDER*"U3000") == StorageTrees.ParsedType(
            julia_type = SVector{3000,Char},
            julia_size = 12000,
            byteorder = 1:12000,
            alignment = 2,
        )
        @test StorageTrees.parse_zarr_type(OTHER_ORDER*"U1") == StorageTrees.ParsedType(
            julia_type = SVector{1,Char},
            julia_size = 4,
            byteorder = 4:-1:1,
            alignment = 2,
        )
        @test StorageTrees.parse_zarr_type(OTHER_ORDER*"U2") == StorageTrees.ParsedType(
            julia_type = SVector{2,Char},
            julia_size = 8,
            byteorder = [4,3,2,1,8,7,6,5],
            alignment = 2,
        )
        @test StorageTrees.parse_zarr_type(OTHER_ORDER*"U3") == StorageTrees.ParsedType(
            julia_type = SVector{3,Char},
            julia_size = 12,
            byteorder = [4,3,2,1,8,7,6,5,12,11,10,9],
            alignment = 2,
        )
        @test StorageTrees.parse_zarr_type(OTHER_ORDER*"U5") == StorageTrees.ParsedType(
            julia_type = SVector{5,Char},
            julia_size = 20,
            byteorder = [4,3,2,1,8,7,6,5,12,11,10,9,16,15,14,13,20,19,18,17],
            alignment = 2,
        )
    end
end


@testset "structured type parsing with no shape" begin
    read_parse(s) = StorageTrees.parse_zarr_type(JSON3.read(s))
    @testset "zero fields" begin
        @test read_parse("[]") == StorageTrees.ParsedType(
            julia_type = NamedTuple{(), Tuple{}},
            julia_size = 0,
            zarr_size = 0,
            byteorder = [],
            alignment = 0,
        )
    end
    @testset "one field" begin
        @test read_parse("""[["r", "|u1"]]""") == StorageTrees.ParsedType(
            julia_type = @NamedTuple{r::UInt8},
            julia_size = 1,
            zarr_size = 1,
            byteorder = [1],
            alignment = 0,
        )
        @test read_parse("""[["g", "$(NATIVE_ORDER)u8"]]""") == StorageTrees.ParsedType(
            julia_type = @NamedTuple{g::UInt64},
            julia_size = 8,
            zarr_size = 8,
            byteorder = 1:8,
            alignment = 3,
        )
        @test read_parse("""[["g", "$(OTHER_ORDER)u8"]]""") == StorageTrees.ParsedType(
            julia_type = @NamedTuple{g::UInt64},
            julia_size = 8,
            zarr_size = 8,
            byteorder = 8:-1:1,
            alignment = 3,
        )
    end
    @testset "simple structs" begin
        @test read_parse("""[["r", "|u1"], ["g", "|u1"], ["b", "|u1"]]""") == StorageTrees.ParsedType(
            julia_type = @NamedTuple{r::UInt8,g::UInt8,b::UInt8},
            julia_size = 3,
            zarr_size = 3,
            byteorder = 1:3,
            alignment = 0,
        )
    end
    @testset "struct alignment" begin
        @test read_parse("""[["r", "|u1"], ["g", "$(NATIVE_ORDER)u2"], ["b", "|u1"]]""") == StorageTrees.ParsedType(
            julia_type = @NamedTuple{r::UInt8,g::UInt16,b::UInt8},
            julia_size = 6,
            zarr_size = 4,
            byteorder = [1,3,4,5],
            alignment = 1,
        )
        @test read_parse("""[["r", "|u1"], ["g", "|u1"], ["b", "$(NATIVE_ORDER)u2"]]""") == StorageTrees.ParsedType(
            julia_type = @NamedTuple{r::UInt8,g::UInt8,b::UInt16},
            julia_size = 4,
            zarr_size = 4,
            byteorder = 1:4,
            alignment = 1,
        )
        @test read_parse("""[["r", "|u1"], ["g", "$(NATIVE_ORDER)u4"], ["b", "$(OTHER_ORDER)u2"]]""") == StorageTrees.ParsedType(
            julia_type = @NamedTuple{r::UInt8,g::UInt32,b::UInt16},
            julia_size = 12,
            zarr_size = 7,
            byteorder = [1,5,6,7,8,10,9],
            alignment = 2,
        )
    end
    @testset "nested structs" begin
        @test read_parse("""[["foo", "$(NATIVE_ORDER)f4"], ["bar", [["baz", "$(NATIVE_ORDER)f4"], ["qux", "$(NATIVE_ORDER)i4"]]]]""") == StorageTrees.ParsedType(
            julia_type = NamedTuple{(:foo, :bar), Tuple{Float32, @NamedTuple{baz::Float32, qux::Int32}}},
            julia_size = 12,
            zarr_size = 12,
            byteorder = 1:12,
            alignment = 2,
        )
    end
end