# Basic version of Zarr storage interface

# Doesn't support deleting, or changing data already written.

using ArgCheck


abstract type AbstractReader end


struct DirectoryReader <: AbstractReader
    path::String
    keys::::Vector{String}
end

function DirectoryReader(dir)
    path = abspath(dir)
    @argcheck isdir(path)
    lp = length(path)
    keys = String[]
    for (root, dirs, files) in walkdir(path)
        for file in files
            fullpath = joinpath(root[begin+lp:end],file)
            fullpath = replace(fullpath, '\\'=>'/')
            fullpath = strip(fullpath, '/')
            while "//" in fullpath
                fullpath = replace(fullpath, "//"=>"/")
            end
            push!(keys, "/"*fullpath)
        end
    end
    DirectoryReader(path, keys)
end

function key_names(d::DirectoryReader)::Vector{String}
    return d.keys
end

function read_key_idx(d::DirectoryReader, idx::Int)::Vector{Uint8}
    key = d.keys[idx]
    read(joinpath([d.path; split(key,"/")]))
end