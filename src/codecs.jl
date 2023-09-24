abstract type Codec end

struct BloscCodec <: Codec
    cname::Union{String,Nothing}
    clevel::Union{Int,Nothing}
    shuffle::Union{Int,Nothing}
    blocksize::Int
end

