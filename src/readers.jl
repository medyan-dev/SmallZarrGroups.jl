# Basic version of Zarr storage interface

# Doesn't support deleting, or changing data already written.

using ArgCheck
using ZipArchives


abstract type AbstractReader end

function norm_zarr_path(path::AbstractString)::String
    join(split(replace(path, '\\'=>'/'), '/'; keepempty=false), '/')
end


struct DirectoryReader <: AbstractReader
    path::String
    keys::Vector{String}
end

function DirectoryReader(dir)
    path = abspath(dir)
    @argcheck isdir(path)
    lp = ncodeunits(path)
    keys = String[]
    for (root, dirs, files) in walkdir(path)
        for file in files
            fullpath = joinpath(root[begin+lp:end],file)
            push!(keys, norm_zarr_path(fullpath))
        end
    end
    DirectoryReader(path, keys)
end

function key_names(d::DirectoryReader)::Vector{String}
    return d.keys
end

"""
Read the bytes stored at key idx.
"""
function read_key_idx(d::DirectoryReader, idx::Int)::Vector{UInt8}
    key = d.keys[idx]
    filename = joinpath([d.path; split(key,"/")])
    read(filename)
end


struct BufferedZipReader <: AbstractReader
    zipfile::ZipBufferReader{Vector{UInt8}}
    function BufferedZipReader(path)
        @argcheck isfile(path)
        new(ZipBufferReader(read(path)))
    end
end

function key_names(d::BufferedZipReader)::Vector{String}
    return zip_names(d.zipfile)
end

function read_key_idx(d::BufferedZipReader, idx::Int)::Vector{UInt8}
    zip_readentry(d.zipfile, idx)
end