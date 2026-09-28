using SmallZarrGroups
using JSON3
using Test


@testset "basic type writing" begin
    tests = [
        Int64      => "\"<i8\"",
        Int32      => "\"<i4\"",
        Int16      => "\"<i2\"",
        Int8       => "\"|i1\"",
        UInt64     => "\"<u8\"",
        UInt32     => "\"<u4\"",
        UInt16     => "\"<u2\"",
        UInt8      => "\"|u1\"",
        Bool       => "\"|b1\"",
        Float64    => "\"<f8\"",
        Float32    => "\"<f4\"",
        Float16    => "\"<f2\"",
        ComplexF16 => "\"<c4\"",
        ComplexF32 => "\"<c8\"",
        ComplexF64 => "\"<c16\"",
        NTuple{0,UInt8} => "\"|V0\"",
        NTuple{55,UInt8} => "\"|V55\"",
    ]
    for (type, str) in tests
        @test sprint(SmallZarrGroups.write_type,type) == str
    end
end