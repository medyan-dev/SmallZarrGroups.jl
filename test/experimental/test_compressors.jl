using SmallZarrGroups
using JSON3
using Test
using Pkg.Artifacts

@testset "compressor edge cases" begin

    # GZip will save as uncompressed.
    @testset "saving gzip" begin
        g = ZGroup()
        data = rand(10,20)
        g["testarray"] = SmallZarrGroups.ZArray(data; compressor = JSON3.read("""{
                "level": 5,
                "id": "gzip"
            }"""))
        mktempdir() do path
            @test_logs (:warn, "compressor gzip not implemented yet, saving data uncompressed") SmallZarrGroups.save_dir(path,g)
            gload = SmallZarrGroups.load_dir(path)
            @test gload["testarray"] == data
        end
    end

    # Zarr has a special autoshuffle for blosc. 
    # I don't know of any code that actually uses this, but its part of the numcodecs spec.
    @testset "blosc autoshuffle" begin
        g = ZGroup()
        data = rand(10,20)
        data_bytes = rand(UInt8,10)
        g["testarray"] = SmallZarrGroups.ZArray(data; compressor = JSON3.read("""{
            "id": "blosc",
            "shuffle": -1
        }"""))
        g["testarray_bytes"] = SmallZarrGroups.ZArray(data_bytes; compressor = JSON3.read("""{
            "id": "blosc",
            "shuffle": -1
        }"""))
        mktempdir() do path
            SmallZarrGroups.save_dir(path,g)
            gload = SmallZarrGroups.load_dir(path)
            @test gload["testarray"] == data
            @test gload["testarray_bytes"] == data_bytes
        end
    end

    # If compressor has out of range parameters
    # or is unknown, save the data uncompressed and create a warning.
    # The data will still be saved.
    @testset "bad blosc compressor parameters" begin
        g = ZGroup()
        data = rand(10,20)
        g["testarray"] = SmallZarrGroups.ZArray(data; compressor = JSON3.read("""{
                "clevel": 1000,
                "id": "blosc"
            }"""))
        mktempdir() do path
            @test_logs (:warn, "blosc clevel not in 0:9, saving data uncompressed") SmallZarrGroups.save_dir(path,g)
            gload = SmallZarrGroups.load_dir(path)
            @test gload["testarray"] == data
        end
    end
    @testset "bad zlib compressor parameters" begin
        g = ZGroup()
        data = rand(10,20)
        g["testarray"] = SmallZarrGroups.ZArray(data; compressor = JSON3.read("""{
                "level": 1000,
                "id": "zlib"
            }"""))
        mktempdir() do path
            @test_logs (:warn, "zlib level not in -1:9, saving data uncompressed") SmallZarrGroups.save_dir(path,g)
            gload = SmallZarrGroups.load_dir(path)
            @test gload["testarray"] == data
        end
    end
    @testset "bz2 compressor not implemented" begin
        g = ZGroup()
        data = rand(10,20)
        g["testarray"] = SmallZarrGroups.ZArray(data; compressor = JSON3.read("""{
                "level": 2,
                "id": "bz2"
            }"""))
        mktempdir() do path
            @test_logs (:warn, "compressor bz2 not implemented yet, saving data uncompressed") SmallZarrGroups.save_dir(path,g)
            gload = SmallZarrGroups.load_dir(path)
            @test gload["testarray"] == data
        end
    end
    @testset "missing compressor id" begin
        g = ZGroup()
        data = rand(10,20)
        g["testarray"] = SmallZarrGroups.ZArray(data; compressor = JSON3.read("""{
                "level": 1000
            }"""))
        mktempdir() do path
            @test_logs (:warn, "compressor id missing, saving data uncompressed") SmallZarrGroups.save_dir(path,g)
            gload = SmallZarrGroups.load_dir(path)
            @test gload["testarray"] == data
        end
    end
end

