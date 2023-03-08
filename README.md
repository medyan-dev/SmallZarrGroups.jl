# StorageTrees (WIP)

[![Build Status](https://github.com/medyan-dev/StorageTrees.jl/workflows/CI/badge.svg)](https://github.com/medyan-dev/StorageTrees.jl/actions)
[![codecov](https://codecov.io/gh/medyan-dev/StorageTrees.jl/branch/main/graph/badge.svg?token=UUOFUEIX8K)](https://codecov.io/gh/medyan-dev/StorageTrees.jl)

In memory hierarchy of arrays and attributes loaded from disk or to be saved to disk with [Zarr](https://zarr.readthedocs.io/en/stable/spec/v2.html#).

## Warning: StorageTrees is currently a WIP and its API may drastically change at any time.

## Limitations

1. If you need to store huge datasets that cannot fit uncompressed in memory consider using https://github.com/JuliaIO/HDF5.jl or https://github.com/JuliaIO/Zarr.jl

1. If you just want to serialize arbitrary Julia data consider using https://github.com/JuliaIO/JLD2.jl or https://github.com/invenia/JLSO.jl
2. Numpy datetime64 (“M”) and timedelta64 (“m”) data types are read as Int64.
3. Zarr filters are not supported.

## Overview

1. `ZGroup` represents a tree with arrays as leaves.
1. `ZGroup` leaf arrays are uncompressed but store metadata about how they should be compressed when saved to disk.
1. `ZGroup` can have JSON3 serializable attributes attached to any node or leaf.
1. Data can be quickly accessed and modified in `ZGroup`.
1. No file open close semantics. Use the Julia garbage collector to clean memory up.
1. Save and load `ZGroup` in a directory or zip file in [Zarr v2 format](https://zarr.readthedocs.io/en/stable/spec/v2.html#).
1. `ZGroup` saved to a directory or zip file can be read in other languages.


## Examples

See [test/test_simple-usage.jl](test/test_simple-usage.jl) 
for examples and documentation.
