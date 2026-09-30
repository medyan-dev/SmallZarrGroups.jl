using SmallZarrGroups
using DataStructures: SortedDict, OrderedDict
using Test

#These are tests for experimental features that are not stable API yet

@testset "chunking" begin
    # zero dim case
    for elsize in (0,8,1000)
        @test SmallZarrGroups.normalize_chunks(  -1, (), elsize) == ()
        @test SmallZarrGroups.normalize_chunks(  (), (), elsize) == ()
        @test SmallZarrGroups.normalize_chunks(   :, (), elsize) == ()
        @test SmallZarrGroups.normalize_chunks(   0, (), elsize) == ()
        @test SmallZarrGroups.normalize_chunks(1000, (), elsize) == ()
    end

    # one dim case default chunking
    @test SmallZarrGroups.normalize_chunks(  -1, (0,), 0) == (1,)
    @test SmallZarrGroups.normalize_chunks(  -1, (0,), 1) == (1,)
    @test SmallZarrGroups.normalize_chunks(  -1, (1,), 0) == (1,)
    @test SmallZarrGroups.normalize_chunks(  -1, (1,), 1) == (1,)
    @test SmallZarrGroups.normalize_chunks(  -1, (100,), 2^30) == (1,)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^50,), 8) == (2^20,)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^50,), 1) == (2^23,)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^30,), 8) == (2^20,)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^30,), 1) == (2^23,)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^23,), 1) == (2^23,)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^23+1,), 1) == (2^22+1,)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^23+2,), 1) == (2^22+1,)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^23+3,), 1) == (2^22+2,)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^23+4,), 1) == (2^22+2,)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^23+5,), 1) == (2^22+3,)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^20,), 8) == (2^20,)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^20+1,), 8) == (2^19+1,)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^18,), 1) == (2^18,)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^10,), 6) == (2^10,)

    # one dim case custom chunking
    @test SmallZarrGroups.normalize_chunks((123), (0,), 6) == (123,)
    @test SmallZarrGroups.normalize_chunks((123), (1,), 6) == (123,)
    @test SmallZarrGroups.normalize_chunks((123), (1000,), 6) == (123,)
    @test SmallZarrGroups.normalize_chunks(  123, (0,), 6) == (123,)
    @test SmallZarrGroups.normalize_chunks(  123, (1,), 6) == (123,)
    @test SmallZarrGroups.normalize_chunks(  123, (1000,), 6) == (123,)
    for x in (0, :)
        @test SmallZarrGroups.normalize_chunks((x,), (1223,), 6) == (1223,)
        @test SmallZarrGroups.normalize_chunks(   x, (1223,), 6) == (1223,)
        @test SmallZarrGroups.normalize_chunks(   x, (0,), 6) == (1,)
    end

    # two dim case default chunking
    @test SmallZarrGroups.normalize_chunks(  -1, (0,0), 0) == (1,1)
    @test SmallZarrGroups.normalize_chunks(  -1, (0,1), 0) == (1,1)
    @test SmallZarrGroups.normalize_chunks(  -1, (1,0), 0) == (1,1)
    @test SmallZarrGroups.normalize_chunks(  -1, (1,1), 0) == (1,1)
    @test SmallZarrGroups.normalize_chunks(  -1, (0,0), 6) == (1,1)
    @test SmallZarrGroups.normalize_chunks(  -1, (0,1), 6) == (1,1)
    @test SmallZarrGroups.normalize_chunks(  -1, (1,0), 6) == (1,1)
    @test SmallZarrGroups.normalize_chunks(  -1, (1,1), 6) == (1,1)
    @test SmallZarrGroups.normalize_chunks(  -1, (1,1), 2^30) == (1,1)
    @test SmallZarrGroups.normalize_chunks(  -1, (6,5), 2^30) == (1,1)
    @test SmallZarrGroups.normalize_chunks(  -1, (6,5), 6) == (6,5)
    @test SmallZarrGroups.normalize_chunks(  -1, (1,6), 1) == (1,6)
    for op in (reverse, identity)
        @test SmallZarrGroups.normalize_chunks(  -1, op((2^50,   1)), 8) == op((2^20,   1))
        @test SmallZarrGroups.normalize_chunks(  -1, op((2^50,   1)), 1) == op((2^23,   1))
        @test SmallZarrGroups.normalize_chunks(  -1, op((2^30,   1)), 8) == op((2^20,   1))
        @test SmallZarrGroups.normalize_chunks(  -1, op((2^30,   1)), 1) == op((2^23,   1))
        @test SmallZarrGroups.normalize_chunks(  -1, op((2^23,   1)), 1) == op((2^23,   1))
        @test SmallZarrGroups.normalize_chunks(  -1, op((2^23+1, 1)), 1) == op((2^22+1, 1))
        @test SmallZarrGroups.normalize_chunks(  -1, op((2^23+2, 1)), 1) == op((2^22+1, 1))
        @test SmallZarrGroups.normalize_chunks(  -1, op((2^23+3, 1)), 1) == op((2^22+2, 1))
        @test SmallZarrGroups.normalize_chunks(  -1, op((2^23+4, 1)), 1) == op((2^22+2, 1))
        @test SmallZarrGroups.normalize_chunks(  -1, op((2^23+5, 1)), 1) == op((2^22+3, 1))
        @test SmallZarrGroups.normalize_chunks(  -1, op((2^20,   1)), 8) == op((2^20,   1))
        @test SmallZarrGroups.normalize_chunks(  -1, op((2^18,   1)), 1) == op((2^18,   1))
        @test SmallZarrGroups.normalize_chunks(  -1, op((2^10,   1)), 6) == op((2^10,   1))
        # small dimensions are not split
        @test SmallZarrGroups.normalize_chunks(  -1, op((2^24,   2)), 1) == op((2^22,   2))
        @test SmallZarrGroups.normalize_chunks(  -1, op((10^7,   3)), 8) == op((312500, 3))
    end
    # the largest chunk dimension is halved, with ties going to the last dimension
    @test SmallZarrGroups.normalize_chunks(  -1, (2^12,   2^12), 1) == (2^12,   2^11)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^12+1, 2^12), 1) == (2^11+1, 2^11)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^12+2, 2^12+1), 1) == (2^11+1, 2^11+1)
    @test SmallZarrGroups.normalize_chunks(  -1, (2^12+3, 2^12), 1) == (2^11+2, 2^11)
    @test SmallZarrGroups.normalize_chunks(  -1, (512, 512, 512), 4) == (128, 128, 128)
    @test SmallZarrGroups.normalize_chunks(  -1, (100, 100, 100, 100), 8) == (50, 25, 25, 25)
    @test SmallZarrGroups.normalize_chunks(  -1, (3, 4000, 4000), 1) == (3, 2000, 1000)
    # chunks are between 4 and 8 MiB for arrays over 8 MiB
    for (s, e) in [((10^7,), 8), ((1025, 1025), 8), ((3, 5, 10^6), 2), ((100, 100, 100, 100), 8), ((1, 10^7), 4)]
        c = SmallZarrGroups.normalize_chunks(-1, s, e)
        @test 4*2^20 < prod(c)*e ≤ 8*2^20
    end

    # two dim case custom chunking
    @test SmallZarrGroups.normalize_chunks((123,456), (0,4), 6) == (123,456)
    @test SmallZarrGroups.normalize_chunks((123,456), (1,2), 6) == (123,456)
    @test SmallZarrGroups.normalize_chunks((123,456), (1000,4), 6) == (123,456)
    @test SmallZarrGroups.normalize_chunks(  123, (0,1), 6) == (123,123)
    @test SmallZarrGroups.normalize_chunks(  123, (1,1), 6) == (123,123)
    @test SmallZarrGroups.normalize_chunks(  123, (1000,1000), 6) == (123,123)
    for x in (0, :)
        @test SmallZarrGroups.normalize_chunks((x,423), (1223,532), 6) == (1223,423)
        @test SmallZarrGroups.normalize_chunks((x,x), (1223,532), 6) == (1223,532)
        @test SmallZarrGroups.normalize_chunks(   x, (1223,532), 6) == (1223,532)
        @test SmallZarrGroups.normalize_chunks(   x, (0,532), 6) == (1,532)
    end
end




