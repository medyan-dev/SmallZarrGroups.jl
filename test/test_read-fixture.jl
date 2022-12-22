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
end

@testset "read fixture data and compare to zarr-python" begin
    disk_load_compare(zarr)
end
