using SmallZarrGroups
using JSON3
using Test
using StaticArrays
using StaticStrings

"Character for native byte order"
const NATIVE_ORDER = (ENDIAN_BOM == 0x04030201) ? '<' : '>'
const OTHER_ORDER = (ENDIAN_BOM == 0x04030201) ? '>' : '<'


@testset "basic type writing" begin
    tests = [
        Int64      => '"'*NATIVE_ORDER*"i8\"",
        Int32      => '"'*NATIVE_ORDER*"i4\"",
        Int16      => '"'*NATIVE_ORDER*"i2\"",
        Int8       => '"'*"|i1\"",
        UInt64     => '"'*NATIVE_ORDER*"u8\"",
        UInt32     => '"'*NATIVE_ORDER*"u4\"",
        UInt16     => '"'*NATIVE_ORDER*"u2\"",
        UInt8      => '"'*"|u1\"",
        Bool       => '"'*"|b1\"",
        Float64    => '"'*NATIVE_ORDER*"f8\"",
        Float32    => '"'*NATIVE_ORDER*"f4\"",
        Float16    => '"'*NATIVE_ORDER*"f2\"",
        ComplexF16 => '"'*NATIVE_ORDER*"c4\"",
        ComplexF32 => '"'*NATIVE_ORDER*"c8\"",
        ComplexF64 => '"'*NATIVE_ORDER*"c16\"",
        NTuple{0,UInt8} => '"'*"|V0\"",
        StaticString{0} => '"'*"|S0\"",
        NTuple{55,UInt8} => '"'*"|V55\"",
        StaticString{34} => '"'*"|S34\"",
        SVector{0,SmallZarrGroups.CharUTF32} => '"'*NATIVE_ORDER*"U0\"",
        SVector{27,SmallZarrGroups.CharUTF32} => '"'*NATIVE_ORDER*"U27\"",
        @NamedTuple{} => "[]",
        @NamedTuple{r::UInt8} => """[["r", "|u1"]]""",
        @NamedTuple{g::UInt64} => """[["g", "$(NATIVE_ORDER)u8"]]""",
        @NamedTuple{r::UInt8,g::UInt8,b::UInt8} => """[["r", "|u1"], ["g", "|u1"], ["b", "|u1"]]""",
        @NamedTuple{r::UInt8,g::SVector{27,SmallZarrGroups.CharUTF32},b::UInt8} => """[["r", "|u1"], ["g", "$(NATIVE_ORDER)U27"], ["b", "|u1"]]""",
        NamedTuple{(:foo, :bar), Tuple{Float32, @NamedTuple{baz::Float32, qux::Int32}}} => """[["foo", "$(NATIVE_ORDER)f4"], ["bar", [["baz", "$(NATIVE_ORDER)f4"], ["qux", "$(NATIVE_ORDER)i4"]]]]""",
        NamedTuple{(:x, :y, :z), Tuple{Float32, Float32, SMatrix{2,2,Float32,4}}} => """[["x", "$(NATIVE_ORDER)f4"], ["y", "$(NATIVE_ORDER)f4"], ["z", "$(NATIVE_ORDER)f4", [2, 2]]]""",
        NamedTuple{(:z,), Tuple{SArray{Tuple{},UInt8,0,1}}} => """[["z", "|u1", []]]""",
        NamedTuple{(:z,), Tuple{SArray{Tuple{0,},UInt8,1,0}}} => """[["z", "|u1", [0]]]""",
        NamedTuple{(:z,), Tuple{SArray{Tuple{1,},UInt8,1,1}}} => """[["z", "|u1", [1]]]""",
        NamedTuple{(:z,), Tuple{SArray{Tuple{2,3},UInt8,2,6}}} => """[["z", "|u1", [2, 3]]]""",
        NamedTuple{(:z,), Tuple{SArray{Tuple{2,3},NamedTuple{(:z,:b,), Tuple{UInt8,UInt16}},2,6}}} => """[["z", [["z", "|u1"], ["b", "<u2"]], [2, 3]]]""",
        NamedTuple{(:z,), Tuple{SArray{Tuple{2,3,2},UInt8,3,12}}} => """[["z", "|u1", [2, 3, 2]]]""",
    ]
    for (type, str) in tests
        @test sprint(SmallZarrGroups.write_type,type) == str
    end
end