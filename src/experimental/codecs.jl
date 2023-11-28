# abstract type for codecs
abstract type Codec end
abstract type StringCodec <: Codec end
abstract type ArrayCodec <: Codec end
abstract type CrossCodec <: Codec end

struct ReaderView
    reader::AbstractReader
    idx::Int
end

struct DecodedRepr
    shape::Union{Vector{Int}, Nothing} # nothing if string
    type::DataType # Original type if string
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

function parse_codec(list, idx, decoded_repr::DecodedRepr)::Codec
    # TODO should each datatype have its own default codec?
    if isempty(idx > length(list))
        if isnothing(decoded_repr.shape)
            return StorageCodec()
        else
            error("codec parse: Final codec must decode a byte string, instead got $(decoded_repr)")
        end
    end
    top = list[idx]
    if top["name"] == "bytes"
        if isnothing(decoded_repr.shape)
            error("codec parse: $(top) must encode an array, instead got a byte string")
        end
        if !(decoded_repr.type <: BytesCodecDataTypes)
            error("codec parse: $(top) must encode an $(BytesCodecDataTypes) array, instead got $(decoded_repr.type)")
        else
            is_big = (
                haskey(top, "configuration") && 
                haskey(top["configuration"], "endian") &&
                top["configuration"]["endian"] == "big"
            )
            BytesCodec(;
                is_big,
                next=parse_codec(list, idx+1, DecodedRepr(nothing,decoded_repr.type)),
            )
        end
    elseif top["name"] == "blosc"
        if isnothing(decoded_repr.shape)
            # parse blosc, this also sets defaults
            default_typesize = if isbitstype(decoded_repr.type)
                sizeof(decoded_repr.type)
            else
                1
            end
            possible_values = [
                ("cname", "lz4", ["blosclz", "lz4", "lz4hc", "snappy", "zlib", "zstd"]),
                ("clevel", 5, 0:9,),
                ("shuffle", 1, 0:2,),
                ("blocksize", 0, 0:typemax(Int),),
                ("typesize", default_typesize, typemin(Int):typemax(Int),),
            ]
            
        else
            error("codec parse: $(top) codec must encode a byte string, instead got $(decoded_repr)")
        end
    else
        error("$(top["name"]) not supported yet")
    end
end

function codec_get_array!(codec::BytesCodec, dest_view, s::ReaderView)::Nothing
    # allocate data to send chuck, of type eltype(dest_view)
    T = eltype(dest_view)
    buff_size = prod(size(dest_view))
    buff = zeros(T, buff_size)
    GC.@preserve buff codec_get_string!(
        codec.next,
        Base.unsafe_convert(Ptr{UInt8}, buff),
        UInt(sizeof(buff)),
        s,
    )
    # might need to flip endianness
    if codec.is_big ⊻ ENDIAN_BOM == 0x01020304
        for i in eachindex(buff)
            buff[i] = htol(ntoh(buff[i]))
        end
    end
    # copy into destination
    copy!(dest_view, reshape(buff, size(dest_view)))
    nothing
end

function codec_get_string!(codec::StringCodec, p::Ptr{UInt8}, n::UInt, s::ReaderView)::Nothing
    data::Vector{UInt8} = codec_get_string(codec, store_view)
    @argcheck length(data) == n
    GC.@preserve data Base.unsafe_copyto!(p, Base.unsafe_convert(Ptr{UInt8}, data), n)
    nothing
end

function codec_get_string(::StorageCodec, s::ReaderView)::Vector{UInt8}
    read_key_idx(store_view.reader, store_view.idx)
end