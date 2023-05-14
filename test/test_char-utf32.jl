# Based on tests in Julia "test/char.jl: # This file is a part of Julia. License is MIT: https://julialang.org/license"

using SmallZarrGroups
using Test

const C32 = SmallZarrGroups.CharUTF32

@testset "CharUTF32" begin


@testset "basic properties" begin
    @test typemax(C32) == C32(0xffffffff)
    @test typemin(C32) == C32(0)
    @test ndims(C32) == 0
    @test getindex(C32('a'), 1) == C32('a')
    @test_throws BoundsError getindex(C32('a'), 2)
    # This is current behavior, but it seems questionable
    @test getindex(C32('a'), 1, 1, 1) == C32('a')
    @test_throws BoundsError getindex(C32('a'), 1, 1, 2)

    @test C32('b') + 1 == C32('c')
    @test typeof(C32('b') + 1) == C32
    @test 1 + C32('b') == C32('c')
    @test typeof(1 + C32('b')) == C32
    @test C32('b') - 1 == C32('a')
    @test typeof(C32('b') - 1) == C32

    @test widen(C32('a')) === C32('a')
end

@testset "ASCII conversion to/from Integer" begin
    numberchars = C32.(['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'])
    lowerchars = C32.(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'])
    upperchars = C32.(['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'])
    plane1_playingcards = C32.(['🂠', '🂡', '🂢', '🂣', '🂤', '🂥', '🂦', '🂧', '🂨', '🂩', '🂪', '🂫', '🂬', '🂭', '🂮'])
    plane2_cjkpart1 = C32.(['𠀀', '𠀁', '𠀂', '𠀃', '𠀄', '𠀅', '𠀆', '𠀇', '𠀈', '𠀉', '𠀊', '𠀋', '𠀌', '𠀍', '𠀎', '𠀏'])

    testarrays = [numberchars; lowerchars; upperchars; plane1_playingcards; plane2_cjkpart1]

    #Integer(x::C32) = Int(x)
    #tests ASCII 48 - 57
    counter = 48
    for x in numberchars
        @test Integer(x) == counter
        @test Char(x) == x
        @test Integer(Char(x)) == counter
        counter += 1
    end

    #tests ASCII 65 - 90
    counter = 65
    for x in upperchars
        @test Integer(x) == counter
        @test Char(x) == x
        @test Integer(Char(x)) == counter
        counter += 1
    end

    #tests ASCII 97 - 122
    counter = 97
    for x in lowerchars
        @test Integer(x) == counter
        @test Char(x) == x
        @test Integer(Char(x)) == counter
        counter += 1
    end

    #tests Unicode plane 1: 127136 - 127150
    counter = 127136
    for x in plane1_playingcards
        @test Integer(x) == counter
        @test Char(x) == x
        @test Integer(Char(x)) == counter
        counter += 1
    end

    #tests Unicode plane 2: 131072 - 131087
    counter = 131072
    for x in plane2_cjkpart1
        @test Integer(x) == counter
        @test Char(x) == x
        @test Integer(Char(x)) == counter
        counter += 1
    end

    for x = 1:9
        @test convert(C32, Float16(x)) == convert(C32, Float32(x)) == convert(C32, Float64(x)) == C32(x) == Char(x)
    end

    for x in testarrays
        @test size(x) == ()
        @test_throws BoundsError size(x,0)
        @test size(x,1) == 1
    end

    #ndims(c::Char) = 0
    for x in testarrays
        @test ndims(x) == 0
    end

    #length(c::Char) = 1
    for x in testarrays
        @test length(x) == 1
    end

    #lastindex(c::Char) = 1
    for x in testarrays
        @test lastindex(x) == 1
    end

    #getindex(c::Char) = c
    for x in testarrays
        @test getindex(x) == x
        @test getindex(x, CartesianIndex()) == x
    end

    #first(c::Char) = c
    for x in testarrays
        @test first(x) == x
    end

    #last(c::Char) = c
    for x in testarrays
        @test last(x) == x
    end

    #eltype(c::C32) = C32
    for x in testarrays
        @test eltype(x) == C32
    end

    #iterate(c::Char)
    for x in testarrays
        @test iterate(x)[1] == x
        @test iterate(x, iterate(x)[2]) == nothing
    end

    #isless(x::Char, y::Integer) = isless(UInt32(x), y)
    for T in (Char, C32)
        for x in upperchars
            @test isless(x, T(91)) == true
        end

        for x in lowerchars
            @test isless(x, T(123)) == true
        end

        for x in numberchars
            @test isless(x, T(66)) == true
        end

        for x in plane1_playingcards
            @test isless(x, T(127151)) == true
        end

        for x in plane2_cjkpart1
            @test isless(x, T(131088)) == true
        end

        #isless(x::Integer, y::Char) = isless(x, UInt32(y))
        for x in upperchars
            @test isless(T(64), x) == true
        end

        for x in lowerchars
            @test isless(T(96), x) == true
        end

        for x in numberchars
            @test isless(T(47), x) == true
        end

        for x in plane1_playingcards
            @test isless(T(127135), x) == true
        end

        for x in plane2_cjkpart1
            @test isless(T(131071), x) == true
        end
    end

    @test !isequal(C32('x'), 120)
    @test convert(Signed, C32('A')) === Int32(65)
    @test convert(Unsigned, C32('A')) === UInt32(65)
end

@testset "issue #14573" begin
    array = C32.(['a', 'b', 'c']) + [1, 2, 3]
    @test array == ['b', 'd', 'f']
    @test eltype(array) == C32

    array = [1, 2, 3] + C32.(['a', 'b', 'c'])
    @test array == ['b', 'd', 'f']
    @test eltype(array) == C32

    array = C32.(['a', 'b', 'c']) - [0, 1, 2]
    @test array == ['a', 'a', 'a']
    @test eltype(array) == C32
end

@testset "sprint, repr" begin
    @test sprint(show, "text/plain", C32('$')) == "SmallZarrGroups.CharUTF32('\$'): ASCII/Unicode U+0024 (category Sc: Symbol, currency)"
    @test sprint(show, "text/plain", C32('$'), context=:compact => true) == "CharUTF32('\$')"
    @test repr(C32('$')) == "SmallZarrGroups.CharUTF32('\$')"
end

@testset "reading and writing" begin
    # writes 4 bytes per char, in native endian byte order.
    test_chars = [C32('a'), C32('\U0010ffff')]
    for a in test_chars
        local iob = IOBuffer()
        @test write(iob, C32('a')) == 4
        seekstart(iob)
        @test read(iob, C32) == 'a'
        seekstart(iob)
        @test read(iob, UInt32) == UInt32('a')
    end
end

@testset "abstractchar" begin
    @test C32('x') === C32(UInt32('x'))
    @test convert(C32, 2.0) == Char(2)

    @test isascii(C32('x'))
    @test C32('x') < 'y'
    @test C32('x') == 'x' === Char(C32('x')) === convert(Char, C32('x'))
    @test C32('x')^3 == "xxx"
    @test repr(C32('x')) == "SmallZarrGroups.CharUTF32('x')"
    @test string(C32('x')) == "x"
    @test length(C32('x')) == 1
    @test !isempty(C32('x'))
    @test eltype(C32) == C32
    @test_throws EOFError read(IOBuffer("x"), C32)
    @test_throws MethodError ncodeunits(C32('x'))
    @test hash(C32('x'), UInt(10)) == hash('x', UInt(10))
    @test Base.IteratorSize(C32) == Base.HasShape{0}()
    @test convert(C32, 1) == Char(1)
end

@testset "broadcasting of Char" begin
    @test identity.(C32('a')) == 'a'
    @test C32('a') .* [C32('b'), C32('c')] == ["ab", "ac"]
end

@testset "code point format of U+ syntax (PR 33291)" begin
    @test repr("text/plain", C32('\n')) == "SmallZarrGroups.CharUTF32('\\n'): ASCII/Unicode U+000A (category Cc: Other, control)"
    @test isascii(C32('\n'))
    @test isvalid(C32('\n'))
    @test repr("text/plain", C32('/')) == "SmallZarrGroups.CharUTF32('/'): ASCII/Unicode U+002F (category Po: Punctuation, other)"
    @test isascii(C32('/'))
    @test isvalid(C32('/'))
    @test repr("text/plain", C32('\u10e')) == "SmallZarrGroups.CharUTF32('Ď'): Unicode U+010E (category Lu: Letter, uppercase)"
    @test !isascii(C32('\u10e'))
    @test isvalid(C32('\u10e'))
    @test repr("text/plain", C32('\u3a2c')) == "SmallZarrGroups.CharUTF32('㨬'): Unicode U+3A2C (category Lo: Letter, other)"
    @test !isascii(C32('\u3a2c'))
    @test isvalid(C32('\u3a2c'))
    @test repr("text/plain", C32('\udf00')) == "SmallZarrGroups.CharUTF32('\\udf00'): Unicode U+DF00 (category Cs: Other, surrogate)"
    @test !isascii(C32('\udf00'))
    @test !isvalid(C32('\udf00'))
    @test repr("text/plain", C32('\U001f428')) == "SmallZarrGroups.CharUTF32('🐨'): Unicode U+1F428 (category So: Symbol, other)"
    @test !isascii(C32('\U001f428'))
    @test isvalid(C32('\U001f428'))
    @test repr("text/plain", C32('\U010f321')) == "SmallZarrGroups.CharUTF32('\\U10f321'): Unicode U+10F321 (category Co: Other, private use)"
    @test !isascii(C32('\U010f321'))
    @test isvalid(C32('\U010f321'))
    @test repr("text/plain", C32(0x00_10_ff_ff)) == "SmallZarrGroups.CharUTF32('\\U10ffff'): Unicode U+10FFFF (category Cn: Other, not assigned)"
    @test !isascii(C32(0x00_10_ff_ff))
    @test isvalid(C32(0x00_10_ff_ff))
    @test repr("text/plain", C32(0x00_1f_ff_ff)) == "SmallZarrGroups.CharUTF32('\\U1fffff'): Unicode U+1FFFFF (category In: Invalid, too high)"
    @test !isascii(C32(0x00_1f_ff_ff))
    @test !isvalid(C32(0x00_1f_ff_ff))
    @test repr("text/plain", C32(0x00_20_00_00)) == "SmallZarrGroups.CharUTF32(0x00200000): Unicode U+200000 (category In: Invalid, too high)"
    @test !isascii(C32(0x00_20_00_00))
    @test !isvalid(C32(0x00_20_00_00))
    @test repr("text/plain", C32(0xff_ff_ff_ff)) == "SmallZarrGroups.CharUTF32(0xffffffff): Unicode U+FFFFFFFF (category In: Invalid, too high)"
    @test !isascii(C32(0xff_ff_ff_ff))
    @test !isvalid(C32(0xff_ff_ff_ff))
end

@testset "errors on converting to Char" begin
    @test Char(C32('a')) === 'a'
    @test Char(C32(0x1F_FF_FF)) === Char(0x1F_FF_FF)
    @test_throws Base.CodePointError{UInt32}(0x00200000) Char(C32(0x00200000))
    @test_throws Base.CodePointError{UInt32}(0xFFFFFFFF) Char(C32(0xFFFFFFFF))
    @test String([C32('a'),C32('b')]) == "ab"
    @test_throws Base.CodePointError{UInt32}(0x00200000) String([C32('a'),C32(0x00200000)])
end

@testset "total ordering" begin
    local test_values = sort(Union{Char,C32}[
        Char(0),
        C32(0),
        Char(0x57),
        C32(0x57),
        reinterpret(Char, 0x00_00_00_01),
        Char(0x1F_FF_FF),
        reinterpret(Char, 0x1F_FF_FF_01),
        C32(0x1F_FF_FF),
        C32(0x00_20_00_00),
        C32(0xff_ff_ff_ff),
        reinterpret(Char, 0xff_ff_ff_ff),
        "\xc0\x80"[1],
        reinterpret(Char, 0x57_00_00_01),
        C32('\U001f428'),
        '\U001f428',
    ])
    local n = length(test_values)
    for i in 1:n
        for j in 1:n
            x = test_values[i]
            y = test_values[j]
            @test isequal(x, y) === isequal(y, x)
            if isequal(x, y)
                @test hash(x) === hash(y)
            end
            @test isequal(x, y) + isless(x, y) + isless(y, x) == 1
            if i < j
                @test isequal(x, y) | isless(x, y)
            else
                @test isequal(x, y) | isless(y, x)
            end
        end
    end
    for i in 1:n
        for j in 1:n
            for k in 1:n
                x = test_values[i]
                y = test_values[j]
                z = test_values[k]
                if isless(x, y) && isless(y, z)
                    isless(x, z)
                end
            end
        end
    end
end

end # @testset "CharUTF32"