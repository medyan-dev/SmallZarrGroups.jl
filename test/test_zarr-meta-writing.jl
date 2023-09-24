using SmallZarrGroups
using JSON3
using Test

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
        ComplexF32 => '"'*NATIVE_ORDER*"c8\"",
        ComplexF64 => '"'*NATIVE_ORDER*"c16\"",
        NTuple{0,UInt8} => '"'*"|V0\"",
        NTuple{55,UInt8} => '"'*"|V55\"",
    ]
    for (type, str) in tests
        @test sprint(SmallZarrGroups.write_type,type) == str
    end
end