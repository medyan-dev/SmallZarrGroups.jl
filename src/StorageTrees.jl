module StorageTrees

# An interface for storing a tree of named arrays and attributes to disk with per array compression options.
# The API is inspired by zarr-python, and uses zarr-python via PythonCall to actually store the arrays to disk.

# This version of the API ZArray doesn't have any type parameters.

using DataStructures: SortedDict, OrderedDict
using ArgCheck
using AbstractTrees
using JSON3

export ZGroup
export attrs
export children

include("ZArray.jl")
include("ZGroup.jl")


include("zarr-meta-parsing.jl")
include("zarr-meta-writing.jl")
include("compression.jl")
include("readers.jl")
include("loading.jl")
include("writers.jl")
include("saving.jl")
include("extra.jl")

end