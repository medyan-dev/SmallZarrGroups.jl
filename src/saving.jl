

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
    group_key = key_prefix*".zgroup"
    write_key(writer, group_key, codeunits("{\"zarr_format\":2}"))
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
            error("unreachable") # COV_EXCL_LINE
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
    zarr_size = dtype.type_size
    norm_compressor = normalize_compressor(z.compressor)
    if zarr_size != 0 && !any(iszero, shape)
        chunks = Tuple(z.chunks)
        # store chunks
        shaped_chunkdata = zeros(UInt8, zarr_size, reverse(chunks)...)
        permuted_shaped_chunkdata = PermutedDimsArray(shaped_chunkdata, (1, ndims(z)+1:-1:2...))
        shaped_array = if zarr_size == 1
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
            chunk_view = view(permuted_shaped_chunkdata, :, (range.(1, real_chunksize))...)
            copy!(chunk_view, array_view)
            compressed_chunkdata = compress(norm_compressor, reshape(shaped_chunkdata,:), zarr_size)
            # empty chunk has name "0" this is the case for zero dim arrays
            chunkname = key_prefix*(isempty(chunktuple) ? "0" : join(chunktuple, '.'))
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
            "order": "C",
            "shape": [$(join(shape, ", "))],
            "zarr_format": 2
        }
        """)
    )
end
