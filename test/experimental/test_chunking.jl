using StorageTrees
using DataStructures: SortedDict, OrderedDict
using StaticArrays
using Test

#These are tests for experimental features that are not stable API yet

@testset "chunking" begin
    # zero dim case
    for elsize in (0,8,1000)
        @test StorageTrees.normalize_chunks(  -1, (), elsize) == ()
        @test StorageTrees.normalize_chunks(  (), (), elsize) == ()
        @test StorageTrees.normalize_chunks(   :, (), elsize) == ()
        @test StorageTrees.normalize_chunks(   0, (), elsize) == ()
        @test StorageTrees.normalize_chunks(1000, (), elsize) == ()
    end

    # one dim case default chunking
    @test StorageTrees.normalize_chunks(  -1, (0,), 0) == (0,)
    @test StorageTrees.normalize_chunks(  -1, (0,), 1) == (0,)
    @test StorageTrees.normalize_chunks(  -1, (1,), 0) == (1,)
    @test StorageTrees.normalize_chunks(  -1, (1,), 1) == (1,)
    @test StorageTrees.normalize_chunks(  -1, (100,), 2^30) == (1,)
    @test StorageTrees.normalize_chunks(  -1, (2^50,), 8) == (2^23,)
    @test StorageTrees.normalize_chunks(  -1, (2^50,), 1) == (2^26,)
    @test StorageTrees.normalize_chunks(  -1, (2^30,), 8) == (2^19,)
    @test StorageTrees.normalize_chunks(  -1, (2^30,), 1) == (2^21,)
    @test StorageTrees.normalize_chunks(  -1, (2^20,), 1) == (2^18,)
    @test StorageTrees.normalize_chunks(  -1, (2^20+1,), 1) == (2^18+1,)
    @test StorageTrees.normalize_chunks(  -1, (2^20+2,), 1) == (2^18+1,)
    @test StorageTrees.normalize_chunks(  -1, (2^20+3,), 1) == (2^18+1,)
    @test StorageTrees.normalize_chunks(  -1, (2^20+4,), 1) == (2^18+1,)
    @test StorageTrees.normalize_chunks(  -1, (2^20+5,), 1) == (2^18+2,)
    @test StorageTrees.normalize_chunks(  -1, (2^20,), 8) == (2^16,)
    @test StorageTrees.normalize_chunks(  -1, (2^18,), 1) == (2^17,)
    @test StorageTrees.normalize_chunks(  -1, (2^10,), 6) == (2^10,)

    # one dim case custom chunking
    @test StorageTrees.normalize_chunks((123), (0,), 6) == (123,)
    @test StorageTrees.normalize_chunks((123), (1,), 6) == (123,)
    @test StorageTrees.normalize_chunks((123), (1000,), 6) == (123,)
    @test StorageTrees.normalize_chunks(  123, (0,), 6) == (123,)
    @test StorageTrees.normalize_chunks(  123, (1,), 6) == (123,)
    @test StorageTrees.normalize_chunks(  123, (1000,), 6) == (123,)
    for x in (0, :)
        @test StorageTrees.normalize_chunks((x,), (1223,), 6) == (1223,)
        @test StorageTrees.normalize_chunks(   x, (1223,), 6) == (1223,)
        @test StorageTrees.normalize_chunks(   x, (0,), 6) == (0,)
    end

    # two dim case default chunking
    @test StorageTrees.normalize_chunks(  -1, (0,0), 0) == (0,0)
    @test StorageTrees.normalize_chunks(  -1, (0,1), 0) == (0,1)
    @test StorageTrees.normalize_chunks(  -1, (1,0), 0) == (1,0)
    @test StorageTrees.normalize_chunks(  -1, (1,1), 0) == (1,1)
    @test StorageTrees.normalize_chunks(  -1, (0,0), 6) == (0,0)
    @test StorageTrees.normalize_chunks(  -1, (0,1), 6) == (0,1)
    @test StorageTrees.normalize_chunks(  -1, (1,0), 6) == (1,0)
    @test StorageTrees.normalize_chunks(  -1, (1,1), 6) == (1,1)
    @test StorageTrees.normalize_chunks(  -1, (1,1), 2^30) == (1,1)
    @test StorageTrees.normalize_chunks(  -1, (6,5), 2^30) == (1,1)
    @test StorageTrees.normalize_chunks(  -1, (6,5), 6) == (6,5)
    @test StorageTrees.normalize_chunks(  -1, (1,6), 1) == (1,6)
    for op in (reverse, identity)
        @test StorageTrees.normalize_chunks(  -1, op((2^50,   1)), 8) == op((2^23,   1))
        @test StorageTrees.normalize_chunks(  -1, op((2^50,   1)), 1) == op((2^26,   1))
        @test StorageTrees.normalize_chunks(  -1, op((2^30,   1)), 8) == op((2^19,   1))
        @test StorageTrees.normalize_chunks(  -1, op((2^30,   1)), 1) == op((2^21,   1))
        @test StorageTrees.normalize_chunks(  -1, op((2^20,   1)), 1) == op((2^18,   1))
        @test StorageTrees.normalize_chunks(  -1, op((2^20+1, 1)), 1) == op((2^18+1, 1))
        @test StorageTrees.normalize_chunks(  -1, op((2^20+2, 1)), 1) == op((2^18+1, 1))
        @test StorageTrees.normalize_chunks(  -1, op((2^20+3, 1)), 1) == op((2^18+1, 1))
        @test StorageTrees.normalize_chunks(  -1, op((2^20+4, 1)), 1) == op((2^18+1, 1))
        @test StorageTrees.normalize_chunks(  -1, op((2^20+5, 1)), 1) == op((2^18+2, 1))
        @test StorageTrees.normalize_chunks(  -1, op((2^20,   1)), 8) == op((2^16,   1))
        @test StorageTrees.normalize_chunks(  -1, op((2^18,   1)), 1) == op((2^17,   1))
        @test StorageTrees.normalize_chunks(  -1, op((2^10,   1)), 6) == op((2^10,   1))
    end
    @test StorageTrees.normalize_chunks(  -1, (2^10,   2^10), 1) == (2^9,   2^9)
    @test StorageTrees.normalize_chunks(  -1, (2^10+1, 2^10), 1) == (2^9+1, 2^9)
    @test StorageTrees.normalize_chunks(  -1, (2^10+2, 2^10+1), 1) == (2^9+1, 2^9+1)
    @test StorageTrees.normalize_chunks(  -1, (2^10+3, 2^10), 1) == (2^9+2, 2^9)
    # slightly prefer to split higher dims
    @test StorageTrees.normalize_chunks(  -1, (2^18,   2), 1) == (2^18,   1)
    @test StorageTrees.normalize_chunks(  -1, (2,   2^18), 1) == (2,   2^17)

    # two dim case custom chunking
    @test StorageTrees.normalize_chunks((123,456), (0,4), 6) == (123,456)
    @test StorageTrees.normalize_chunks((123,456), (1,2), 6) == (123,456)
    @test StorageTrees.normalize_chunks((123,456), (1000,4), 6) == (123,456)
    @test StorageTrees.normalize_chunks(  123, (0,1), 6) == (123,123)
    @test StorageTrees.normalize_chunks(  123, (1,1), 6) == (123,123)
    @test StorageTrees.normalize_chunks(  123, (1000,1000), 6) == (123,123)
    for x in (0, :)
        @test StorageTrees.normalize_chunks((x,423), (1223,532), 6) == (1223,423)
        @test StorageTrees.normalize_chunks((x,x), (1223,532), 6) == (1223,532)
        @test StorageTrees.normalize_chunks(   x, (1223,532), 6) == (1223,532)
        @test StorageTrees.normalize_chunks(   x, (0,532), 6) == (0,532)
    end
end




