# Basic version of Zarr storage interface

# Doesn't support deleting, or changing data already written.

using ArgCheck
using ZipArchives


abstract type AbstractWriter end

"""
Call to finish writing.
"""
function closewriter(::AbstractWriter)
end


struct DirectoryWriter <: AbstractWriter
    path::String
    function DirectoryWriter(dir)
        mkpath(dir)
        new(abspath(dir))
    end
end

"""
Add a key and value to the store.
"""
function write_key(d::DirectoryWriter, key::AbstractString, data)::Nothing
    @assert !endswith(key, "/")
    filename = joinpath([d.path; split(key,"/")])
    mkpath(dirname(filename))
    open(filename, "w") do f
        write(f, data)
    end
    nothing
end

"""
Write to an in memory zipfile, that gets saved to disk on close.
This writer will overwrite any existing file at `path`
"""
struct ZarrZipWriter{IO_TYPE<:IO} <: AbstractWriter
    zipfile::ZipWriter{IO_TYPE}
    function ZarrZipWriter(io)
        new{typeof(io)}(ZipWriter(io))
    end
end

function write_key(d::ZarrZipWriter, key::AbstractString, data)::Nothing
    zip_writefile(d.zipfile, key, data)
    nothing
end

function closewriter(d::ZarrZipWriter)
    close(d.zipfile)
    nothing
end