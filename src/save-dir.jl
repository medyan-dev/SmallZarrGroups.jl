# Save a ZGroup to a directory using zarr-python.

using PythonCall

const zarr = PythonCall.pynew() # initially NULL
function __init__()
  PythonCall.pycopy!(zarr, pyimport("zarr"))
end

"""
Note this will delete pre existing data at dirpath
"""
function save_dir(dirpath::AbstractString, z::ZGroup)
    # TODO add something to prevent loops
    save_zgroup(dirpath, "/", z::ZGroup)
end


# subpath should always end in a "/"
function save_zgroup(dirpath, subpath::String, z::ZGroup)
    zarr.open_group(
        store=zarr.DirectoryStore(dirpath),
        path=subpath, # Group path within store.
        mode="w", # Persistence mode: 
            # ‘r’ means read only (must exist); 
            # ‘r+’ means read/write (must exist); 
            # ‘a’ means read/write (create if doesn’t exist); 
            # ‘w’ means create (overwrite if exists); 
            # ‘w-’ means create (fail if exists).
    )
    save_attrs(dirpath, subpath, z)
    for (k,v) in pairs(children(z))
        @argcheck !isempty(k)
        @argcheck k != "."
        @argcheck k != ".."
        child_subpath = String(subpath*k*"/")
        if v isa ZGroup
            save_zgroup(dirpath, child_subpath, v)
        elseif v isa ZArray
            save_zarray(dirpath, child_subpath, v)
        else
            error("unreachable")
        end
    end
end

function save_zarray(dirpath, subpath::String, z::ZArray)
    zarr.array(getarray(z);
        chunks=z.chunks,
        compressor="default", # TODO use compressor saved in z
        order="F",
        store=zarr.DirectoryStore(dirpath),
        overwrite=true,
        path=subpath,
        filters=nothing, # TODO use filters saved in z
    )
    save_attrs(dirpath, subpath, z)
end


"""
save attributes using JSON3
"""
function save_attrs(dirpath, subpath, z::Union{ZArray,ZGroup})
    if isempty(attrs(z))
        return
    end
    attr_path = joinpath([dirpath; split(subpath,"/")])
    mkpath(attr_path)
    open(joinpath(attr_path,".zattrs"), "w") do io
        JSON3.pretty(io, attrs(z); allow_inf=true)
    end
end

function load_dir(dirpath::AbstractString)::ZGroup
    @argcheck isdir(dirpath)
    load_zgroup(dirpath, "/")
end


function load_zgroup(dirpath, subpath::String)::ZGroup
    out = ZGroup(;attrs=load_attrs(dirpath, subpath))
    zg = zarr.open_group(
        store=zarr.DirectoryStore(dirpath),
        path=subpath, # Group path within store.
        mode="r", # Persistence mode: 
            # ‘r’ means read only (must exist); 
            # ‘r+’ means read/write (must exist); 
            # ‘a’ means read/write (create if doesn’t exist); 
            # ‘w’ means create (overwrite if exists); 
            # ‘w-’ means create (fail if exists).
    )
    subgroup_keys::Vector{String} = sort(string.(collect(zg.group_keys())))
    for k in subgroup_keys
        child_subpath = String(subpath*k*"/")
        out[k] = load_zgroup(dirpath, child_subpath)
    end
    # @show subpath
    subarray_keys::Vector{String} = sort(string.(collect(zg.array_keys())))
    for k in subarray_keys
        child_subpath = String(subpath*k*"/")
        out[k] = load_zarray(dirpath, child_subpath)
    end
    out
end

function load_zarray(dirpath, subpath::String)::ZArray
    za = zarr.open_array(
        store=zarr.DirectoryStore(dirpath),
        path=subpath,
        mode="r",
    )
    data, chunks = try
        Array(PyArray(za.get_basic_selection())), Tuple(pyconvert(Vector{Int},za.chunks))
    catch e
        if endswith(e.msg, "cannot convert this Python 'ndarray' to a 'PyArray'")
            Array(PyArray(za.get_basic_selection().tobytes())), 0
        else
            rethrow()
        end
    end
    if !(eltype(data) <: ZDataTypes)
        data = collect(vec(reinterpret(UInt8,data)))
        chunks = 0
    end
    ZArray(data;
        chunks,
        attrs=load_attrs(dirpath, subpath),
        compressor="default", # TODO add compressor and filter loading
    )
end

function load_attrs(dirpath, subpath)::OrderedDict{String,Any}
    attr_file = joinpath([dirpath; split(subpath,"/"); ".zattrs"])
    if !isfile(attr_file)
        OrderedDict{String,Any}()
    else
        jsonobj = JSON3.read(read(attr_file,String); allow_inf=true)
        OrderedDict{String,Any}((string(k)=>v for (k,v) in pairs(jsonobj)))
    end
end
