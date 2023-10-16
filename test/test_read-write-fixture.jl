using SmallZarrGroups
using DataStructures: SortedDict, OrderedDict
using Test
using Pkg.Artifacts

using PythonCall

zarr = pyimport("zarr")


"""
Compare the results of reading a directory or zip file with zarr-python and SmallZarrGroups.

Then write the data with SmallZarrGroups and read and compare again.

The directory must be a group, not an array.
"""
function disk_load_compare(zarr, dirpath)
    # get path of python group
    python_group = zarr.open_group(
        store=dirpath,
        path="/", # Group path within store.
        mode="r", # Persistence mode: 
            # ‘r’ means read only (must exist); 
            # ‘r+’ means read/write (must exist); 
            # ‘a’ means read/write (create if doesn’t exist); 
            # ‘w’ means create (overwrite if exists); 
            # ‘w-’ means create (fail if exists).
    )
    zgroup = SmallZarrGroups.load_dir(dirpath)
    compare_jl_py_groups(zgroup, python_group)
    newdir = if isdir(dirpath)
        mktempdir()
    else
        joinpath(mktempdir(), "temp.zarr.zip")
    end
    SmallZarrGroups.save_dir(newdir, zgroup)
    python_group2 = zarr.open_group(
        store=newdir,
        path="/", # Group path within store.
        mode="r", # Persistence mode: 
    )
    zgroup2 = SmallZarrGroups.load_dir(newdir)
    compare_jl_py_groups(zgroup2, python_group2)
    compare_jl_py_groups(zgroup2, python_group)
    compare_jl_py_groups(zgroup, python_group2)
end


function compare_jl_py_groups(jl_group::ZGroup, py_group)
    # @show attrs(jl_group)
    @test pyconvert(Dict, PyDict(py_group.attrs.asdict())) == Dict(attrs(jl_group))
    py_subgroup_keys::Vector{String} = sort(string.(collect(py_group.group_keys())))
    jl_subgroup_keys = map(first ,filter(x->x[2] isa ZGroup, collect(pairs(jl_group))))
    @test py_subgroup_keys == jl_subgroup_keys
    for groupkey in py_subgroup_keys
        compare_jl_py_groups(jl_group[groupkey], py_group[groupkey])
    end
    #test arrays are equal
    py_array_keys::Vector{String} = sort(string.(collect(py_group.array_keys())))
    jl_array_keys = map(first ,filter(x->x[2] isa SmallZarrGroups.ZArray, collect(pairs(jl_group))))
    @test py_array_keys == jl_array_keys
    for arraykey in py_array_keys
        compare_jl_py_zarray(jl_group[arraykey], py_group[arraykey])
    end
end

function compare_jl_py_zarray(jl_zarray::SmallZarrGroups.ZArray, py_zarray)
    @test pyconvert(Dict, PyDict(py_zarray.attrs.asdict())) == Dict(attrs(jl_zarray))
    # compare shapes
    @test size(jl_zarray.data) == pyconvert(Tuple,py_zarray.shape)
    # test values equal
    py_data, ok = try
        Array(PyArray(py_zarray.get_basic_selection())), true
    catch e
        if endswith(e.msg, "cannot convert this Python 'ndarray' to a 'PyArray'")
            Array(PyArray(py_zarray.get_basic_selection().tobytes())), false
        else
            rethrow()
        end
    end
    if ok
        if eltype(py_data) <: PythonCall.Utils.StaticString{UInt32}
            @test rstrip.(String.(jl_zarray.data), '\0') == rstrip.(String.(py_data), '\0')
        else
            @test isequal(py_data,jl_zarray.data)
        end
    end
end


@testset "read fixture data and compare to zarr-python" begin
    disk_load_compare(zarr, joinpath(artifact"fixture", "fixture"))
    disk_load_compare(zarr, joinpath(artifact"fixture", "fixture.zip"))
    disk_load_compare(zarr, joinpath(artifact"fixture", "ring_system.zarr"))
    disk_load_compare(zarr, joinpath(artifact"fixture", "ring_system.zarr.zip"))
    # disk_load_compare(zarr, joinpath(@__DIR__,"example_all_sites_context.zarr"))
end

@testset "zarr-python zero dimensional array compatibility" begin
    g = ZGroup()
    a::Array{Float64, 0} = fill(3.25)
    b::Array{Int8, 0} = fill(Int8(2))
    c::Array{UInt8, 0} = fill(UInt8(0xFF))
    g["a"] = a
    g["b"] = b
    g["c"] = c
    mktempdir() do path
        SmallZarrGroups.save_dir(path, g)
        disk_load_compare(zarr, path)
    end
end