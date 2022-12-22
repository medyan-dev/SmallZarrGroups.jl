using StorageTrees
using DataStructures: SortedDict, OrderedDict
using Test
using Pkg.Artifacts

using PythonCall

zarr = pyimport("zarr")


"""
Compare the results of reading a directory with zarr-python and StorageTrees.

The directory must be a group, not an array.
This function is call 
"""
function disk_load_compare(zarr, dirpath=joinpath(artifact"fixture","fixture"))
    # get path of python group
    python_group = zarr.open_group(
        store=zarr.DirectoryStore(dirpath),
        path="/", # Group path within store.
        mode="r", # Persistence mode: 
            # ‘r’ means read only (must exist); 
            # ‘r+’ means read/write (must exist); 
            # ‘a’ means read/write (create if doesn’t exist); 
            # ‘w’ means create (overwrite if exists); 
            # ‘w-’ means create (fail if exists).
    )
    zgroup = StorageTrees.load_dir(StorageTrees.DirectoryReader(dirpath))
    compare_jl_py_groups(zgroup, python_group)


end


function compare_jl_py_groups(jl_group::ZGroup, py_group)
    @test PyDict(py_group.attrs.asdict()) == attrs(jl_group)
    py_subgroup_keys::Vector{String} = sort(string.(collect(py_group.group_keys())))
    jl_subgroup_keys = map(first ,filter(x->x[2] isa ZGroup, collect(pairs(jl_group))))
    @test py_subgroup_keys == jl_subgroup_keys
    for groupkey in py_subgroup_keys
        compare_jl_py_groups(jl_group[groupkey], py_group[groupkey])
    end
    #test arrays are equal
    py_array_keys::Vector{String} = sort(string.(collect(py_group.array_keys())))
    jl_array_keys = map(first ,filter(x->x[2] isa StorageTrees.ZArray, collect(pairs(jl_group))))
    @test py_array_keys == jl_array_keys
    for arraykey in py_array_keys
        compare_jl_py_zarray(jl_group[arraykey], py_group[arraykey])
    end
end

function compare_jl_py_zarray(jl_zarray::StorageTrees.ZArray, py_zarray)
    @test PyDict(py_zarray.attrs.asdict()) == attrs(jl_zarray)
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
    disk_load_compare(zarr)
end
