using SmallZarrGroups: contiguous_prefix, unsafe_strided_copy!
using Test

"""
Reference strided copy, one byte at a time.
"""
function reference_copy!(dst, dst_offset, dst_strides, src, src_offset, src_strides, sizes)
    for I in CartesianIndices(sizes)
        i = Tuple(I) .- 1
        dst[1 + dst_offset + sum(i .* dst_strides; init=0)] = src[1 + src_offset + sum(i .* src_strides; init=0)]
    end
    dst
end

"""
Call `unsafe_strided_copy!` on byte offsets into `dst` and `src`.
"""
function offset_copy!(dst::Vector{UInt8}, dst_offset, dst_strides, src::Vector{UInt8}, src_offset, src_strides, sizes)
    dst_c = Base.cconvert(Ptr{UInt8}, dst)
    src_c = Base.cconvert(Ptr{UInt8}, src)
    GC.@preserve dst_c src_c unsafe_strided_copy!(
        Base.unsafe_convert(Ptr{UInt8}, dst_c) + dst_offset, dst_strides,
        Base.unsafe_convert(Ptr{UInt8}, src_c) + src_offset, src_strides,
        sizes,
    )
    dst
end

@testset "contiguous_prefix" begin
    # contiguous on both sides
    @test contiguous_prefix((2, 3, 4), (1, 2, 6), (1, 2, 6)) == (3, 24)
    # the source is part of a larger array
    @test contiguous_prefix((2, 3, 4), (1, 2, 6), (1, 10, 100)) == (1, 2)
    @test contiguous_prefix((10, 3), (1, 10), (1, 10)) == (2, 30)
    @test contiguous_prefix((10, 3, 2), (1, 10, 30), (1, 10, 100)) == (2, 30)
    # size 1 dimensions after the run are not part of it
    @test contiguous_prefix((4, 5, 1), (1, 4, 20), (1, 10, 50)) == (1, 4)
    # transposed
    @test contiguous_prefix((3, 4), (4, 1), (1, 3)) == (0, 1)
    # not stride 1
    @test contiguous_prefix((5,), (2,), (2,)) == (0, 1)
    # size 1 dimensions are skipped
    @test contiguous_prefix((1, 5, 1, 3), (1, 1, 5, 5), (7, 1, 9, 5)) == (4, 15)
    @test contiguous_prefix((1, 1), (1, 1), (1, 1)) == (2, 1)
    @test contiguous_prefix((), (), ()) == (0, 1)
end

@testset "unsafe_strided_copy!" begin
    src = rand(UInt8, 1000)
    cases = [
        # (sizes, dst_offset, dst_strides, src_offset, src_strides)
        ((), 0, (), 6, ()),
        ((5,), 0, (1,), 2, (1,)),
        ((5,), 1, (3,), 2, (2,)),
        ((4, 5), 0, (1, 4), 11, (1, 10)),
        ((4, 5), 0, (5, 1), 11, (1, 10)),
        ((10, 3), 0, (1, 10), 0, (1, 10)),
        ((2, 3, 4), 0, (12, 4, 1), 4, (1, 10, 100)),
        ((1, 3, 1), 0, (1, 1, 3), 4, (1, 10, 100)),
        ((4, 3, 2), 0, (1, 4, 12), 2, (1, 4, 50)),
        ((1, 4, 1, 3), 0, (9, 1, 99, 4), 1, (5, 1, 7, 4)),
        # the first dimension is the bytes of each element
        ((8, 3, 4), 0, (1, 8, 24), 16, (1, 32, 8)),
        ((2, 5, 4), 0, (1, 2, 10), 0, (1, 2, 20)),
        # copying nothing
        ((0, 3), 0, (1, 1), 0, (1, 1)),
        ((3, 0), 0, (1, 3), 0, (1, 3)),
    ]
    for (sizes, dst_offset, dst_strides, src_offset, src_strides) in cases
        expected = reference_copy!(zeros(UInt8, 100), dst_offset, dst_strides, src, src_offset, src_strides, sizes)
        @test offset_copy!(zeros(UInt8, 100), dst_offset, dst_strides, src, src_offset, src_strides, sizes) == expected
    end
    # an empty block does not use its pointers
    @test unsafe_strided_copy!(Ptr{UInt8}(0), (1, 1), Ptr{UInt8}(0), (1, 1), (0, 1000)) === nothing
end
