# abstract type for codecs
abstract type Codec end
abstract type StringCodec <: Codec end
abstract type ArrayCodec <: Codec end

@kwdef struct BytesCodec <: ArrayCodec
    next::StringCodec
    is_big::Bool = false
end

@kwdef struct BloscCodec <: StringCodec
    next::StringCodec
    cname::String="lz4"
    clevel::Int=5
    shuffle::Int=1
    typesize::Int=1
    blocksize::Int=0
end

@kwdef struct PermuteDimsCodec <: ArrayCodec
    next::ArrayCodec
    order::Vector{Int}
end

# The final codec in the chain
struct StorageCodec <: StringCodec
end

function parse_codec(list, idx; default_typesize)::ArrayCodec
    if idx > length(list)
        error("codec parse: Final codec must decode a byte string")
    end
    top = list[idx]
    if top["name"] == "bytes"
        is_big = (
            haskey(top, "configuration") && 
            haskey(top["configuration"], "endian") &&
            top["configuration"]["endian"] == "big"
        )
        BytesCodec(;
            is_big,
            next=parse_string_codec(list, idx+1; default_typesize),
        )
    elseif top["name"] == "blosc"
        error("codec parse: $(top) codec must encode a byte string, instead got $(decoded_repr)")
    else
        error("$(top["name"]) not supported yet")
    end
end

function parse_string_codec(list, idx; default_typesize)::StringCodec
    if idx > length(list)
        return StorageCodec()
    end
    top = list[idx]
    next = parse_string_codec(list, idx+1; default_typesize=1)
    if top["name"] == "blosc"
        # parse blosc
        possible_values = (;
            cname= ("lz4", ["blosclz", "lz4", "lz4hc", "snappy", "zlib", "zstd"],),
            clevel= (5, 0:9,),
            shuffle= ("shuffle", ["noshuffle", "shuffle", "bitshuffle"],),
            blocksize= (0, 0:typemax(Int),),
            typesize= (default_typesize, typemin(Int):typemax(Int),),
        )
        use_default = false
        if haskey(top, "configuration")
            config = top["configuration"]
            for (key, (default, val_range)) in pairs(possible_values)
                if get(Returns(default), config, string(key)) ∉ val_range
                    return BloscCodec(;next)
                end
            end
            shuffle_str = get(Returns("shuffle"), config, "shuffle")
            shuffle = if shuffle_str == "shuffle"
                1
            elseif shuffle_str == "noshuffle"
                0
            elseif shuffle_str == "bitshuffle"
                2
            end
            return BloscCodec(;next,
                cname = get(Returns("lz4"), config, "cname"),
                clevel = get(Returns(5), config, "clevel"),
                shuffle,
                blocksize = get(Returns(0), config, "blocksize"),
                typesize = get(Returns(default_typesize), config, "typesize"),
            )
        else
            return BloscCodec(;next)
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