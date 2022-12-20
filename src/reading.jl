# reading a storage tree from a directory or zip file.

function load_dir(reader::AbstractReader)::ZGroup
    output = ZGroup()
    keynames =  key_names(reader)
    splitkeys = map(x->split(x,'/';keepempty=false), keynames)
    for (key_idx, splitkey) in enumerate(splitkeys)
        if length(splitkey) < 2
            continue
        end
        if splitkey[end] == ".zgroup"
            output[join(splitkey[begin:end-1],'/')] = ZGroup()
        elseif splitkey[end] == ".zarray"
            metadata = parse_zarr_metadata(JSON3.read(read_key_idx(reader, key_idx)))
            fill_value = reinterpret(metadata.dtype.julia_type, metadata.fill_value)[1]
            array = fill(fill_value, metadata.shape...)
            ZArray(array;
                chunks = Tuple(metadata.chunks),
                compressor = metadata.compressor,
            )
        end
    end
    for (key_idx, splitkey) in enumerate(splitkeys)

            



    load_zgroup(dirpath, "/")
end