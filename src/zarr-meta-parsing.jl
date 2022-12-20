# parse zarr meta data

using ArgCheck
import JSON3
import Base64

"""
Zarr Version 2 Array meta data
https://zarr.readthedocs.io/en/stable/spec/v2.html#arrays
"""
Base.@kwdef struct ParsedMetaData
    shape::Vector{Int}
    chunks::Vector{Int}
    dtype::ParsedType
    compressor::Union{Nothing, JSON3.Object}
    fill_value::Vector{UInt8}
    is_column_major::Bool
    is_dot_sep::Bool=true
end

function parse_zarr_metadata(metadata::JSON3.Object)::ParsedMetaData
    @argcheck metadata["zarr_format"] == 2
    shape = collect(Int, metadata["shape"])
    chunks = collect(Int, metadata["chunks"])
    @argcheck length(shape)==length(chunks)
    @argcheck all(≥(0), shape)
    @argcheck all(≥(0), chunks)
    if all(>(0), shape)
        @argcheck all(>(0), chunks)
    end
    dtype = parse_zarr_type(metadata["dtype"])
    compressor = metadata["compressor"]
    @argcheck isnothing(compressor) || compressor.id == "blosc"
    fill_value = parse_zarr_fill_value(metadata["fill_value"], dtype)
    order = metadata["order"]
    @argcheck order in ("C", "F")
    is_column_major = order == "F"
    dimension_separator = get(Returns("."), metadata, "dimension_separator")
    is_dot_sep = dimension_separator == "."
    ParsedMetaData(;
        shape,
        chunks,
        dtype,
        compressor,
        fill_value,
        is_column_major,
        is_dot_sep,
    )
end
