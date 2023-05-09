using SmallZarrGroups
using DataStructures: SortedDict, OrderedDict
using StaticArrays
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