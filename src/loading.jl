# loading a storage tree from a directory or zip file.
using EllipsisNotation

function load_dir(dirpath::AbstractString)::ZGroup
    if isdir(dirpath)
        load_dir(DirectoryReader(dirpath))
    elseif isfile(dirpath)
        error("zip file loading not implemented yet.")
    end
end


function try_add_attrs!(zthing::Union{ZGroup, ZArray}, reader::AbstractReader, keyname_dict,  key_prefix)
    attrsidx = get(Returns(0), keyname_dict, key_prefix*".zattrs")
    if attrsidx > 0
        jsonobj = JSON3.read(read_key_idx(reader,attrsidx); allow_inf=true)
        foreach(pairs(jsonobj)) do (k,v)
            attrs(zthing)[string(k)] = v
        end
    end
end

function load_dir(reader::AbstractReader)::ZGroup
    output = ZGroup()
    keynames = key_names(reader)
    splitkeys = map(x->split(x,'/';keepempty=false), keynames)
    keyname_dict = Dict(zip(keynames,eachindex(keynames)))
    try_add_attrs!(output, reader, keyname_dict, "")
    for splitkey in sort(splitkeys)
        if length(splitkey) < 2
            continue
        end
        if splitkey[end] == ".zgroup"
            groupname = join(splitkey[begin:end-1],'/')
            group = get!(ZGroup, output, groupname)
            try_add_attrs!(group, reader, keyname_dict, groupname*"/")
        elseif splitkey[end] == ".zarray"
            arrayname = join(splitkey[begin:end-1],'/')
            arrayidx = keyname_dict[arrayname*"/.zarray"]
            metadata = parse_zarr_metadata(JSON3.read(read_key_idx(reader, arrayidx)))
            fill_value = reinterpret(metadata.dtype.julia_type, metadata.fill_value)[1]
            shape, chunks = if metadata.is_column_major
                metadata.shape, metadata.chunks
            else
                reverse(metadata.shape), reverse(metadata.chunks)
            end
            array = fill(fill_value, shape...)
            zarr_size = metadata.dtype.zarr_size
            julia_size = metadata.dtype.julia_size

            # If there is no actual data don't load chunks
            if !(any(==(0), shape) || julia_size == 0 || zarr_size == 0)
                # load chunks
                for chunkidx in CartesianIndices(Tuple(cld.(shape,chunks)))
                    chunktuple = Tuple(chunkidx) .- 1
                    chunknametuple = if metadata.is_column_major
                        chunktuple
                    else
                        #shape and chunks have been pre reversed so reverse chunkidx as well.
                        reverse(chunktuple)
                    end
                    chunkname = arrayname*"/"*join(chunknametuple, metadata.dimension_separator)
                    chunknameidx = get(Returns(0), keyname_dict, chunkname)
                    if chunknameidx > 0
                        rawchunkdata = read_key_idx(reader, chunknameidx)
                        decompressed_chunkdata = decompress!(Vector{UInt8}(), rawchunkdata, metadata)
                        chunkstart = chunktuple .* chunks .+ 1
                        chunkstop = min.(chunkstart .+ chunks .- 1, shape)
                        real_chunksize = chunkstop .- chunkstart .+ 1
                        if zarr_size == 1
                            shaped_chunkdata = reshape(decompressed_chunkdata, chunks...)
                            shaped_array = reinterpret(UInt8, array)
                            array_view = view(shaped_array, (range.(chunkstart, chunkstop))...)
                            chunk_view = view(shaped_chunkdata, (range.(1, real_chunksize))...)
                            array_view .= chunk_view
                        else
                            shaped_chunkdata = reshape(decompressed_chunkdata, zarr_size, chunks...)
                            shaped_array = reinterpret(reshape, UInt8, array)
                            # now create overlapping views
                            array_view = view(shaped_array, :, (range.(chunkstart, chunkstop))...)
                            chunk_view = view(shaped_chunkdata, :, (range.(1, real_chunksize))...)
                            # TODO check if the data can just be directly copied.
                            for (zarr_byte, julia_byte) in enumerate(metadata.dtype.byteorder)
                                array_view[julia_byte, ..] .= chunk_view[zarr_byte, ..]
                            end
                        end
                    end
                end
            end

            zarray = if metadata.is_column_major
                ZArray(array;
                    chunks = Tuple(chunks),
                    compressor = metadata.compressor,
                )
            else
                ZArray(permutedims(array,reverse(1:length(shape)));
                    chunks = Tuple(reverse(chunks)),
                    compressor = metadata.compressor,
                )
            end
            output[arrayname] = zarray

            try_add_attrs!(zarray, reader, keyname_dict, arrayname*"/")
        end
    end
    output
end
