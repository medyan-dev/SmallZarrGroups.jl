Base.@kwdef struct ZGroup
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

function _normalize_path(pathstr::AbstractString)::Vector{SubString{String}}
    path = split(replace(pathstr, '\\'=>'/'), '/'; keepempty=false)
    @argcheck !isempty(path)
    @argcheck !any(==("."), path)
    @argcheck !any(==(".."), path)
    path
end

function Base.getindex(d::ZGroup, pathstr::AbstractString)
    path = _normalize_path(pathstr)
    foldl((x,y)->getindex(x.children, y), path; init=d)
end

"""
Make all groups in path if they don't already exist.
Return the last group.
"""
function makegroups(d::ZGroup, path::Vector{<:AbstractString})
    gr::ZGroup = d
    for part in path
        if !haskey(gr.children, part)
            #create path if it doesn't exist
            gr.children[part] = ZGroup()
        end
        gr = gr.children[part]
    end
    gr
end

function Base.setindex!(d::ZGroup, x::Union{ZGroup,ZArray}, pathstr::AbstractString)
    path = _normalize_path(pathstr)
    lastgroup = makegroups(d, path[begin:end-1])
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
        lastgroup::ZGroup = foldl((x,y)->getindex(x.children, y), path[begin:end-1]; init=d)
        delete!(lastgroup.children, path[end])
    end
    d
end


function Base.show(io::IO, ::MIME"text/plain", d::ZGroup)
    print_tree(io, d; maxdepth=5, printkeys=true) do io, node
        if node isa ZGroup
            print(io, "📂 ")
        elseif node isa ZArray
            print(io, "🔢 ", join(size(getarray(node)),"×"), " ", eltype(getarray(node)), " ")
        end
        for (k, v) in attrs(node)
            print(io, "🏷️\"$k\" => $(repr(v)), ")
        end
    end
end
