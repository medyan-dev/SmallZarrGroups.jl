using StorageTrees
using DataStructures: SortedDict, OrderedDict
using StaticArrays
using Test

@testset "saving and loading attrs on root" begin
    g = ZGroup()
    attrs(g)["foo"] = "bar"
    attrs(g)["2"] = 123
    attrs(g)["weird-number"] = 1.5
    attrs(g)["list"] = [1,2,3,4]
    mktempdir() do path
        StorageTrees.save_dir(path,g)
        gload = StorageTrees.load_dir(path)
        @test length(keys(attrs(gload))) == length(keys(attrs(g)))
        @test attrs(gload)["foo"] == "bar"
        @test attrs(gload)["2"] == 123
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
        StorageTrees.save_dir(path,g)
        gload = StorageTrees.load_dir(path)
        aload = gload["testarray"]
        @test isempty(attrs(gload))
        @test aload == data
        @test attrs(aload) == OrderedDict([
            "foo" => "bar",
        ])
    end
end