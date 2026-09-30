

"""
If dirpath ends in .zip, save to a zip file, otherwise save to a directory.

Note this will delete pre existing data at dirpath
"""
function save_dir(dirpath::AbstractString, z::ZGroup)
    if endswith(dirpath, ".zip")
        @argcheck !isdir(dirpath)
        mkpath(dirname(dirpath))
        save_zip(dirpath, z)
    else
        save_dir(DirectoryWriter(dirpath), z)
    end
    nothing
end
function save_dir(writer::AbstractWriter, z::ZGroup)
    # TODO add something to prevent loops
    _save_zgroup(writer, "", z::ZGroup)
end

"""
    save_zip(filename::AbstractString, z::ZGroup)
    save_zip(io::IO, z::ZGroup)

Save data in a file `filename` or an `io` in ZipStore format.
Note this will delete pre existing data in `filename`.
The `io` passed to this function must be empty.
This function will not close `io`.
"""
function save_zip(filename::AbstractString, z::ZGroup)::Nothing
    open(filename; write=true) do io
        save_zip(io, z)
    end
end
function save_zip(io::IO, z::ZGroup)::Nothing
    writer = ZarrZipWriter(io)
    try
        save_dir(writer, z)
    finally
        closewriter(writer)
    end
end

"""
Save the attributes as JSON, if there are any.
"""
function _save_attrs(writer::AbstractWriter, key_prefix::String, z::Union{ZArray,ZGroup})
    if isempty(attrs(z))
        return
    end
    write_key(writer, key_prefix*".zattrs", codeunits(JSON.json(attrs(z); allownan=true)))
    return
end

function _save_zgroup(writer::AbstractWriter, key_prefix::String, z::ZGroup)
    group_key = key_prefix*".zgroup"
    write_key(writer, group_key, codeunits("{\"zarr_format\":2}"))
    _save_attrs(writer, key_prefix, z)
    for (k,v) in pairs(children(z))
        @argcheck !isempty(k)
        @argcheck k != "."
        @argcheck k != ".."
        @argcheck k ∉ RESERVED_NAMES
        @argcheck '/' ∉ k
        @argcheck '\\' ∉ k
        child_key_prefix = String(key_prefix*k*"/")
        if v isa ZGroup
            _save_zgroup(writer, child_key_prefix, v)
        elseif v isa ZArray
            _save_zarray(writer, child_key_prefix, v)
        else
            error("unreachable") # COV_EXCL_LINE
        end
    end
end


"""
Save the chunks and metadata of `z`.

Dispatching on `ZArray{T,N}` is the function barrier where `T` and `N` become static.
"""
function _save_zarray(writer::AbstractWriter, key_prefix::String, z::ZArray{T,N}) where {T, N}
    _save_attrs(writer, key_prefix, z)
    data = getarray(z)
    c = z.compressor
    # If there is no actual data don't save chunks
    if sizeof(T) != 0 && !any(iszero, size(data))
        chunk = Vector{UInt8}(undef, chunk_nbytes(sizeof(T), z.chunks))
        for index in CartesianIndices(cld.(size(data), z.chunks))
            copy_to_chunk!(chunk, data, z.chunks, c.reverse_dims, index)
            write_key(writer, key_prefix*chunk_key(index, '.'), encode_chunk(c, chunk))
        end
    end
    write_key(writer, key_prefix*".zarray", zarray_json(T, size(data), z.chunks, c))
end
