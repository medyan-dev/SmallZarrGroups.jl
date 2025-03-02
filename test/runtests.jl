using Test
using Random
using CondaPkg

CondaPkg.add("zarr"; version="2.*")

Random.seed!(1234)

include("test_zarr-meta-parsing.jl")
include("test_zarr-meta-writing.jl")
include("test_simple-usage.jl")
include("test_read-write-fixture.jl")
include("test_loading-errors.jl")
include("test_edge-cases.jl")
include("experimental/test_chunking.jl")
include("experimental/test_compressors.jl")
include("experimental/test_structarrays.jl")
include("experimental/test_print_diff.jl")