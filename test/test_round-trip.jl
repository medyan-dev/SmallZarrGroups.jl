using SmallZarrGroups
using SmallZarrGroups: ZArray, level_range, default_level
using SmallZarrGroups: COMPRESSOR_NONE, COMPRESSOR_ZSTD
using PythonCall
using Test

zarr = pyimport("zarr")

const ELEMENT_TYPES = [
    Bool,
    Int8, Int16, Int32, Int64,
    UInt8, UInt16, UInt32, UInt64,
    Float16, Float32, Float64,
    ComplexF16, ComplexF32, ComplexF64,
    NTuple{0,UInt8}, NTuple{3,UInt8}, NTuple{300,UInt8},
]

# numpy has no complex32, and numpy crashes copying non empty arrays with zero size elements.
const NOT_PYTHON_TYPES = (ComplexF16, NTuple{0,UInt8})

# (shape, chunks), including partial edge chunks, zero dimensions, and zero length dimensions.
const SHAPES = [
    ((), ()),
    ((0,), (0,)),
    ((7,), (3,)),
    ((3,), (7,)),
    ((4, 5), (4, 5)),
    ((4, 10), (5, 2)),
    ((10, 7), (4, 3)),
    ((2, 5), (3, 2)),
    ((5, 0, 3), (2, 0, 3)),
    ((3, 4, 5), (2, 3, 2)),
]

function round_trip(g::ZGroup)::ZGroup
    io = IOBuffer()
    SmallZarrGroups.save_zip(io, g)
    SmallZarrGroups.load_zip(take!(io))
end

"""
Test that `gload` has the same tree, attributes, data, chunks, and compressor options as `g`.
"""
function test_equal_tree(gload::ZGroup, g::ZGroup)
    @test isequal(attrs(gload), attrs(g))
    @test collect(keys(gload)) == collect(keys(g))
    for (k, z) in pairs(g)
        haskey(gload, k) || continue
        zload = gload[k]
        @test typeof(zload) == typeof(z)
        typeof(zload) == typeof(z) && test_equal_tree(zload, z)
    end
end
function test_equal_tree(zload::ZArray, z::ZArray)
    @test isequal(attrs(zload), attrs(z))
    @test isequal(parent(zload), parent(z))
    @test zload.chunks == z.chunks
    @test zload.compressor == z.compressor
end

"""
Save `g`, test that zarr-python reads it, then copy it with zarr-python and load the copy.

zarr-python's copy decodes every chunk and encodes it again with the same chunks, order, filters, and compressor.
"""
function python_round_trip(g::ZGroup)::ZGroup
    # zarr-python's ZipStore needs a file path.
    # Files are closed before the other side opens them, for Windows.
    mktemp() do src, src_io
        mktemp() do dst, dst_io
            SmallZarrGroups.save_zip(src_io, g)
            close(src_io)
            close(dst_io)
            src_store = zarr.ZipStore(src, mode="r")
            dst_store = zarr.ZipStore(dst, mode="w")
            try
                py_src = zarr.open_group(store=src_store, mode="r")
                test_python_reads(py_src, g)
                zarr.copy_all(py_src, zarr.group(store=dst_store))
            finally
                src_store.close()
                dst_store.close()
            end
            SmallZarrGroups.load_zip(dst)
        end
    end
end

"""
Test that zarr-python reads the same tree, element types, shapes, chunks, orders, and data as `g`.
"""
function test_python_reads(py_group, g::ZGroup)
    @test sort(pyconvert(Vector{String}, pylist(py_group.keys()))) == collect(keys(g))
    for (k, z) in pairs(g)
        test_python_reads(py_group[k], z)
    end
end
function test_python_reads(py_array, z::ZArray{T}) where {T}
    @test pyconvert(String, py_array.dtype.kind) == numpy_kind(T)
    @test pyconvert(Int, py_array.dtype.itemsize) == sizeof(T)
    @test pyconvert(Tuple, py_array.shape) == reverse(size(z))
    @test pyconvert(Tuple, py_array.chunks) == reverse(z.chunks)
    @test pyconvert(String, py_array.order) == (z.compressor.reverse_dims ? "F" : "C")
    # Because the dimensions are reversed, zarr-python's C order bytes are Julia's column major bytes.
    @test pyconvert(Vector{UInt8}, py_array.get_basic_selection().tobytes()) == julia_bytes(parent(z))
end

numpy_kind(::Type{Bool}) = "b"
numpy_kind(::Type{<:Signed}) = "i"
numpy_kind(::Type{<:Unsigned}) = "u"
numpy_kind(::Type{<:AbstractFloat}) = "f"
numpy_kind(::Type{<:Complex}) = "c"
numpy_kind(::Type{NTuple{N,UInt8}}) where {N} = "V"

function julia_bytes(a::Array)::Vector{UInt8}
    io = IOBuffer()
    write(io, a)
    take!(io)
end

"""
Test that `g` round trips through a zip file, and through zarr-python if `python` is `true`.
"""
function test_round_trip(g::ZGroup; python::Bool=true)
    test_equal_tree(round_trip(g), g)
    python && test_equal_tree(python_round_trip(g), g)
end

@testset "round trip every compressor option" begin
    for compressor in (COMPRESSOR_NONE, COMPRESSOR_ZSTD),
            level in unique([extrema(level_range(compressor))..., default_level(compressor)]),
            reverse_dims in (false, true),
            byteshuffle in (false, true)
        g = ZGroup()
        for (i, (shape, chunks)) in enumerate(SHAPES)
            g["$i"] = ZArray(rand(Float64, shape); chunks, compressor, level, reverse_dims, byteshuffle)
        end
        test_round_trip(g)
    end
end

@testset "round trip every element type" begin
    for reverse_dims in (false, true), byteshuffle in (false, true), T in ELEMENT_TYPES
        g = ZGroup()
        for (i, (shape, chunks)) in enumerate(SHAPES)
            g["$i"] = ZArray(rand(T, shape); chunks, reverse_dims, byteshuffle)
        end
        test_round_trip(g; python=(T ∉ NOT_PYTHON_TYPES))
    end
end

@testset "round trip nested groups and attributes" begin
    g = ZGroup()
    attrs(g)["root"] = "r"
    g["a"] = ZArray(rand(Int16, 3, 4); chunks=(2, 2))
    g["empty"] = ZGroup()
    g["sub/b"] = ZArray(rand(Float32, 5))
    g["sub/empty"] = ZGroup()
    g["sub/deeper/c"] = ZArray(rand(UInt8, 2, 3, 4); compressor=COMPRESSOR_NONE)
    attrs(g["sub"])["n"] = 3
    attrs(g["sub/deeper/c"])["list"] = [1.5, NaN]
    attrs(g["sub/deeper/c"])["nested"] = Dict("x" => "y")
    attrs(g["sub/deeper/c"])["unicode"] = Dict("x" => "🦘")
    test_round_trip(g)
end
