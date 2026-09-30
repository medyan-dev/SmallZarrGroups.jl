# Compressor options, and compressing chunk bytes.

using ChunkCodecCore: ChunkCodecCore, encode, decode!, NoopEncodeOptions, NoopDecodeOptions
using ChunkCodecLibZstd: ZstdEncodeOptions, ZstdDecodeOptions

# Compressor ids.
const COMPRESSOR_NONE = Int32(0)
const COMPRESSOR_ZSTD = Int32(1)

"""
    level_range(type::Integer)::UnitRange{Int32}

Return the valid compression levels for compressor `type`.
"""
function level_range(type::Integer)::UnitRange{Int32}
    if type == COMPRESSOR_NONE
        Int32(0):Int32(0)
    elseif type == COMPRESSOR_ZSTD
        # `ZSTD_minCLevel()` to `ZSTD_maxCLevel()`, 0 is zstd's default level.
        Int32(-131072):Int32(22)
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
    elseif type == COMPRESSOR_ZSTD
        Int32(1)
    else
        throw(ArgumentError("unknown compressor type $(type)"))
    end
end

"""
    CompressorOptions(type, level, itemsize, reverse_dims, byteshuffle)

How the chunks of an array are encoded and decoded.

- `type`: compressor id, either `COMPRESSOR_NONE` or `COMPRESSOR_ZSTD`.
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
    elseif c.type == COMPRESSOR_ZSTD
        encode(ZstdEncodeOptions(; compressionLevel=c.level), src)
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
    elseif c.type == COMPRESSOR_ZSTD
        decode!(ZstdDecodeOptions(), dst, src)
    else
        error("unreachable") # COV_EXCL_LINE
    end
    nothing
end
