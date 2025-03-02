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


function try_add_attrs!(zthing::Union{ZGroup, ZArray}, reader::AbstractReader, keyname_dict,  key_prefix)
    attrsidx = get(Returns(0), keyname_dict, key_prefix*".zattrs")
    if attrsidx > 0
        jsonobj = JSON3.read(read_key_idx(reader,attrsidx); allow_inf=true)
        foreach(pairs(jsonobj)) do (k,v)
            attrs(zthing)[string(k)] = v
        end
    end
end

function load_dir(reader::AbstractReader; predicate=Returns(true))::ZGroup
    output = ZGroup()
    keynames = key_names(reader)
    splitkeys = Vector{SubString{String}}[]
    keyname_dict = Dict{String, Int}()
    for (key_idx, keyname) in enumerate(keynames)
        if predicate(keyname)
            push!(splitkeys, split(keyname,'/';keepempty=false))
            keyname_dict[keyname] = key_idx
        end
    end
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
            fill_value = metadata.fill_value
            zarray = load_array(
                fill_value,
                Tuple(metadata.shape),
                Tuple(metadata.chunks),
                arrayname,
                metadata.dimension_separator,
                keyname_dict,
                reader,
                metadata.dtype.in_native_order,
                metadata.is_column_major,
                metadata.compressor,
            )


            output[arrayname] = zarray

            try_add_attrs!(zarray, reader, keyname_dict, arrayname*"/")
        end
    end
    output
end


function load_array(
        fill_value::T,
        shape::NTuple{N, Int},
        chunks::NTuple{N, Int},
        arrayname::String,
        dimension_separator::Char,
        keyname_dict::Dict{String,Int},
        reader,
        in_native_order::Bool,
        is_column_major::Bool,
        compressor,
    )::ZArray{T, N} where {T, N}
    array = fill(fill_value, shape...)
    # If there is no actual data don't load chunks
    if !(any(==(0), shape) || sizeof(T) == 0)
        # load chunks
        for chunkidx in CartesianIndices(Tuple(cld.(shape,chunks)))
            chunktuple = Tuple(chunkidx) .- 1
            # empty chunk has name "0" this is the case for zero dim arrays
            chunkname = arrayname*"/"*(isempty(chunktuple) ? "0" : join(chunktuple, dimension_separator))
            chunknameidx = get(Returns(0), keyname_dict, chunkname)
            if chunknameidx > 0
                rawchunkdata = read_key_idx(reader, chunknameidx)
                decompressed_chunkdata = Vector{T}(undef, prod(chunks))
                decompress!(
                    reinterpret(UInt8, decompressed_chunkdata),
                    rawchunkdata,
                    compressor,
                )
                if !in_native_order
                    for i in eachindex(decompressed_chunkdata)
                        decompressed_chunkdata[i] = htol(ntoh(decompressed_chunkdata[i]))
                    end
                end
                chunkstart = chunktuple .* chunks .+ 1
                chunkstop = min.(chunkstart .+ chunks .- 1, shape)
                real_chunksize = chunkstop .- chunkstart .+ 1
                
                shaped_chunkdata = if is_column_major || N ≤ 1
                    reshape(decompressed_chunkdata, chunks...)
                else
                    permutedims(reshape(decompressed_chunkdata, reverse(chunks)...), ((N:-1:1)...,))
                end
                copyto!(
                    array,
                    CartesianIndices(((range.(chunkstart, chunkstop))...,)),
                    shaped_chunkdata,
                    CartesianIndices(((range.(1, real_chunksize))...,))
                )
            end
        end
    end

    ZArray(array;
        chunks,
        compressor,
    )
end