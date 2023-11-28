import Blosc_jll

# The following constants should match those in blosc.h
const BLOSC_VERSION_FORMAT = 2
const BLOSC_MAX_OVERHEAD = 16

# Blosc is currently limited to 32-bit buffer sizes (Blosc/c-blosc#67)
const BLOSC_MAX_BUFFERSIZE = typemax(Cint) - BLOSC_MAX_OVERHEAD

import TranscodingStreams, CodecZlib

"""
Uncompressed the data.
"""
@noinline function unsafe_decompress!(p::Ptr{UInt8}, n::Int, src::Vector{UInt8}, compressor)::Nothing
    @argcheck n > 0
    if !isnothing(compressor) && compressor.id == "blosc"
        numinternalthreads = 1
        sz = ccall((:blosc_decompress_ctx,Blosc_jll.libblosc), Cint,
        (Ptr{Cvoid},Ptr{Cvoid},Csize_t,Cint), src, p, n, numinternalthreads)
        sz == n || error("Blosc decompress error, compressed data is corrupted")
        return
    end
    r = if isnothing(compressor)
        src
    else
        id = compressor.id
        if id == "zlib"
            TranscodingStreams.transcode(CodecZlib.ZlibDecompressor, src)
        elseif id == "gzip"
            TranscodingStreams.transcode(CodecZlib.GzipDecompressor, src)
        else
            error("$(id) compressor not supported yet")
        end
    end
    @argcheck length(r) == n
    GC.@preserve r Base.unsafe_copyto!(p, Base.unsafe_convert(Ptr{UInt8}, r), n)
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
        numinternalthreads = 1
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
        blocksize::Int = get(Returns(0), compressor, "blocksize")
        @argcheck length(src) ≤ BLOSC_MAX_BUFFERSIZE
        dest = Vector{UInt8}(undef, BLOSC_MAX_OVERHEAD + length(src))
        sz = ccall((:blosc_compress_ctx,Blosc_jll.libblosc), Cint,
            (Cint, Cint, Csize_t, Csize_t, Ptr{Cvoid}, Ptr{Cvoid}, Csize_t, Cstring, Csize_t, Cint), 
            clevel, doshuffle, elsize, length(src), src, dest, length(dest), cname, blocksize, numinternalthreads
        )
        sz == 0 && error("Blosc cannot compress")
        sz < 0 && error("Internal Blosc error. This
            should never happen.  If you see this, please report it back
            together with the buffer data causing this and compression settings.
        ")
        resize!(dest, sz)
    elseif compressor.id == "zlib"
        level::Int = get(Returns(1), compressor, "level")
        zlib_codec =  CodecZlib.ZlibCompressor(;level)
        TranscodingStreams.initialize(zlib_codec)
        try
            TranscodingStreams.transcode(zlib_codec, src)
        finally
            TranscodingStreams.finalize(zlib_codec)
        end
    else
        # This should be unreachable because 
        # unknown compressors will be normalized to 
        # uncompressed when saving.
        error("compressor not implemented yet") # COV_EXCL_LINE
    end
end