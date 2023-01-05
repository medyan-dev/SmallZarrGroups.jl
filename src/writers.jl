# Basic version of Zarr storage interface

# Doesn't support deleting, or changing data already written.

using ArgCheck
using ZipFile


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
struct BufferedZipWriter <: AbstractWriter
    zipfile::ZipFile.Writer
    path::String
    iobuffer::IOBuffer
    function BufferedZipWriter(path)
        @argcheck !isdir(path)
        @argcheck !isdirpath(path)
        mkpath(dirname(path))
        iobuffer = IOBuffer()
        zipfile = ZipFile.Writer(iobuffer)
        new(zipfile, abspath(path), iobuffer)
    end
end

function write_key(d::BufferedZipWriter, key::AbstractString, data)::Nothing
    f = ZipFile.addfile(d.zipfile, key);
    write(f, data)
    nothing
end

function closewriter(d::BufferedZipWriter)
    close(d.zipfile)
    open(d.path, "w") do f
        write(f, take!(d.iobuffer))
        close(d.iobuffer)
    end
end