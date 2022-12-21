# reading a storage tree from a directory or zip file.

function load_dir(reader::AbstractReader)::ZGroup
    output = ZGroup()
    keynames = key_names(reader)
    splitkeys = map(x->split(x,'/';keepempty=false), keynames)
    keyname_dict = Dict(zip(keynames,eachindex(keynames)))
    rawchunkdata = Vector{UInt8}()
    chunkdata = Vector{UInt8}()
    for splitkey in sort(splitkeys)
        if length(splitkey) < 2
            continue
        end
        if splitkey[end] == ".zgroup"
            groupname = join(splitkey[begin:end-1],'/')
            group = get!(ZGroup, output, groupname)
            attrsidx = get(Returns(0), keyname_dict, groupname*"/.zattrs")
            if attrsidx > 0
                jsonobj = JSON3.read(read_key_idx(reader,attrsidx); allow_inf=true)
                foreach(pairs(jsonobj)) do (k,v)
                    attrs(group)[string(k)] = v
                end
            end
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
                    chunknametuple = if metadata.is_column_major
                        Tuple(chunkidx)
                    else
                        #shape and chunks have been pre reversed so reverse chunkidx as well.
                        reverse(Tuple(chunkidx))
                    end
                    chunkname = arrayname*"/"*join(chunknametuple, metadata.dimension_separator)
                    chunknameidx = get(Returns(0), keyname_dict, chunkname)
                    if chunknameidx > 0
                        read_key_idx!(rawchunkdata, reader, chunknameidx)
                        decompressed_chunkdata = decompress!(chunkdata, rawchunkdata, metadata)
                        shaped_chunkdata = reshape(decompressed_chunkdata, zarr_size, chunks...)
                        shaped_array = reinterpret(reshape, UInt8, array)
                        # now create overlapping views
                        
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


            # load attributes
            attrsidx = get(Returns(0), keyname_dict, arrayname*"/.zattrs")
            if attrsidx > 0
                jsonobj = JSON3.read(read_key_idx(reader,attrsidx); allow_inf=true)
                foreach(pairs(jsonobj)) do (k,v)
                    attrs(zarray)[string(k)] = v
                end
            end

            
            
        end
    end
end
