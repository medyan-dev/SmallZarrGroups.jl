

"""
Write a julia type as a zarr type string
"""
function write_type(io::IO, t::Type)
    if t <: Bool
        print(io, "\"|b1\"")
    elseif t <: Int8
        print(io, "\"|i1\"")
    elseif t <: Int16
        print(io, "\"", NATIVE_ORDER, "i2\"")
    elseif t <: Int32
        print(io, "\"", NATIVE_ORDER, "i4\"")
    elseif t <: Int64
        print(io, "\"", NATIVE_ORDER, "i8\"")
    elseif t <: UInt8
        print(io, "\"|u1\"")
    elseif t <: UInt16
        print(io, "\"", NATIVE_ORDER, "u2\"")
    elseif t <: UInt32
        print(io, "\"", NATIVE_ORDER, "u4\"")
    elseif t <: UInt64
        print(io, "\"", NATIVE_ORDER, "u8\"")
    elseif t <: Float16
        print(io, "\"", NATIVE_ORDER, "f2\"")
    elseif t <: Float32
        print(io, "\"", NATIVE_ORDER, "f4\"")
    elseif t <: Float64
        print(io, "\"", NATIVE_ORDER, "f8\"")
    elseif t <: ComplexF16
        print(io, "\"", NATIVE_ORDER, "c4\"")
    elseif t <: ComplexF32
        print(io, "\"", NATIVE_ORDER, "c8\"")
    elseif t <: ComplexF64
        print(io, "\"", NATIVE_ORDER, "c16\"")
    elseif t <: (NTuple{N,UInt8} where N)
        print(io, "\"|V", sizeof(t), "\"")
    else
        error("type $t cannot be saved in a zarr array")
    end

end