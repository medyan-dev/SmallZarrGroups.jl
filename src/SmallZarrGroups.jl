module SmallZarrGroups


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
include("experimental/print-diff.jl")
include("experimental/structarrays.jl")


end