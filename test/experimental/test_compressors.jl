using StorageTrees
using JSON3
using Test
using Pkg.Artifacts

@testset "loading gzip" begin

    @testset "loading gzip" begin
        gload = StorageTrees.load_dir(joinpath("fixture", "test_gzip.zarr"))
        @test gload["test_gzip"] == 0:9
    end

    @testset "saving gzip" begin
        g = ZGroup()
        data = rand(10,20)
        g["testarray"] = StorageTrees.ZArray(data; compressor = JSON3.read("""{
                "level": 5,
                "id": "gzip"
            }"""))
        data = g["testarray"]
        mktempdir() do path
            @test_logs (:warn, "compressor gzip not implemented yet, saving data uncompressed") StorageTrees.save_dir(path,g)
            gload = StorageTrees.load_dir(path)
            aload = gload["testarray"]
            @test aload == data
        end
    end

    @testset "saving gzip" begin
        g = ZGroup()
        data = rand(10,20)
        g["testarray"] = StorageTrees.ZArray(data; compressor = JSON3.read("""{
                "level": 5,
                "id": "gzip"
            }"""))
        data = g["testarray"]
        mktempdir() do path
            @test_logs (:warn, "compressor gzip not implemented yet, saving data uncompressed") StorageTrees.save_dir(path,g)
            gload = StorageTrees.load_dir(path)
            aload = gload["testarray"]
            @test aload == data
        end
    end
end

