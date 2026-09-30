"""
    ZGroup()
Represents a tree with `ZArray` leaves.

Can have JSON serializable attributes attached to any node or leaf.
"""
Base.@kwdef mutable struct ZGroup
    children::SortedDict{String,Union{ZArray,ZGroup}} = SortedDict{String,Union{ZArray,ZGroup}}()
    attrs::OrderedDict{String,Any} = OrderedDict{String,Any}()
end

"""
Return the mutable SortedDict of attributes.
"""
attrs(d::ZGroup) = d.attrs

AbstractTrees.children(d::ZGroup) = d.children

AbstractTrees.childrentype(::Type{ZGroup}) = SortedDict{String,Union{ZArray,ZGroup}}

AbstractTrees.childtype(::Type{ZGroup}) = Union{ZArray,ZGroup}

# Names of zarr metadata keys, which can't be used as child names.
# "zarr.json" is the zarr v3 metadata key, so a child with that name could make the store look like zarr v3.
const RESERVED_NAMES = (".zgroup", ".zarray", ".zattrs", "zarr.json")

function _normalize_path(pathstr::AbstractString)::Vector{SubString{String}}
    _check_path(split(String(pathstr), ('/', '\\'); keepempty=false))
end

"""
Throw an `ArgumentError` if `path`, a vector of non empty path parts, isn't a valid child path.
Return `path`.
"""
function _check_path(path::AbstractVector{<:AbstractString})
    @argcheck !isempty(path)
    @argcheck !any(==("."), path)
    @argcheck !any(==(".."), path)
    @argcheck !any(in(RESERVED_NAMES), path)
    path
end

function Base.getindex(d::ZGroup, pathstr::AbstractString)
    path = _normalize_path(pathstr)
    gr::ZGroup = d
    for part in @view(path[begin:end-1])
        child = get(gr.children, part, nothing)
        # The path doesn't exist if it goes through a missing child or a `ZArray`.
        child isa ZGroup || throw(KeyError(pathstr))
        gr = child
    end
    get(() -> throw(KeyError(pathstr)), gr.children, path[end])
end

"""
Make all groups in path if they don't already exist.
Return the last group.
Throw an `ArgumentError` if a `ZArray` is in the way.
"""
function makegroups(d::ZGroup, path::AbstractVector{<:AbstractString})
    gr::ZGroup = d
    for (i, part) in enumerate(path)
        #create path if it doesn't exist
        # A closure is used instead of `ZGroup` because `get!` doesn't specialize on a `Type` argument.
        child = get!(() -> ZGroup(), gr.children, part)
        if !(child isa ZGroup)
            throw(ArgumentError("cannot make group $(repr(join(path[begin:i], '/'))), a ZArray is already there"))
        end
        gr = child
    end
    gr
end

function Base.setindex!(d::ZGroup, x::Union{ZGroup,ZArray}, pathstr::AbstractString)
    path = _normalize_path(pathstr)
    lastgroup = makegroups(d, @view(path[begin:end-1]))
    setindex!(lastgroup.children, x, path[end])
    d
end

function Base.setindex!(d::ZGroup, x::AbstractArray, pathstr::AbstractString)
    setindex!(d, ZArray(collect(x)), pathstr)
end

Base.keys(d::ZGroup) = keys(children(d))

function Base.haskey(d::ZGroup, pathstr::AbstractString)
    path = _normalize_path(pathstr)
    gr::ZGroup = d
    pathexists = true
    for i in 1:length(path)-1
        part = String(path[i])
        if haskey(gr.children, part)
            child = gr.children[part]
            if child isa ZGroup
                gr = child
            else
                pathexists = false
                break
            end
        else
            pathexists = false
            break
        end
    end
    pathexists && haskey(gr.children, path[end])
end

function Base.get!(f, d::ZGroup, pathstr::AbstractString)
    if haskey(d, pathstr)
        d[pathstr]
    else
        d[pathstr] = f()
    end
end

Base.values(d::ZGroup) = values(children(d))

Base.pairs(d::ZGroup) = pairs(children(d))


function Base.delete!(d::ZGroup, pathstr::AbstractString)
    if haskey(d, pathstr)
        path = _normalize_path(pathstr)
        lastgroup::ZGroup = foldl((x,y)->getindex(x.children, y), @view(path[begin:end-1]); init=d)
        delete!(lastgroup.children, path[end])
    end
    d
end

"""
Print the children of `zg`.

`ancestors` holds the groups currently being printed, to detect a group that contains itself.
"""
function _print_group(io::IO, zg::ZGroup, prefix::String, ancestors::Vector{ZGroup})
    push!(ancestors, zg)
    num_childern = length(pairs(zg))
    for (i, (k, child)) in enumerate(pairs(zg))
        println(io)
        last_child = i == num_childern
        print(io, prefix)
        if last_child
            print(io, "└─ ")
        else
            print(io, "├─ ")
        end
        if child isa ZGroup
            print(io, "📂 ", k)
            ancestor_idx = findfirst(a -> a === child, ancestors)
            if !isnothing(ancestor_idx)
                # Like `Base`, print a circular reference instead of recursing forever.
                print(io, " #= circular reference @-", length(ancestors) - ancestor_idx + 1, " =#")
                continue
            end
        elseif child isa ZArray
            print(io, "🔢 ", k, ": ")
            join(io, size(parent(child)),"×")
            print(io, " ", eltype(parent(child)), " ")
        end
        for (k, v) in attrs(child)
            print(io, " 🏷️ $k => $(repr(v)),")
        end
        if child isa ZGroup
            if last_child
                child_prefix = prefix * "   "
            else
                child_prefix = prefix * "|  "
            end
            _print_group(io, child, child_prefix, ancestors)
        end
    end
    pop!(ancestors)
    nothing
end

function Base.show(io::IO, ::MIME"text/plain", zg::ZGroup)
    print(io, "📂")
    for (k, v) in attrs(zg)
        print(io, " 🏷️ $k => $(repr(v)),")
    end
    _print_group(io, zg, "", ZGroup[])
end
