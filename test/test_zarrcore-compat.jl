using SmallZarrGroups
using Test
# import instead of using because ZarrCore also exports ZGroup and ZArray
import ZarrCore
import ZarrZip

# Types supported by both packages. ZarrCore doesn't support "V" types.
const ZARRCORE_TYPES = [
    Bool,
    Int8, Int16, Int32, Int64,
    UInt8, UInt16, UInt32, UInt64,
    Float16, Float32, Float64,
    ComplexF16, ComplexF32, ComplexF64,
]

function uncompressed_test_group()
    g = ZGroup()
    for T in ZARRCORE_TYPES
        tg = ZGroup()
        tg["zero_dim"] = SmallZarrGroups.ZArray(fill(one(T)); compressor=SmallZarrGroups.COMPRESSOR_NONE, byteshuffle=false)
        tg["one_dim"] = SmallZarrGroups.ZArray(rand(T, 7); chunks=(3,), compressor=SmallZarrGroups.COMPRESSOR_NONE, byteshuffle=false)
        tg["two_dim"] = SmallZarrGroups.ZArray(rand(T, 4, 5); chunks=(3, 2), compressor=SmallZarrGroups.COMPRESSOR_NONE, byteshuffle=false)
        tg["three_dim"] = SmallZarrGroups.ZArray(rand(T, 2, 3, 5); chunks=(2, 2, 3), compressor=SmallZarrGroups.COMPRESSOR_NONE, byteshuffle=false)
        tg["one_chunk"] = SmallZarrGroups.ZArray(rand(T, 3, 4); chunks=:, compressor=SmallZarrGroups.COMPRESSOR_NONE, byteshuffle=false)
        g[string(T)] = tg
    end
    g
end

function compare_zarrcore(jl_group::ZGroup, zc_group)
    # TODO test keys match when ZarrCore has that API
    for (k, v) in pairs(jl_group)
        if v isa ZGroup
            compare_zarrcore(v, zc_group[k])
        else
            zc_array = zc_group[k]
            @test eltype(zc_array) == eltype(v)
            @test size(zc_array) == size(v)
            @test isequal(collect(zc_array), collect(v))
        end
    end
end

@testset "ZarrCore can read uncompressed v2 arrays" begin
    g = uncompressed_test_group()
    compare_zarrcore(g, ZarrCore.zopen(ZarrZip.ZipStore(SmallZarrGroups.save_zip(Vector{UInt8}, g))))
end
