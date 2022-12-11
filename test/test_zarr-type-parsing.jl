using StorageTrees
using JSON3
using Test
using StaticArrays
using StaticStrings

"Character for native byte order"
const native_order = ENDIAN_BOM == 0x04030201 ? '<' : '>'
const other_order = ENDIAN_BOM == 0x04030201 ? '>' : '<'


@testset "basic type parsing" begin
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
end