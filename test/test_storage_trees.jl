using StorageTrees
using DataStructures: SortedDict, OrderedDict
using StaticArrays
using Test
using StructArrays

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

@testset "saving and loading attrs" begin
    attrs = StorageTrees.attrs
    g = StorageTrees.ZGroup()
    attrs(g)["foo"] = "bar"
    attrs(g)["2"] = 123
    attrs(g)["weird-number"] = NaN
    attrs(g)["list"] = [1,2,3,4]
    mktempdir() do path
        StorageTrees.save_dir(path,g)
        gload = StorageTrees.load_dir(path)
        @test length(keys(attrs(gload))) == length(keys(attrs(g)))
        @test attrs(gload)["foo"] =="bar"
        @test attrs(gload)["2"] == 123
        @test attrs(gload)["weird-number"] === NaN
        @test attrs(gload)["list"] == [1,2,3,4]
    end
end

@testset "saving and loading array" begin
    attrs = StorageTrees.attrs
    g = StorageTrees.ZGroup()
    data = rand(10,20)
    g["testarray"] = StorageTrees.ZArray(data;
        attrs = OrderedDict([
            "foo" => "bar",
        ])
    )
    mktempdir() do path
        StorageTrees.save_dir(path,g)
        gload = StorageTrees.load_dir(path)
        aload = gload["testarray"]
        @test isempty(attrs(gload))
        @test StorageTrees.getarray(aload) == data
        @test attrs(aload) == OrderedDict([
            "foo" => "bar",
        ])
    end
end

@testset "saving and loading many arrays" begin
    attrs = StorageTrees.attrs
    g = StorageTrees.ZGroup()
    data1 = rand(10,20)
    g["testarray1"] = StorageTrees.ZArray(data1;
        attrs = OrderedDict([
            "foo" => "bar1",
        ])
    )
    data2 = rand(Int,20)
    g["testarray2"] = StorageTrees.ZArray(data2;
        attrs = OrderedDict([
            "foo" => "bar2",
        ])
    )
    data3 = rand(UInt8,20)
    g["testgroup1"] = StorageTrees.ZGroup()
    g["testgroup1"]["testarray1"] = StorageTrees.ZArray(data3;
        attrs = OrderedDict([
            "foo" => "bar3",
        ])
    )
    mktempdir() do path
        StorageTrees.save_dir(path,g)
        gload = StorageTrees.load_dir(path)
        @test StorageTrees.getarray(gload["testarray1"]) == data1
        @test attrs(gload["testarray1"]) == OrderedDict([
            "foo" => "bar1",
        ])
        @test StorageTrees.getarray(gload["testarray2"]) == data2
        @test attrs(gload["testarray2"]) == OrderedDict([
            "foo" => "bar2",
        ])
        @test StorageTrees.getarray(gload["testgroup1/testarray1"]) == data3
        @test attrs(gload["testgroup1/testarray1"]) == OrderedDict([
            "foo" => "bar3",
        ])
    end
end


@testset "loading/saving nested StructArray" begin
    @testset "StructArray with nested empty tuple and nothing" begin
        d = (a=5,b=6.0,d=nothing,e=(),)
        aos = fill(d,10)
        soa = StructArray(aos)
        g1 = StorageTrees.write_nested_struct_array(soa)
        @test !haskey(g1,"d") # zero size data should be ignored
        @test !haskey(g1,"e") # zero size data should be ignored
        d0 = (a=0,b=0.0,d=nothing,e=(),)
        aos0 = fill(d0,10)
        soa0 = StructArray(aos0)
        StorageTrees.read_nested_struct_array!(soa0, g1)
        @test soa0 == soa
    end
    @testset "StructArray with nested SMatrix" begin
        d = (a=5,b=6.0,d=SA[1 2 3; 4 5 6],)
        aos = fill(d,10)
        soa = StructArray(aos, unwrap = t-> t<:AbstractArray)
        g1 = StorageTrees.write_nested_struct_array(soa)
        d0 = (a=0,b=0.0,d=SA[0 0 0; 0 0 0],)
        aos0 = fill(d0,10)
        soa0 = StructArray(aos0, unwrap = t-> t<:AbstractArray)
        StorageTrees.read_nested_struct_array!(soa0, g1)
        @test soa0 == soa
    end
    @testset "StructArray with double nested SMatrix" begin
        double_nested_Smatrix = SA[SA[1 2 3; 4 5 6],SA[13 2 3; 4 5 6],SA[1 24 3; 4 55 6]]
        d = (a=5,b=6.0,d=double_nested_Smatrix,)
        aos = fill(d,10)
        soa = StructArray(aos, unwrap = t-> t<:AbstractArray)
        g1 = StorageTrees.write_nested_struct_array(soa)
        d0 = (a=0,b=0.0,d=zero(double_nested_Smatrix),)
        aos0 = fill(d0,10)
        soa0 = StructArray(aos0, unwrap = t-> t<:AbstractArray)
        StorageTrees.read_nested_struct_array!(soa0, g1)
        @test soa0 == soa
    end
    @testset "StructArray with double nested SMatrix emoji" begin
        double_nested_Smatrix = SA[SA[1 2 3; 4 5 6],SA[13 2 3; 4 5 6],SA[1 24 3; 4 55 6]]
        d = (🐢=5,🎈=6.0,🌐=double_nested_Smatrix,)
        aos = fill(d,10)
        soa = StructArray(aos, unwrap = t-> t<:AbstractArray)
        g1 = StorageTrees.write_nested_struct_array(soa)
        d0 = (🐢=0,🎈=0.0,🌐=zero(double_nested_Smatrix),)
        aos0 = fill(d0,10)
        soa0 = StructArray(aos0, unwrap = t-> t<:AbstractArray)
        StorageTrees.read_nested_struct_array!(soa0, g1)
        @test soa0 == soa
    end
end