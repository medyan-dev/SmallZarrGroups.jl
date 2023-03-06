using StorageTrees
using DataStructures: SortedDict, OrderedDict
using Test

@testset "open missing file" begin
    @test_throws ArgumentError StorageTrees.load_dir("asfdasdflewrq")
end

@testset "open file with unknown compressor" begin
    @test_throws "ja3sfdsdhgw compressor not supported yet" StorageTrees.load_dir(joinpath(@__DIR__,"bad_files","missing_compressor"))
end