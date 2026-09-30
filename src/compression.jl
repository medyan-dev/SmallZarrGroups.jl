# Compressor options, and compressing chunk bytes.

using ChunkCodecCore: ChunkCodecCore, encode, decode!, NoopEncodeOptions, NoopDecodeOptions
using ChunkCodecLibBlosc: BloscEncodeOptions, BloscDecodeOptions, BLOSC_LZ4
using ChunkCodecLibZlib: ZlibEncodeOptions, ZlibDecodeOptions, GzipEncodeOptions, GzipDecodeOptions

# Compressor ids.
const COMPRESSOR_NONE = Int32(0)
const COMPRESSOR_ZLIB = Int32(1)
const COMPRESSOR_GZIP = Int32(2)
const COMPRESSOR_BLOSC_LZ4 = Int32(3)

const DEFAULT_COMPRESSOR = COMPRESSOR_BLOSC_LZ4

"""
    level_range(type::Integer)::UnitRange{Int32}

Return the valid compression levels for compressor `type`.
"""
function level_range(type::Integer)::UnitRange{Int32}
    if type == COMPRESSOR_NONE
        Int32(0):Int32(0)
    elseif type == COMPRESSOR_ZLIB || type == COMPRESSOR_GZIP
        Int32(-1):Int32(9)
    elseif type == COMPRESSOR_BLOSC_LZ4
        Int32(0):Int32(9)
    else
        throw(ArgumentError("unknown compressor type $(type)"))
    end
end

"""
    default_level(type::Integer)::Int32

Return the default compression level for compressor `type`.
"""
function default_level(type::Integer)::Int32
    if type == COMPRESSOR_NONE
        Int32(0)
    elseif type == COMPRESSOR_ZLIB || type == COMPRESSOR_GZIP
        Int32(1)
    elseif type == COMPRESSOR_BLOSC_LZ4
        Int32(5)
    else
        throw(ArgumentError("unknown compressor type $(type)"))
    end
end

"""
    CompressorOptions(type, level, itemsize, reverse_dims, byteshuffle)

How the chunks of an array are encoded and decoded.

- `type`: compressor id, one of `COMPRESSOR_NONE`, `COMPRESSOR_ZLIB`, `COMPRESSOR_GZIP`, or `COMPRESSOR_BLOSC_LZ4`.
- `level`: compression level, clamped to `level_range(type)`.
- `itemsize`: size of the array elements in bytes.
- `reverse_dims`: if `true`, chunk data is stored with dimensions reversed
    relative to Julia's memory layout, Zarr `"F"` order.
- `byteshuffle`: if `true`, the numcodecs shuffle filter is applied before compressing.
    Always `false` when `itemsize ≤ 1`, where shuffling does nothing.
"""
struct CompressorOptions
    type::Int32
    level::Int32
    itemsize::Int32
    reverse_dims::Bool
    byteshuffle::Bool
    function CompressorOptions(
            type::Integer,
            level::Integer,
            itemsize::Integer,
            reverse_dims::Bool,
            byteshuffle::Bool,
        )
        @argcheck itemsize in 0:typemax(Int32)
        new(type, clamp(level, level_range(type)), itemsize, reverse_dims, byteshuffle && itemsize > 1)
    end
end

"""
Return `src` compressed with the compressor in `c`.
"""
function compress(c::CompressorOptions, src::AbstractVector{UInt8})::Vector{UInt8}
    if c.type == COMPRESSOR_NONE
        encode(NoopEncodeOptions(), src)
    elseif c.type == COMPRESSOR_ZLIB
        encode(ZlibEncodeOptions(; level=c.level), src)
    elseif c.type == COMPRESSOR_GZIP
        encode(GzipEncodeOptions(; level=c.level), src)
    elseif c.type == COMPRESSOR_BLOSC_LZ4
        encode(BloscEncodeOptions(; clevel=c.level, doshuffle=1, typesize=c.itemsize, compcode=BLOSC_LZ4), src)
    else
        error("unreachable") # COV_EXCL_LINE
    end
end

"""
Decompress `src` into `dst` with the compressor in `c`.
Throw an error if the decompressed size is not `length(dst)`.
"""
function decompress!(c::CompressorOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8})::Nothing
    if c.type == COMPRESSOR_NONE
        decode!(NoopDecodeOptions(), dst, src)
    elseif c.type == COMPRESSOR_ZLIB
        decode!(ZlibDecodeOptions(), dst, src)
    elseif c.type == COMPRESSOR_GZIP
        decode!(GzipDecodeOptions(), dst, src)
    elseif c.type == COMPRESSOR_BLOSC_LZ4
        decode!(BloscDecodeOptions(), dst, src)
    else
        error("unreachable") # COV_EXCL_LINE
    end
    nothing
end
