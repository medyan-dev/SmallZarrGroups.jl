# Zarr.jl reading SmallZarrGroups output: TODO

Zarr.jl 0.10.2 can't read these:

- [ ] **Shuffle filter**, which is on by default for element types bigger than 1 byte.
      Reading throws a `BoundsError`, because `zuncompress!` at `src/Compressors/Compressors.jl:54`
      copies the unshuffled bytes into the `Array{T}` element by element. Reinterpret them as `T` first.
- [ ] **`order: "F"`** (`reverse_dims=true`), rejected at `src/metadata.jl:126`.
- [ ] **`"|Vn"` dtypes** (`NTuple{n,UInt8}`), which aren't in `typemap` (`src/metadata.jl:43`).
      `_zero` also needs a method for them. For `"|V0"`, no chunk files are written, and that's deliberate:
      zarr-python can't read its own empty chunk files.
- [ ] **`NaN`, `Infinity` and `-Infinity` in `.zattrs`.** Parse with `allownan=true` instead of the `": NaN,"`
      string replacement at `src/Storage/Storage.jl:104`.

The last three are thrown by `zopen`, so one bad array or attribute makes the whole file unreadable.
