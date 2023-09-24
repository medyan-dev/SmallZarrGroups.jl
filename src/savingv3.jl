

"""
If dirpath ends in .zip, save to a zip file, otherwise save to a directory.

Note this will delete pre existing data at dirpath
"""
function save_dir(dirpath::AbstractString, z::ZGroup)
    if endswith(dirpath, ".zip")
        @argcheck !isdir(dirpath)
        mkpath(dirname(dirpath))
        open(dirpath; write=true) do io
            writer = ZarrZipWriter(io)
            try
                save_dir(writer, z)
            finally
                closewriter(writer)
            end
        end
    else
        save_dir(DirectoryWriter(dirpath), z)
    end
    nothing
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
    write_key(writer, key_prefix*".zattrs", codeunits(sprint(io->JSON3.pretty(io,attrs(z); allow_inf=true))))
    return
end

function _save_zgroup(writer::AbstractWriter, key_prefix::String, z::ZGroup)
    group_key = key_prefix*"zarr.json"
    io = IOBuffer()
    write(io, "{\"zarr_format\":3, \"node_type\":\"group\"")
    if !isempty(attrs(z))
        write(io, ", \"attributes\":\n")
        JSON3.pretty(io, attrs(z); allow_inf=true)
    end
    write(io, "}")
    write_key(writer, group_key, codeunits(String(take!(io))))
    for (k,v) in pairs(children(z))
        @argcheck !isempty(k)
        @argcheck !all(==(UInt8('.')), codeunits(k))
        @argcheck !startswith(k, "__")
        @argcheck UInt8('/') ∉ codeunits(k)
        @argcheck UInt8(0) ∉ codeunits(k)
        @argcheck k != "zarr.json"
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


function _save_zarray(writer::AbstractWriter, key_prefix::String, z::ZArray)
    data = getarray(z)
    array_metadata = OrderedDict{String,Any}()
    array_metadata["zarr_format"] = 3
    array_metadata["node_type"] = "array"
    array_metadata["shape"] = collect(size(data))
    # TODO optional dimension_names
    array_metadata["data_type"] = zarr_data_type(eltype(data))
    array_metadata["fill_value"] = zarr_fill_value(eltype(data))
    array_metadata["chunk_grid"] = [
        "name" => "regular",
        "configuration" => ["chunk_shape" => z.chunks]
    ]
    array_metadata["chunk_key_encoding"] = ["name" => "default"]
    array_metadata["codecs"] = [
        
    ]
    if !isempty(attrs(z))
        array_metadata["attributes"] = attrs(z)
    end
    shape = size(data)
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
            # empty chunk has name "0" this is the case for zero dim arrays
            chunkname = key_prefix*"c"*join('/'.*chunktuple)
            write_key(writer, chunkname, compressed_chunkdata)
        end
    end

    # store array meta data
    write_key(writer, key_prefix*".zarray",
        codeunits("""
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
        """)
    )
end
