import Blosc_jll

# The following constants should match those in blosc.h
const BLOSC_VERSION_FORMAT = 2
const BLOSC_MAX_OVERHEAD = 16

# Blosc is currently limited to 32-bit buffer sizes (Blosc/c-blosc#67)
const BLOSC_MAX_BUFFERSIZE = typemax(Cint) - BLOSC_MAX_OVERHEAD

import TranscodingStreams, CodecZlib, CodecBzip2

"""
Return the uncompressed data.
May return src if no compression was used, or buffer, if compression was used.

`src` is the compressed data.
`buffer` is a buffer used to avoid allocations, it may be resized and returned. 
"""
function decompress!(buffer::Vector{UInt8}, src::Vector{UInt8}, metadata::ParsedMetaData)::Vector{UInt8}
    expected_output_size = prod(metadata.chunks)*metadata.dtype.zarr_size
    @argcheck expected_output_size > 0
    if isnothing(metadata.compressor)
        return src
    end
    id = metadata.compressor.id
    if id == "blosc"
        numinternalthreads = 1
        buffer = Vector{UInt8}(undef, expected_output_size)
        sz = ccall((:blosc_decompress_ctx,Blosc_jll.libblosc), Cint,
        (Ptr{Cvoid},Ptr{Cvoid},Csize_t,Cint), src, buffer, expected_output_size, numinternalthreads)
        sz == expected_output_size || error("Blosc decompress error, compressed data is corrupted")
        buffer
    elseif id == "zlib"
        TranscodingStreams.transcode(CodecZlib.ZlibDecompressor, src)
    elseif id == "gzip"
        TranscodingStreams.transcode(CodecZlib.GzipDecompressor, src)
    elseif id == "bz2"
        TranscodingStreams.transcode(CodecBzip2.Bzip2Decompressor, src)
    else
        error("$(metadata.compressor.id) compressor not supported yet")
    end
end