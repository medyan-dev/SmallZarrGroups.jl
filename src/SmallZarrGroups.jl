module SmallZarrGroups


using DataStructures: SortedDict, OrderedDict
using ArgCheck
using AbstractTrees
using JSON
using PrecompileTools: @compile_workload

export ZGroup
export attrs
export children

include("compression.jl")
include("ZArray.jl")
include("ZGroup.jl")
include("zarr-meta-parsing.jl")
include("zarr-meta-writing.jl")
include("strided-copy.jl")
include("chunks.jl")
include("readers.jl")
include("loading.jl")
include("writers.jl")
include("saving.jl")
include("experimental/print-diff.jl")
include("experimental/structarrays.jl")

precompile(parse_zarray, (Vector{UInt8},))
precompile(try_add_attrs!, (Union{ZGroup, ZArray}, ZarrZipReader, Dict{String, Int}, String))
precompile(load_zip, (String,))
precompile(load_zip, (Vector{UInt8},))
for N in 1:4
    precompile(zarray_json, (Type, NTuple{N, Int}, NTuple{N, Int}, CompressorOptions))
end
const PRECOMPILE_TYPES = (Bool, Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64, Float32, Float64)
for T in PRECOMPILE_TYPES, N in 1:4
    precompile(ZArray, (Array{T, N},))
    precompile(load_array, (Type{T}, Val{N}, ZarrayMetadata, String, Dict{String, Int}, ZarrZipReader))
end
# `setindex!` stores arrays in the children `SortedDict` with a runtime dispatch,
# so it is precompiled by running it.
# Saving to and loading from a `Vector{UInt8}` is also run, so time to first save and load is fast.
@compile_workload begin
    g = ZGroup()
    for T in PRECOMPILE_TYPES, N in 1:4
        g["a"] = ZArray(Array{T, N}(undef, ntuple(Returns(0), N)))
    end
    g = ZGroup()
    attrs(g)["a"] = "b"
    for T in PRECOMPILE_TYPES, N in 1:4
        g["$(T)/$(N)"] = zeros(T, ntuple(Returns(2), N))
    end
    g["none"] = ZArray(zeros(UInt8, 2); compressor=COMPRESSOR_NONE)
    attrs(g["none"])["a"] = 1
    gload = load_zip(save_zip(Vector{UInt8}, g))
    for T in PRECOMPILE_TYPES, N in 1:4
        gload["$(T)/$(N)"][begin]
    end
end

end