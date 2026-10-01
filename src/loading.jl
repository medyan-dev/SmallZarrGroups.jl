# loading a storage tree from a directory or zip file.

function load_dir(dirpath::AbstractString; predicate=Returns(true))::ZGroup
    reader = if isdir(dirpath)
        DirectoryReader(dirpath)
    elseif isfile(dirpath)
        ZarrZipReader(read(dirpath))
    else
        throw(ArgumentError("loading directory $(repr(dirpath)): No such file or directory"))
    end
    load_dir(reader; predicate)
end

"""
    load_zip(filename::AbstractString)::ZGroup
    load_zip(data::Vector{UInt8})::ZGroup


Load data in a file `filename` or a `data` vector in ZipStore format.
"""
function load_zip(filename::AbstractString; predicate=Returns(true))::ZGroup
    reader = ZarrZipReader(read(filename))
    load_dir(reader; predicate)
end
function load_zip(data::Vector{UInt8}; predicate=Returns(true))::ZGroup
    reader = ZarrZipReader(data)
    load_dir(reader; predicate)
end


function try_add_attrs!(@nospecialize(zthing::Union{ZGroup, ZArray}), reader::AbstractReader, keyname_dict,  key_prefix)
    attrsidx = get(Returns(0), keyname_dict, key_prefix*".zattrs")
    if attrsidx > 0
        zthing.attrs = JSON.parse(read_key_idx(reader, attrsidx), OrderedDict{String,Any})
    end
end

function load_dir(reader::AbstractReader; predicate=Returns(true))::ZGroup
    output = ZGroup()
    keynames = key_names(reader)
    splitkeys = Vector{SubString{String}}[]
    keyname_dict = Dict{String, Int}()
    for (key_idx, rawkeyname) in enumerate(keynames)
        # Skip directory entries in zip files.
        endswith(rawkeyname, '/') && continue
        # Keys are looked up by their normalized name,
        # so different spellings of a key, like "a//0" and "a/0", must not both exist.
        keyname = norm_zarr_path(rawkeyname)
        if predicate(keyname)
            if haskey(keyname_dict, keyname)
                otherrawkeyname = keynames[keyname_dict[keyname]]
                if otherrawkeyname == rawkeyname
                    throw(ArgumentError("duplicate key $(repr(rawkeyname))"))
                else
                    throw(ArgumentError("keys $(repr(otherrawkeyname)) and $(repr(rawkeyname)) are both the key $(repr(keyname))"))
                end
            end
            push!(splitkeys, split(keyname, '/'))
            keyname_dict[keyname] = key_idx
        end
    end
    try_add_attrs!(output, reader, keyname_dict, "")
    for splitkey in sort(splitkeys)
        if length(splitkey) < 2
            continue
        end
        if splitkey[end] == ".zgroup"
            path = _check_path(@view(splitkey[begin:end-1]))
            # Throws an `ArgumentError` if an array is already there.
            group = makegroups(output, path)
            try_add_attrs!(group, reader, keyname_dict, join(path, '/')*"/")
        elseif splitkey[end] == ".zarray"
            path = _check_path(@view(splitkey[begin:end-1]))
            arrayname = join(path, '/')
            parent = makegroups(output, @view(path[begin:end-1]))
            # Don't silently replace a group that has already been loaded.
            if haskey(parent.children, path[end])
                throw(ArgumentError("$(repr(arrayname)) is both an array and a group"))
            end
            meta = parse_zarray(read_key_idx(reader, keyname_dict[arrayname*"/.zarray"]))
            # `invokelatest` stops Julia from wasting time inferring the generic `load_array`,
            # only the concrete versions are ever run.
            zarray = invokelatest(load_array, meta.dtype, Val(length(meta.shape)), meta, arrayname, keyname_dict, reader)::ZArray
            parent.children[path[end]] = zarray

            try_add_attrs!(zarray, reader, keyname_dict, arrayname*"/")
        end
    end
    output
end


"""
Load the chunks of the array described by `meta`.

This is the function barrier where the element type `T` and number of dimensions `N` become static.
"""
function load_array(
        ::Type{T}, ::Val{N}, meta::ZarrayMetadata,
        arrayname::String, keyname_dict::Dict{String,Int}, reader,
    )::ZArray{T,N} where {T, N}
    shape = ntuple(i -> meta.shape[i], Val(N))
    chunks = ntuple(i -> meta.chunks[i], Val(N))
    c = meta.compressor
    data = fill(parse_zarr_fill_value(T, meta.fill_value), shape)
    # If there is no actual data don't load chunks
    if sizeof(T) != 0 && !any(iszero, shape)
        chunk = Vector{UInt8}(undef, chunk_nbytes(sizeof(T), chunks))
        for index in CartesianIndices(cld.(shape, chunks))
            key_idx = get(keyname_dict, arrayname*"/"*chunk_key(index, meta.dimension_separator), 0)
            # Missing chunks are left as the fill value.
            iszero(key_idx) && continue
            decode_chunk!(chunk, c, read_key_idx(reader, key_idx))
            if T === Bool
                # Like numpy, any nonzero byte is `true`.
                for i in eachindex(chunk)
                    chunk[i] = !iszero(chunk[i])
                end
            end
            copy_from_chunk!(data, chunk, chunks, c.reverse_dims, index)
        end
    end
    ZArray(data, chunks, c)
end
