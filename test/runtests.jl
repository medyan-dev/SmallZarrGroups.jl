using Test
using Random

Random.seed!(1234)

include("test_zarr-type-parsing.jl")
include("test_storage_trees.jl")
include("test_simple-usage.jl")