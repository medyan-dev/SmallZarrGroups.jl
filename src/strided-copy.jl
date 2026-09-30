# Copying a strided block of bytes between buffers.

"""
    contiguous_prefix(sizes, dst_strides, src_strides)

Return the number of leading dimensions `M` that form a single run
with stride 1 in both `dst` and `src`, and the length `n` of that run.
"""
function contiguous_prefix(sizes::NTuple{N,Int}, dst_strides::NTuple{N,Int}, src_strides::NTuple{N,Int}) where {N}
    M, n = 0, 1
    for d in 1:N
        if sizes[d] != 1
            (dst_strides[d] == n && src_strides[d] == n) || break
            n *= sizes[d]
        end
        M = d
    end
    M, n
end

"""
    unsafe_strided_copy!(dst, dst_strides, src, src_strides, sizes)

Copy a block of `sizes` bytes from `src` to `dst` without bounds checks.
The byte at zero based position `i` in the block is at
`ptr + sum(i .* strides)` for each pointer.
The bytes read and written must not overlap.
"""
function unsafe_strided_copy!(
        dst::Ptr{UInt8}, dst_strides::NTuple{N,Int},
        src::Ptr{UInt8}, src_strides::NTuple{N,Int},
        sizes::NTuple{N,Int},
    ) where {N}
    # An empty block copies nothing, so its pointers may be invalid.
    any(iszero, sizes) && return nothing
    M, n = contiguous_prefix(sizes, dst_strides, src_strides)
    # Loop over the dimensions after the contiguous run.
    for I in CartesianIndices(ntuple(d -> d ≤ M ? 1 : sizes[d], Val(N)))
        i = Tuple(I) .- 1
        Libc.memcpy(dst + sum(i .* dst_strides; init=0), src + sum(i .* src_strides; init=0), n)
    end
    nothing
end
