# abstract type for codecs
abstract type Codec end
abstract type StringCodec <: Codec end
abstract type ArrayCodec <: Codec end
abstract type CrossCodec <: Codec end

struct DecodedRepr
    shape::Union{Vector{Int}, Nothing} # nothing if string
    type::DataType # UInt8 if string
end

@kwdef struct BytesCodec <: CrossCodec
    next::StringCodec
    is_big::Bool = false
end

const BytesCodecDataTypes = Union{
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

@kwdef struct BloscCodec <: StringCodec
    next::StringCodec
    cname::String
    clevel::Int
    shuffle::Int
    typesize::Int
    blocksize::Int
end

@kwdef struct PermuteDimsCodec <: ArrayCodec
    next::Union{ArrayCodec, CrossCodec}
    order::Vector{Int}
end

# The final codec in the chain
struct StorageCodec <: StringCodec
end

function parse_codec(list, decoded_repr::DecodedRepr)::Codec
    # TODO should each datatype have its own default codec?
    if isempty(list)
        if isnothing(decoded_repr.shape)
            return StorageCodec()
        else
            error("codec parse: Final codec must decode a byte string, instead got $(decoded_repr)")
        end
    end
    top = list[1]
    if top["name"] == "bytes"
        if isnothing(decoded_repr.shape)
            error("codec parse: $(top) must encode an array, instead got a byte string")
        end
        if !(decoded_repr.type <: BytesCodecDataTypes)
            error("codec parse: $(top) must encode an $(BytesCodecDataTypes) array, instead got $(decoded_repr.type)")
        else
            BytesCodec(;
                is_big=get(top, "endian", "") == "big",
                next=parse_codec(list[2:end], DecodedRepr(nothing,UInt8)),
            )
        end
    else
        error("$(top["name"]) not supported yet")
    end
end

# dest_view and store_view must not alias
function codec_get_data!(codec::BytesCodec, dest_view, store_view)::Nothing
    #check if dest_view is 
    codec_get_data!(codec.next, dest_ptr, store_view)
end