"""
A character that matches the python Py_UCS4 bit layout.
This is utf-32 encoded in native endian.
"""
struct CharUTF32 <: AbstractChar
    value::UInt32
    CharUTF32(value::UInt32) = new(value)
end

Base.ncodeunits(c::CharUTF32) = 1

function Base.codepoint(c::CharUTF32)
    # c.value > 0x1F_FFFF && throw(Base.InvalidCharError(c))
    c.value
end

Base.typemax(::Type{CharUTF32}) = typemax(UInt32)
Base.typemin(::Type{CharUTF32}) = typemin(UInt32)

Base.IteratorSize(::Type{CharUTF32}) = HasShape{0}()

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