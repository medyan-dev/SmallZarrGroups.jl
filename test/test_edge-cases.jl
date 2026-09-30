using SmallZarrGroups
using DataStructures: SortedDict, OrderedDict
using Test

@testset "saving and loading attrs on root" begin
    g = ZGroup()
    attrs(g)["foo"] = "bar"
    attrs(g)["2"] = 123
    attrs(g)["weird-number"] = 1.5
    attrs(g)["list"] = [1,2,3,4]
    @test repr("text/plain",g) == """
        📂 🏷️ foo => "bar", 🏷️ 2 => 123, 🏷️ weird-number => 1.5, 🏷️ list => [1, 2, 3, 4],\
        """
    mktempdir() do path
        SmallZarrGroups.save_dir(path,g)
        gload = SmallZarrGroups.load_dir(path)
        @test length(keys(attrs(gload))) == length(keys(attrs(g)))
        @test attrs(gload)["foo"] == "bar"
        # All numbers are loaded as `Float64`.
        @test attrs(gload)["2"] === 123.0
        @test attrs(gload)["weird-number"] === 1.5
        @test attrs(gload)["list"] == [1,2,3,4]
    end
end


@testset "saving and loading attrs on array" begin
    g = ZGroup()
    g["testarray"] = rand(10,20)
    data = g["testarray"]
    attrs(data)["foo"] = "bar"
    mktempdir() do path
        SmallZarrGroups.save_dir(path,g)
        gload = SmallZarrGroups.load_dir(path)
        aload = gload["testarray"]
        @test isempty(attrs(gload))
        @test aload == data
        @test attrs(aload) == OrderedDict([
            "foo" => "bar",
        ])
    end
end


@testset "saving and loading zero dimensional array" begin
    g = ZGroup()
    a::Array{Float64, 0} = fill(3.25)
    b::Array{Int8, 0} = fill(Int8(2))
    c::Array{UInt8, 0} = fill(UInt8(0xFF))
    g["a"] = a
    g["b"] = b
    g["c"] = c
    mktempdir() do path
        SmallZarrGroups.save_dir(path, g)
        gload = SmallZarrGroups.load_dir(path)
        @test gload["a"][] == 3.25
        @test gload["b"][] == 2
        @test gload["c"][] == 0xFF
    end
end

@testset "partial edge chunks are padded with zeros" begin
    # (2,5) makes the first chunk partial too
    for shape in ((4,5), (2,5))
        g = ZGroup()
        data = reshape(Float64.(1:prod(shape)), shape)
        g["a"] = SmallZarrGroups.ZArray(data; chunks=(3,2), compressor=SmallZarrGroups.COMPRESSOR_NONE, byteshuffle=false)
        mktempdir() do path
            SmallZarrGroups.save_dir(path, g)
            for i in 0:cld(shape[1],3)-1, j in 0:cld(shape[2],2)-1
                # chunk keys are reversed to match Zarr.jl
                chunk = reshape(reinterpret(Float64, read(joinpath(path, "a", "$(j).$(i)"))), 3, 2)
                rows = 3i+1:min(3i+3, shape[1])
                cols = 2j+1:min(2j+2, shape[2])
                @test chunk[1:length(rows), 1:length(cols)] == data[rows, cols]
                padded = trues(3, 2)
                padded[1:length(rows), 1:length(cols)] .= false
                @test all(iszero, chunk[padded])
            end
            @test SmallZarrGroups.load_dir(path)["a"] == data
        end
    end
end

@testset "saving a child with a zarr metadata key name errors" begin
    # Children added directly to `children` skip the path checks in `setindex!`.
    for name in (".zgroup", ".zarray", ".zattrs", "zarr.json")
        g = ZGroup()
        children(g)[name] = ZGroup()
        @test_throws ArgumentError SmallZarrGroups.save_zip(IOBuffer(), g)
    end
end
