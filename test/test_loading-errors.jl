using SmallZarrGroups
using DataStructures: SortedDict, OrderedDict
using Test

@testset "open missing file" begin
    @test_throws ArgumentError SmallZarrGroups.load_dir("asfdasdflewrq")
end

@testset "open file with unknown compressor" begin
    @test_throws "ja3sfdsdhgw compressor not supported yet" SmallZarrGroups.load_dir(joinpath(@__DIR__,"bad_files","missing_compressor"))
end
@testset "chunk buffer size overflow" begin
    # The chunk buffer would have 2^64 bytes, which wraps around to 0 if not checked.
    mktempdir() do dir
        mkpath(joinpath(dir, "data"))
        write(joinpath(dir, ".zgroup"), """{"zarr_format": 2}""")
        write(joinpath(dir, "data", ".zarray"), """
            {
                "chunks": [4, 4611686018427387904],
                "compressor": null,
                "dtype": "|i1",
                "fill_value": 0,
                "filters": null,
                "order": "C",
                "shape": [2, 3],
                "zarr_format": 2
            }
            """)
        write(joinpath(dir, "data", "0.0"), UInt8[])
        @test_throws OverflowError SmallZarrGroups.load_dir(dir)
    end
end
