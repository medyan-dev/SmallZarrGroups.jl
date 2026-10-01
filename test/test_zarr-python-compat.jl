using SmallZarrGroups
using SmallZarrGroups: CompressorOptions
using SmallZarrGroups: COMPRESSOR_NONE, COMPRESSOR_ZSTD
using PythonCall
using Test

zarr = pyimport("zarr")
numcodecs = pyimport("numcodecs")
np = pyimport("numpy")

"""
Return the data of a zarr-python array, with dimensions reversed to match Julia.
"""
function py_data(py_array)
    a = Array(PyArray(py_array.get_basic_selection()))
    permutedims(a, ndims(a):-1:1)
end

"""
Return `data` as a numpy array, with dimensions reversed to match zarr-python.
"""
to_numpy(data::Array) = np.asarray(data).T

@testset "SmallZarrGroups reads what zarr-python writes" begin
    shuffle8 = numcodecs.Shuffle(elementsize=8)
    zstd = numcodecs.Zstd(level=1)
    # name => (create_array keywords, expected compressor options)
    cases = Any[
        "uncompressed" => ((; compressors=nothing), CompressorOptions(COMPRESSOR_NONE, 0, 8, false, false)),
        "order F" => ((; order="F", compressors=zstd), CompressorOptions(COMPRESSOR_ZSTD, 1, 8, true, false)),
        "shuffle" => ((; filters=pylist([shuffle8]), compressors=nothing), CompressorOptions(COMPRESSOR_NONE, 0, 8, false, true)),
        "zstd" => ((; compressors=numcodecs.Zstd(level=-100)), CompressorOptions(COMPRESSOR_ZSTD, -100, 8, false, false)),
        "zstd default level" => ((; compressors=numcodecs.Zstd()), CompressorOptions(COMPRESSOR_ZSTD, 0, 8, false, false)),
        "zstd checksum" => ((; compressors=numcodecs.Zstd(level=3, checksum=true)), CompressorOptions(COMPRESSOR_ZSTD, 3, 8, false, false)),
        "shuffle zstd" => ((; filters=pylist([shuffle8]), compressors=zstd), CompressorOptions(COMPRESSOR_ZSTD, 1, 8, false, true)),
        "slash separator" => ((; chunk_key_encoding=pydict(name="v2", separator="/"), compressors=zstd), CompressorOptions(COMPRESSOR_ZSTD, 1, 8, false, false)),
    ]
    data = rand(10, 7)
    mktempdir() do path
        py_group = zarr.open_group(store=path, mode="w", zarr_format=2)
        for (name, (kwargs, _)) in cases
            py_group.create_array(name; data=to_numpy(data), chunks=(3, 4), kwargs...)
        end
        g = SmallZarrGroups.load_dir(path)
        for (name, (_, expected)) in cases
            @test parent(g[name]) == data
            @test g[name].chunks == (4, 3)
            @test g[name].compressor == expected
        end
    end
end

@testset "missing chunks are the fill value" begin
    # (dtype, zarr-python fill value, expected Julia fill value)
    cases = [
        ("f8", 7.5, 7.5),
        ("f8", NaN, NaN),
        ("f4", -Inf, -Inf32),
        # `isequal` checks the sign of zero.
        ("f8", -0.0, -0.0),
        ("f4", -0.0, -0.0f0),
        ("f2", 1.5, Float16(1.5)),
        ("i2", -3, Int16(-3)),
        ("u8", typemax(UInt64), typemax(UInt64)),
        ("b1", true, true),
        # Complex fill values are saved as a list of the real and imaginary parts.
        ("c8", 0, ComplexF32(0)),
        ("c8", complex(-2.5, 0.25), ComplexF32(-2.5, 0.25)),
        ("c16", complex(1.5, -3.0), ComplexF64(1.5, -3.0)),
        ("c16", complex(-0.0, -0.0), ComplexF64(-0.0, -0.0)),
    ]
    for (dtype, fill_value, expected) in cases
        mktempdir() do path
            py_group = zarr.open_group(store=path, mode="w", zarr_format=2)
            py_array = py_group.create_array("a"; shape=(7, 10), chunks=(3, 4), dtype, fill_value, compressors=numcodecs.Zstd())
            py_array[pyslice(0, 3), pyslice(0, 4)] = 1
            expected_data = fill(expected, 10, 7)
            expected_data[1:4, 1:3] .= 1
            @test isequal(py_data(py_array), expected_data)
            z = SmallZarrGroups.load_dir(path)["a"]
            @test eltype(z) === typeof(expected)
            @test isequal(parent(z), expected_data)
        end
    end
end

@testset "Bool bytes are normalized like numpy" begin
    mktempdir() do path
        py_group = zarr.open_group(store=path, mode="w", zarr_format=2)
        # zarr-python saves the raw bytes of a numpy bool view of every byte value.
        py_bools = np.arange(256; dtype=np.uint8).view(np.bool_)
        py_array = py_group.create_array("a"; data=py_bools, chunks=(100,), compressors=numcodecs.Zstd())
        # numpy treats any nonzero byte as true, and converts it to 0x01.
        expected = Vector(PyArray(py_array.get_basic_selection().astype(np.uint8)))
        @test expected == [0x00; fill(0x01, 255)]
        z = SmallZarrGroups.load_dir(path)["a"]
        @test eltype(z) === Bool
        @test reinterpret(UInt8, parent(z)) == expected
    end
end

@testset "unsupported zarr-python arrays error" begin
    cases = [
        (; filters=pylist([numcodecs.Delta(dtype="<f8")]), compressors=nothing) => "delta filter not supported",
        (; filters=pylist([numcodecs.Shuffle(elementsize=4)]), compressors=nothing) => "elementsize",
        (; filters=pylist([numcodecs.Shuffle(elementsize=8), numcodecs.Shuffle(elementsize=8)]), compressors=nothing) => "single shuffle filter",
        (; compressors=numcodecs.BZ2()) => "bz2 compressor not supported yet",
        # zarr-python's default compressor is blosc.
        (;) => "blosc compressor not supported yet",
        (; compressors=numcodecs.Zlib(level=3)) => "zlib compressor not supported yet",
        (; compressors=numcodecs.GZip(level=4)) => "gzip compressor not supported yet",
    ]
    for (kwargs, message) in cases
        mktempdir() do path
            py_group = zarr.open_group(store=path, mode="w", zarr_format=2)
            py_group.create_array("a"; data=np.zeros((3, 4)), kwargs...)
            @test_throws message SmallZarrGroups.load_dir(path)
        end
    end
end
