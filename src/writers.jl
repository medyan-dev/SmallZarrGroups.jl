# Basic version of Zarr storage interface

# Doesn't support deleting, or changing data already written.

using ArgCheck


abstract type AbstractWriter end


struct DirectoryWriter <: AbstractWriter
    path::String
end

function DirectoryWriter(dir)
    mkpath(dir)
    DirectoryWriter(abspath(dir))
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