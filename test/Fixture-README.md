# SmallZarrGroup.jl Fixture

This directory contains a number of zip archives 
that should be able to be successfully read.

### How to add new files
Download the fixture with 
```julia
using Pkg.Artifacts
fixture_dir = "fixture"
cp(artifact"fixture", fixture_dir)
```

Add the file to the "fixture" directory, and a description to this file.

Then run
```julia
# This is the url that the artifact will be available from:
url_to_upload_to = "https://github.com/medyan-dev/SmallZarrGroups.jl/releases/download/v0.6.6/fixture.tar.gz"
# This is the path to the Artifacts.toml we will manipulate
artifact_toml = "Artifacts.toml"
fixture_hash = create_artifact() do artifact_dir
    cp(fixture_dir, artifact_dir; force=true)
end
tar_hash = archive_artifact(fixture_hash, "fixture.tar.gz")
bind_artifact!(artifact_toml, "fixture", fixture_hash; force=true,
    download_info = [(url_to_upload_to, tar_hash)]
)
```

Finally, upload the new "fixture.tar.gz" to `url_to_upload_to`