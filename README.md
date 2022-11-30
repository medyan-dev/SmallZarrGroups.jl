# StorageTrees (WIP)

[![Build Status](https://github.com/medyan-dev/StorageTrees.jl/workflows/CI/badge.svg)](https://github.com/medyan-dev/StorageTrees.jl/actions)



In memory hierarchy of arrays and attributes loaded from disk or to be saved to disk with Zarr.

## Warning: StorageTrees is currently a WIP and its API may drastically change at any time.

If you need to store huge datasets that cannot fit uncompressed in memory consider using https://github.com/JuliaIO/HDF5.jl or https://github.com/JuliaIO/Zarr.jl

If you just want to serialize arbitrary Julia data consider using https://github.com/JuliaIO/JLD2.jl or https://github.com/invenia/JLSO.jl

## Goals

1. `ZGroup` represents a tree with arrays as leaves.
1. `ZGroup` leaf arrays are uncompressed but store metadata about how they should be losslessly compressed when saved to disk.
1. `ZGroup` can have JSON3 serializable attributes attached to any node or leaf.
1. Data can be quickly accessed and modified in `ZGroup`.
1. No file open close semantics. Use the Julia garbage collector to clean memory up.
1. Save and load `ZGroup` in a directory in Zarr format.
1. `ZGroup` saved to a directory can be read in other languages.


## Examples

Create an empty `ZGroup` with:

```julia
using StorageTrees
zg = ZGroup()
```

Save and copy data to the group with:

```julia
zg["random_data"] = rand(30,10)
```

Save and copy data a sub group using "/" as a path separator.

All intermediate groups will be automatically created.

```julia
zg["group1/subgroup2/random_data"] = rand(30)
zg
```
```
📂 
├─ "group1" ⇒ 📂 
│             └─ "subgroup2" ⇒ 📂 
│                              └─ "random_data" ⇒ 🔢 30 Float64 
└─ "random_data" ⇒ 🔢 30×10 Float64 
```

Sub groups can also be added to a group.
Note unlike `setindex!` with an `AbstractArray`, this doesn't make a copy of the added group, it is just a reference.
```julia
othergroup = ZGroup()
othergroup["bar"] = rand(Int,3)
zg["innergroup2"] = othergroup
zg
```
```
📂 
├─ "group1" ⇒ 📂 
│             └─ "subgroup2" ⇒ 📂 
│                              └─ "random_data" ⇒ 🔢 30 Float64 
├─ "innergroup2" ⇒ 📂 
│                  └─ "bar" ⇒ 🔢 3 Int64 
└─ "random_data" ⇒ 🔢 30×10 Float64 
```


Arrays can be read with collect. This returns a copy of the array.

```julia-repl
julia> collect(zg["innergroup2/bar"])
3-element Vector{Int64}:
  8547501744104122400
 -1824477752480561305
  6628972061588725027

julia> collect(Int128,zg["innergroup2/bar"])
3-element Vector{Int128}:
  8547501744104122400
 -1824477752480561305
  6628972061588725027
```