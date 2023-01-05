using StorageTrees
using DataStructures: SortedDict, OrderedDict
using Test

@testset "create empty ZGroup" begin
    zg = ZGroup()
    @test repr("text/plain",zg) == """
    📂 
    """
end

@testset "copy data to a group" begin
    zg = ZGroup()

    # Save and copy an abstract array with setindex!
    zg["random_data"] = rand(30,10)
    @test repr("text/plain",zg) == """
        📂 
        └─ "random_data" ⇒ 🔢 30×10 Float64 
        """

    # Save and copy data to a sub group using "/" as a path separator.
    # All intermediate groups will be automatically created.
    zg["group1/subgroup2/random_data"] = rand(30)
    @test repr("text/plain",zg) == """
        📂 
        ├─ "group1" ⇒ 📂 
        │             └─ "subgroup2" ⇒ 📂 
        │                              └─ "random_data" ⇒ 🔢 30 Float64 
        └─ "random_data" ⇒ 🔢 30×10 Float64 
        """

    # \ and / are both treated as path separators.
    # empty keys and keys of ".." or "." are not allowed.
    @test_throws ArgumentError zg[""] = [1,2]
    @test_throws ArgumentError zg[".."] = [1,2]
    @test_throws ArgumentError zg["."] = [1,2]
    @test_throws ArgumentError zg["/"] = [1,2]
    @test_throws ArgumentError zg["\\"] = [1,2]
    @test_throws ArgumentError zg["\\.."] = [1,2]

    # Element types must be Union{
    #     Bool,
    #     Int8,
    #     Int16,
    #     Int32,
    #     Int64,
    #     UInt8,
    #     UInt16,
    #     UInt32,
    #     UInt64,
    #     Float16,
    #     Float32,
    #     Float64,
    #     ComplexF32,
    #     ComplexF64,
    # }
    @test_throws ArgumentError zg["a"] = fill(BigInt(10),3)
    @test repr("text/plain",zg) == """
        📂 
        ├─ "group1" ⇒ 📂 
        │             └─ "subgroup2" ⇒ 📂 
        │                              └─ "random_data" ⇒ 🔢 30 Float64 
        └─ "random_data" ⇒ 🔢 30×10 Float64 
        """

    # Sub groups can also be added with setindex!
    # Note: Unlike setindex with an AbstractArray, 
    # this won't make a copy of the group, a reference will be added.
    othergroup = ZGroup()
    othergroup["bar"] = [1,2,4]
    zg["innergroup2"] = othergroup
    @test repr("text/plain",zg) == """
        📂 
        ├─ "group1" ⇒ 📂 
        │             └─ "subgroup2" ⇒ 📂 
        │                              └─ "random_data" ⇒ 🔢 30 Float64 
        ├─ "innergroup2" ⇒ 📂 
        │                  └─ "bar" ⇒ 🔢 3 Int64 
        └─ "random_data" ⇒ 🔢 30×10 Float64 
        """
    @test repr("text/plain",othergroup) == """
        📂 
        └─ "bar" ⇒ 🔢 3 Int64 
        """
    
    # Mutating one group will also effect the other now.
    othergroup["foo"] = [1.5,3.4]
    @test repr("text/plain",zg) == """
        📂 
        ├─ "group1" ⇒ 📂 
        │             └─ "subgroup2" ⇒ 📂 
        │                              └─ "random_data" ⇒ 🔢 30 Float64 
        ├─ "innergroup2" ⇒ 📂 
        │                  ├─ "bar" ⇒ 🔢 3 Int64 
        │                  └─ "foo" ⇒ 🔢 2 Float64 
        └─ "random_data" ⇒ 🔢 30×10 Float64 
        """
    @test repr("text/plain",othergroup) == """
        📂 
        ├─ "bar" ⇒ 🔢 3 Int64 
        └─ "foo" ⇒ 🔢 2 Float64 
        """
    
    # haskey can be used to check if a path exists.
    @test haskey(zg,"group1")
    @test haskey(zg,"random_data")
    @test !haskey(zg,"foo")
    @test haskey(zg,"innergroup2/foo")
    @test haskey(zg,"innergroup2/foo/")
    @test !haskey(zg,"innergroup2/foo/a")
    @test !haskey(zg,"innergroup2/foo2")
    @test haskey(zg,"group1/subgroup2")
    @test haskey(zg,"/group1//subgroup2/")
    @test haskey(zg,"group1\\subgroup2")

    # children can be used to get a SortedDict of direct children
    @test children(zg) isa SortedDict{String, Union{ZGroup,StorageTrees.ZArray}}
    @test children(zg) == SortedDict([
        "group1" => zg["group1"],
        "innergroup2" => zg["innergroup2"],
        "random_data" => zg["random_data"],
    ])

    # attr can be used to get an OrderedDict of attributes
    @test attrs(zg) isa OrderedDict{String, Any}
    @test isempty(attrs(zg))
    @test attrs(zg["random_data"]) isa OrderedDict{String, Any}
    @test isempty(attrs(zg["random_data"]))

    
    # keys can be deleted from a group
    delete!(zg,"innergroup2/bar")
    delete!(zg,"innergroup2")
    delete!(zg,"group1/subgroup2")
    @test repr("text/plain",zg) == """
        📂 
        ├─ "group1" ⇒ 📂 
        └─ "random_data" ⇒ 🔢 30×10 Float64 
        """
end

@testset "read data from a group with collect" begin
    zg = ZGroup()
    zg["data"] = Int32[1,2,4]
    @test collect(zg["data"]) isa Vector{Int32}
    @test collect(zg["data"]) == [1,2,4]
    @test collect(Int64, zg["data"]) isa Vector{Int64}
    @test collect(Int64, zg["data"]) == [1,2,4]
end


@testset "saving and loading a directory" begin
    g = ZGroup()
    data1 = rand(10,20)
    g["testarray1"] = data1
    attrs(g["testarray1"])["foo"] = "bar1"
    data2 = rand(Int,20)
    g["testarray2"] = data2
    data3 = rand(UInt8,20)
    g["testgroup1"] = ZGroup()
    g["testgroup1"]["testarray1"] = data3
    attrs(g["testgroup1/testarray1"])["foo"] = "bar3"
    mktempdir() do path
        # Note this will delete pre existing data at dirpath
        # if path ends in ".zip" the data will be saved in a zip file instead.
        StorageTrees.save_dir(path,g)
        gload = StorageTrees.load_dir(path)
        @test collect(gload["testarray1"]) == data1
        @test attrs(gload["testarray1"]) == OrderedDict([
            "foo" => "bar1",
        ])
        @test collect(gload["testarray2"]) == data2
        @test attrs(gload["testarray2"]) == OrderedDict([])
        @test attrs(gload) == OrderedDict([])
        @test collect(gload["testgroup1/testarray1"]) == data3
        @test attrs(gload["testgroup1/testarray1"]) == OrderedDict([
            "foo" => "bar3",
        ])
    end
end

@testset "saving and loading a zip file" begin
    g = ZGroup()
    data1 = rand(10,20)
    g["testarray1"] = data1
    attrs(g["testarray1"])["foo"] = "bar1"
    data2 = rand(Int,20)
    g["testarray2"] = data2
    data3 = rand(UInt8,20)
    g["testgroup1"] = ZGroup()
    g["testgroup1"]["testarray1"] = data3
    attrs(g["testgroup1/testarray1"])["foo"] = "bar3"
    mktempdir() do path
        # Note this will delete pre existing data at "path/test.zip".
        # If path ends in ".zip" the data will be saved in a zip file.
        # This zip file can be read by zarr-python.
        StorageTrees.save_dir(joinpath(path,"test.zip"),g)
        @test isfile(joinpath(path,"test.zip"))
        # load_dir can load zip files saved by save_dir, or saved by zarr-python.
        # It can also load zip files created by zipping a zarr directory.
        # Note the zip file must be in the format described in the zarr-python docs:
        # "
        #  Take note that the files in the Zip file must be relative to the root of the Zarr archive. 
        #  You may find it easier to create such a Zip file with 7z, e.g.:
        #       `7z a -tzip archive.zarr.zip archive.zarr/.`
        # "
        gload = StorageTrees.load_dir(joinpath(path,"test.zip"))
        @test collect(gload["testarray1"]) == data1
        @test attrs(gload["testarray1"]) == OrderedDict([
            "foo" => "bar1",
        ])
        @test collect(gload["testarray2"]) == data2
        @test attrs(gload["testarray2"]) == OrderedDict([])
        @test attrs(gload) == OrderedDict([])
        @test collect(gload["testgroup1/testarray1"]) == data3
        @test attrs(gload["testgroup1/testarray1"]) == OrderedDict([
            "foo" => "bar3",
        ])
    end
end