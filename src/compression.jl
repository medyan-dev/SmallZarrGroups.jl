using ChunkCodecLibBlosc: BloscEncodeOptions, BloscCodec
using ChunkCodecLibZlib: ZlibEncodeOptions, ZlibCodec, GzipCodec
using ChunkCodecCore: encode, try_decode!, NoopCodec

"""
Uncompressed the data.
"""
function decompress!(dst::AbstractVector{UInt8}, src::Vector{UInt8}, compressor)::Nothing
    n = length(dst)
    decoded_n = if isnothing(compressor)
        try_decode!(NoopCodec(), dst, src)
    elseif compressor.id == "blosc"
        try_decode!(BloscCodec(), dst, src)
    elseif compressor.id == "zlib"
        try_decode!(ZlibCodec(), dst, src)
    elseif compressor.id == "gzip"
        try_decode!(GzipCodec(), dst, src)
    else
        error("$(compressor.id) compressor not supported yet")
    end::Int64
    @argcheck decoded_n == n
    nothing
end

"""
Normalize compressor
"""
normalize_compressor(compressor)::Nothing = nothing

function normalize_compressor(compressor::JSON3.Object)::Union{Nothing, JSON3.Object}
    if !haskey(compressor, "id")
        @warn "compressor id missing, saving data uncompressed"
        return nothing
    end
    if compressor.id == "blosc"
        possible_values = [
            ("cname", "lz4", ["blosclz", "lz4", "lz4hc", "snappy", "zlib", "zstd"]),
            ("clevel", 5, 0:9,),
            ("shuffle", 1, -1:2,),
            ("blocksize", 0, 0:typemax(Int),),
        ]
        for (key, default, val_range) in possible_values
            if get(Returns(default), compressor, key) ∉ val_range
                @warn "blosc $key not in $val_range, saving data uncompressed"
                return nothing
            end
        end
        return compressor
    end
    if compressor.id == "zlib"
        if get(Returns(1), compressor, "level") ∉ -1:9
            @warn "zlib level not in -1:9, saving data uncompressed"
            return nothing
        end
        return compressor
    end
    @warn "compressor $(compressor.id) not implemented yet, saving data uncompressed"
    return nothing
end

"""
Return the compressed data, or `src` if no compression used.
"""
function compress(compressor::Nothing, src::Vector{UInt8}, elsize::Int)::Vector{UInt8}
    return src
end

function compress(compressor::JSON3.Object, src::Vector{UInt8}, elsize::Int)::Vector{UInt8}
    if compressor.id == "blosc"
        clevel::Int = get(Returns(5), compressor, "clevel")
        shuffle::Int = get(Returns(1), compressor, "shuffle")
        doshuffle::Int = if shuffle == -1
            if elsize == 1
                2
            else
                1
            end
        else
            shuffle
        end
        cname::String = get(Returns("lz4"), compressor, "cname")
        encode(BloscEncodeOptions(;clevel, compressor=cname, doshuffle, typesize=elsize), src)
    elseif compressor.id == "zlib"
        level::Int = get(Returns(1), compressor, "level")
        encode(ZlibEncodeOptions(;level), src)
    else
        # This should be unreachable because 
        # unknown compressors will be normalized to 
        # uncompressed when saving.
        error("compressor not implemented yet") # COV_EXCL_LINE
    end
end