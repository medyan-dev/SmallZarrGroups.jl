"""
Native endian utf-32 character.
Also represents too high invalid code points from 0x10_FFFF to 0xFFFF_FFFF
Use `isvalid(c::CharUTF32)` to see if the character can be used in a valid UTF-8 string.

Has a defined fixed total order when compared to `Char`.
`CharUTF32` with value below or equal to 0x1F_FFFF are converted to `Char` when compared to `Char`.
`CharUTF32` with value above 0x1F_FFFF cannot be converted to `Char`. They are ordered after all `Char`.
"""
struct CharUTF32 <: AbstractChar
    value::UInt32
    CharUTF32(value::UInt32) = new(value)
end

function Base.codepoint(c::CharUTF32)
    # Not throwing errors if the code point is too high.
    # This enables fallbacks like `isascii` to work correctly.
    # c.value > 0x1F_FFFF && throw(Base.InvalidCharError(c))
    c.value
end

Base.typemax(::Type{CharUTF32}) = CharUTF32(typemax(UInt32))
Base.typemin(::Type{CharUTF32}) = CharUTF32(typemin(UInt32))

Base.IteratorSize(::Type{CharUTF32}) = Base.HasShape{0}()

Base.isless(x::CharUTF32, y::CharUTF32) = isless(x.value, y.value)

# values above 0x1F_FFFF are after all Char.
function Base.isless(x::Char, y::CharUTF32)
    if y.value ≤ 0x1F_FFFF
        isless(x, Char(y.value))
    else
        true
    end
end
function Base.isless(y::CharUTF32, x::Char)
    if y.value ≤ 0x1F_FFFF
        isless(Char(y.value),x)
    else
        false
    end
end

Base.:(==)(x::CharUTF32, y::CharUTF32) = x.value == y.value
function Base.:(==)(x::Char, y::CharUTF32)
    if y.value ≤ 0x1F_FFFF
        Char(y.value) == x
    else
        false
    end
end
function Base.:(==)(y::CharUTF32, x::Char)
    if y.value ≤ 0x1F_FFFF
        Char(y.value) == x
    else
        false
    end
end

function Base.hash(c::CharUTF32, h::UInt)
    if c.value ≤ 0x1F_FFFF
        hash(Char(c.value), h)
    else
        hash(c.value, h)
    end
end

function Base.write(io::IO, c::CharUTF32)
    write(io, UInt32(c))
end

function Base.read(io::IO, ::Type{CharUTF32})
    CharUTF32(read(io, UInt32))
end

function Base.show(io::IO, c::CharUTF32)
    if c.value ≤ 0x1F_FFFF
        print(io, typeof(c), '(')
        show(io, Char(c))
        print(io, ')')
    else
        print(io, typeof(c), '(', )
        show(io, c.value)
        print(io, ')')
    end
end