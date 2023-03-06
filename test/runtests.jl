using Test
using Random

Random.seed!(1234)

include("test_zarr-meta-parsing.jl")
include("test_zarr-meta-writing.jl")
include("test_simple-usage.jl")
include("test_read-write-fixture.jl")
include("test_loading-errors.jl")
include("test_extras.jl")