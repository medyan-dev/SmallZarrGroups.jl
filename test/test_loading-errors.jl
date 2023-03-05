using StorageTrees
using DataStructures: SortedDict, OrderedDict
using Test

@testset "open missing file" begin
    @test_throws ArgumentError StorageTrees.load_dir("asfdasdflewrq")
end