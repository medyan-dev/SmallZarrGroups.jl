using Test
using Random

Random.seed!(1234)

include("test_zarr-meta-parsing.jl")
include("test_storage_trees.jl")
include("test_simple-usage.jl")
include("test_read-write-fixture.jl")