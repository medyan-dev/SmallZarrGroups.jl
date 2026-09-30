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
@testset "array nested in an array" begin
    mktempdir() do dir
        write(joinpath(dir, ".zgroup"), """{"zarr_format": 2}""")
        zarray = """
            {
                "chunks": [2],
                "compressor": null,
                "dtype": "|i1",
                "fill_value": 0,
                "filters": null,
                "order": "C",
                "shape": [2],
                "zarr_format": 2
            }
            """
        mkpath(joinpath(dir, "a", "b"))
        write(joinpath(dir, "a", ".zarray"), zarray)
        write(joinpath(dir, "a", "b", ".zarray"), zarray)
        @test_throws ArgumentError SmallZarrGroups.load_dir(dir)
        # A group nested in an array is also invalid.
        rm(joinpath(dir, "a", "b", ".zarray"))
        write(joinpath(dir, "a", "b", ".zgroup"), """{"zarr_format": 2}""")
        @test_throws ArgumentError SmallZarrGroups.load_dir(dir)
    end
end
@testset "array and group with the same name" begin
    zarray = """
        {
            "chunks": [2],
            "compressor": null,
            "dtype": "|i1",
            "fill_value": 0,
            "filters": null,
            "order": "C",
            "shape": [2],
            "zarr_format": 2
        }
        """
    # "-" sorts before ".zarray", so the group "a" is made before the array "a" is loaded.
    mktempdir() do dir
        write(joinpath(dir, ".zgroup"), """{"zarr_format": 2}""")
        mkpath(joinpath(dir, "a", "-x"))
        write(joinpath(dir, "a", ".zarray"), zarray)
        write(joinpath(dir, "a", "-x", ".zarray"), zarray)
        @test_throws ArgumentError SmallZarrGroups.load_dir(dir)
    end
    # ".zarray" sorts before ".zgroup", so the array "a" is loaded before the group "a".
    mktempdir() do dir
        write(joinpath(dir, ".zgroup"), """{"zarr_format": 2}""")
        mkpath(joinpath(dir, "a"))
        write(joinpath(dir, "a", ".zarray"), zarray)
        write(joinpath(dir, "a", ".zgroup"), """{"zarr_format": 2}""")
        write(joinpath(dir, "a", ".zattrs"), """{"foo": 1}""")
        @test_throws ArgumentError SmallZarrGroups.load_dir(dir)
    end
end

# Make a zip file from `entries`, allowing duplicate and unusual names.
function make_raw_zip(entries)
    ZipArchives = SmallZarrGroups.ZipArchives
    io = IOBuffer()
    ZipArchives.ZipWriter(io; check_names=false) do w
        for (k, v) in entries
            ZipArchives.zip_writefile(w, k, v)
        end
    end
    take!(io)
end
@testset "duplicate and aliased keys" begin
    zgroup = codeunits("""{"zarr_format": 2}""")
    zarray = codeunits("""
        {
            "chunks": [2],
            "compressor": null,
            "dtype": "|i1",
            "fill_value": 0,
            "filters": null,
            "order": "C",
            "shape": [2],
            "zarr_format": 2
        }
        """)
    zattrs = codeunits("""{"x": 1}""")
    # Different spellings of the same key are normalized.
    g = SmallZarrGroups.load_zip(make_raw_zip([
        ".zgroup" => zgroup,
        "a/" => UInt8[], # directory entries are ignored
        "a//.zarray" => zarray,
        "/a/0" => [0x01, 0x02],
        "a\\.zattrs" => zattrs,
    ]))
    @test g["a"] == [1, 2]
    @test attrs(g["a"]) == Dict("x" => 1)
    # The predicate sees the normalized key.
    g = SmallZarrGroups.load_zip(
        make_raw_zip([".zgroup" => zgroup, "a//.zarray" => zarray, "/a/0" => [0x01, 0x02], "b/.zarray" => zarray]);
        predicate = startswith("a/"),
    )
    @test collect(keys(g)) == ["a"]
    @test g["a"] == [1, 2]
    # Exact duplicates error, even when the contents are the same.
    for key in (".zgroup", "a/.zarray", "a/0", "a/.zattrs")
        entries = [".zgroup" => zgroup, "a/.zarray" => zarray, "a/0" => [0x01, 0x02], "a/.zattrs" => zattrs]
        push!(entries, key => Dict(entries)[key])
        @test_throws "duplicate key \"$(key)\"" SmallZarrGroups.load_zip(make_raw_zip(entries))
    end
    # Different spellings of the same key error.
    @test_throws(
        "keys \"a/0\" and \"a//0\" are both the key \"a/0\"",
        SmallZarrGroups.load_zip(make_raw_zip([
            ".zgroup" => zgroup, "a/.zarray" => zarray, "a/0" => [0x01, 0x02], "a//0" => [0x03, 0x04],
        ])),
    )
    # Duplicates of keys removed by the predicate are ignored.
    g = SmallZarrGroups.load_zip(
        make_raw_zip([".zgroup" => zgroup, "a/.zarray" => zarray, "b/0" => [0x01], "b/0" => [0x02]]);
        predicate = !startswith("b/"),
    )
    @test g["a"] == [0, 0]
end
