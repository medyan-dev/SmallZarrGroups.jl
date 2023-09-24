const ZDataTypes = Union{
    Bool,
    Int8,
    Int16,
    Int32,
    Int64,
    UInt8,
    UInt16,
    UInt32,
    UInt64,
    Float16,
    Float32,
    Float64,
    ComplexF32,
    ComplexF64,
    NTuple{N, UInt8} where N,
}

function isvalidtype(T::Type)::Bool
    isbitstype(T) && ((T <: ZDataTypes))
end



zarr_data_type(t::Type{Bool}) = "bool"
zarr_fill_value(t::Type{Bool}) = false

zarr_data_type(t::Type{Int8}) = "int8"
zarr_data_type(t::Type{Int16}) = "int16"
zarr_data_type(t::Type{Int32}) = "int32"
zarr_data_type(t::Type{Int64}) = "int64"
zarr_data_type(t::Type{UInt8}) = "uint8"
zarr_data_type(t::Type{UInt16}) = "uint16"
zarr_data_type(t::Type{UInt32}) = "uint32"
zarr_data_type(t::Type{UInt64}) = "uint64"
zarr_fill_value(t::Type{<:Integer}) = 0

zarr_data_type(t::Type{Float32}) = "float32"
zarr_data_type(t::Type{Float64}) = "float64"
zarr_fill_value(t::Type{<:AbstractFloat}) = "NaN"

zarr_data_type(t::Type{ComplexF32}) = "complex64"
zarr_data_type(t::Type{ComplexF64}) = "complex128"
zarr_fill_value(t::Type{<:Complex}) = ["NaN", "NaN"]

zarr_data_type(t::Type{NTuple{N,UInt8}}) where N = "r$(N*8)"
zarr_fill_value(t::Type{NTuple{N,UInt8}}) where N = zeros(UInt8, N)