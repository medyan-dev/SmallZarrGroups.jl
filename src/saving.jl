
"""
If dirpath ends in .zip, save to a zip file, otherwise save to a directory.
"""
function save_dir(dirpath::AbstractString, z::ZGroup)
    writer = if endswith(dirpath, ".zip")
        BufferedZipWriter(dirpath)
    else
        DirectoryWriter(dirpath)
    end
    save_dir(writer, z)
    closewriter(writer)
end


"""
Note this will delete pre existing data at dirpath
"""
function save_dir(writer::AbstractWriter, z::ZGroup)
    # TODO add something to prevent loops
    _save_zgroup(writer, "", z::ZGroup)
end

"""
save attributes using JSON3
"""
function _save_attrs(writer::AbstractWriter, key_prefix::String, z::Union{ZArray,ZGroup})
    if isempty(attrs(z))
        return
    end
    write_key(writer, key_prefix*".zattrs", sprint(io->JSON3.pretty(io,attrs(z); allow_inf=true)))
    return
end

function _save_zgroup(writer::AbstractWriter, key_prefix::String, z::ZGroup)
    group_key = key_prefix*".zgroup"
    write_key(writer, group_key, "{\"zarr_format\":2}")
    _save_attrs(writer, key_prefix, z)
    for (k,v) in pairs(children(z))
        @argcheck !isempty(k)
        @argcheck k != "."
        @argcheck k != ".."
        @argcheck '/' ∉ k
        @argcheck '\\' ∉ k
        child_key_prefix = String(key_prefix*k*"/")
        if v isa ZGroup
            _save_zgroup(writer, child_key_prefix, v)
        elseif v isa ZArray
            _save_zarray(writer, child_key_prefix, v)
        else
            error("unreachable")
        end
    end
end


function _save_zarray(writer::AbstractWriter, key_prefix::String, z::ZArray)
    _save_attrs(writer, key_prefix, z)
    # Get type info
    data = getarray(z)
    dtype_str::String = sprint(write_type, eltype(data))
    dtype::ParsedType = parse_zarr_type(JSON3.read(dtype_str))
    @assert dtype.julia_type == eltype(data)
    shape = size(data)
    zarr_size = dtype.zarr_size
    norm_compressor = normalize_compressor(z.compressor)
    if zarr_size != 0 && !any(iszero, shape)
        chunks = Tuple(z.chunks)
        # store chunks
        shaped_chunkdata = zeros(UInt8, zarr_size, chunks...)
        shaped_array = if dtype.julia_size == 1
            reshape(reinterpret(reshape, UInt8, data), 1, shape...)
        else
            reinterpret(reshape, UInt8, data)
        end
        for chunkidx in CartesianIndices(Tuple(cld.(shape,chunks)))
            chunktuple = Tuple(chunkidx) .- 1
            chunkstart = chunktuple .* chunks .+ 1
            chunkstop = min.(chunkstart .+ chunks .- 1, shape)
            real_chunksize = chunkstop .- chunkstart .+ 1
            # now create overlapping views
            array_view = view(shaped_array, :, (range.(chunkstart, chunkstop))...)
            chunk_view = view(shaped_chunkdata, :, (range.(1, real_chunksize))...)
            # TODO check if the data can just be directly copied.
            for (zarr_byte, julia_byte) in enumerate(dtype.byteorder)
                selectdim(chunk_view, 1, zarr_byte) .= selectdim(array_view, 1, julia_byte)
            end
            compressed_chunkdata = compress(norm_compressor, reshape(shaped_chunkdata,:), zarr_size)
            chunkname = key_prefix*join(chunktuple, '.')
            write_key(writer, chunkname, compressed_chunkdata)
        end
    end
    # store array meta data
    write_key(writer, key_prefix*".zarray",
        """
        {
            "chunks": [$(join(z.chunks, ", "))],
            "compressor": $(JSON3.write(norm_compressor; allow_inf=true)),
            "dtype": $dtype_str,
            "fill_value": null,
            "filters": null,
            "order": "F",
            "shape": [$(join(shape, ", "))],
            "zarr_format": 2
        }
        """
    )
end
