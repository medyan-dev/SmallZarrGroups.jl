using StorageTrees
using DataStructures: SortedDict, OrderedDict
using StaticArrays
using Test
using StructArrays


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