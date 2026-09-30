using SmallZarrGroups
using SmallZarrGroups: CompressorOptions
using SmallZarrGroups: COMPRESSOR_NONE, COMPRESSOR_ZLIB, COMPRESSOR_GZIP, COMPRESSOR_BLOSC_LZ4, COMPRESSOR_ZSTD
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
    # name => (create_dataset keywords, expected compressor options)
    cases = Any[
        "default" => ((;), CompressorOptions(COMPRESSOR_BLOSC_LZ4, 5, 8, false, false)),
        "order F" => ((; order="F"), CompressorOptions(COMPRESSOR_BLOSC_LZ4, 5, 8, true, false)),
        "shuffle" => ((; filters=pylist([shuffle8]), compressor=nothing), CompressorOptions(COMPRESSOR_NONE, 0, 8, false, true)),
        "shuffle zlib" => ((; filters=pylist([shuffle8]), compressor=numcodecs.Zlib(level=3)), CompressorOptions(COMPRESSOR_ZLIB, 3, 8, false, true)),
        "zlib" => ((; compressor=numcodecs.Zlib(level=3)), CompressorOptions(COMPRESSOR_ZLIB, 3, 8, false, false)),
        "gzip" => ((; compressor=numcodecs.GZip(level=4)), CompressorOptions(COMPRESSOR_GZIP, 4, 8, false, false)),
        "zstd" => ((; compressor=numcodecs.Zstd(level=-100)), CompressorOptions(COMPRESSOR_ZSTD, -100, 8, false, false)),
        "zstd checksum" => ((; compressor=numcodecs.Zstd(level=3, checksum=true)), CompressorOptions(COMPRESSOR_ZSTD, 3, 8, false, false)),
        "shuffle zstd" => ((; filters=pylist([shuffle8]), compressor=numcodecs.Zstd(level=1)), CompressorOptions(COMPRESSOR_ZSTD, 1, 8, false, true)),
        "slash separator" => ((; dimension_separator="/"), CompressorOptions(COMPRESSOR_BLOSC_LZ4, 5, 8, false, false)),
    ]
    for cname in ("blosclz", "lz4", "lz4hc", "zlib", "zstd"), shuffle in (0, 1, 2)
        push!(cases, "blosc $(cname) $(shuffle)" => (
            (; compressor=numcodecs.Blosc(cname=cname, clevel=7, shuffle=shuffle)),
            CompressorOptions(COMPRESSOR_BLOSC_LZ4, 7, 8, false, false),
        ))
    end
    data = rand(10, 7)
    mktempdir() do path
        py_group = zarr.open_group(store=path, mode="w")
        for (name, (kwargs, _)) in cases
            py_group.create_dataset(name; data=to_numpy(data), chunks=(3, 4), kwargs...)
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
        ("f2", 1.5, Float16(1.5)),
        ("i2", -3, Int16(-3)),
        ("u8", typemax(UInt64), typemax(UInt64)),
        ("b1", true, true),
        # Complex fill values are saved as a list of the real and imaginary parts.
        ("c8", 0, ComplexF32(0)),
        ("c8", complex(-2.5, 0.25), ComplexF32(-2.5, 0.25)),
        ("c16", complex(1.5, -3.0), ComplexF64(1.5, -3.0)),
    ]
    for (dtype, fill_value, expected) in cases
        mktempdir() do path
            py_group = zarr.open_group(store=path, mode="w")
            py_array = py_group.create_dataset("a"; shape=(7, 10), chunks=(3, 4), dtype, fill_value)
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

@testset "unsupported zarr-python arrays error" begin
    cases = [
        (; filters=pylist([numcodecs.Delta(dtype="<f8")])) => "delta filter not supported",
        (; filters=pylist([numcodecs.Shuffle(elementsize=4)])) => "elementsize",
        (; filters=pylist([numcodecs.Shuffle(elementsize=8), numcodecs.Shuffle(elementsize=8)])) => "single shuffle filter",
        (; compressor=numcodecs.BZ2()) => "bz2 compressor not supported yet",
    ]
    for (kwargs, message) in cases
        mktempdir() do path
            py_group = zarr.open_group(store=path, mode="w")
            py_group.create_dataset("a"; data=np.zeros((3, 4)), kwargs...)
            @test_throws message SmallZarrGroups.load_dir(path)
        end
    end
end
