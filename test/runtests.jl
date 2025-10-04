using JSON, Test, Tar

include(joinpath(dirname(pathof(JSON)), "../test/object.jl"))
include(joinpath(dirname(pathof(JSON)), "../test/lazy.jl"))
include(joinpath(dirname(pathof(JSON)), "../test/parse.jl"))
include(joinpath(dirname(pathof(JSON)), "../test/json.jl"))
include(joinpath(dirname(pathof(JSON)), "../test/arrow.jl"))
include(joinpath(dirname(pathof(JSON)), "../test/ryu.jl"))

function tar_files(tarball::String)
    data = Dict{String, Vector{UInt8}}()
    buf = Vector{UInt8}(undef, Tar.DEFAULT_BUFFER_SIZE)
    io = IOBuffer()
    open(tarball) do tio
        Tar.read_tarball(_ -> true, tio; buf=buf) do header, _
            if header.type == :file
                take!(io) # In case there are multiple entries for the file
                Tar.read_data(tio, io; size=header.size, buf)
                data[header.path] = take!(io)
            end
        end
    end
    data
end

# JSONTestSuite

function parse_testfile(i, file, data)
    # known failures on 14, 32, 33 (all are "i_...", meaning the spec is ambiguous anyway)
      # 14: i_string_UTF-16LE_with_BOM.json, we don't support UTF-16
      # 32: i_string_utf16BE_no_BOM.json, we don't support UTF-16
      # 33: i_string_utf16LE_no_BOM.json, we don't support UTF-16
    if startswith(file, "n_")
        try
            JSON.parse(data)
            @warn "no error thrown while parsing json test file" file=file i=i
            @test !(file isa String)
        catch
            @test file isa String
        end
    elseif startswith(file, "i_")
        try
            JSON.parse(data)
        catch
            @warn "error thrown while parsing json test file" file=file i=i
        end
    else
        try
            JSON.parse(data)
            @test file isa String
        catch
            @warn "error thrown while parsing json test file" file=file i=i
            @test !(file isa String)
            rethrow()
        end
    end
end

println("\nTest cases 70, 85, and 104 are expected to emit warnings next\n")
const jsontestsuite = tar_files(joinpath(dirname(pathof(JSON)), "../test/JSONTestSuite.tar"))
@testset "JSONTestSuite" begin
    for (i, (file, data)) in enumerate(jsontestsuite)
        parse_testfile(i, file, data)
    end
end

# jsonchecker

function parse_testfile2(i, file, data)
    if startswith(file, "fail")
        try
            JSON.parse(data)
            @warn "no error thrown while parsing json test file" file=file i=i
            @test !(file isa String)
        catch
            @test file isa String
        end
    else
        try
            JSON.parse(data)
            @test file isa String
        catch
            @warn "error thrown while parsing json test file" file=file i=i
            @test !(file isa String)
            rethrow()
        end
    end
end

const jsonchecker = tar_files(joinpath(dirname(pathof(JSON)), "../test/jsonchecker.tar"))
@testset "jsonchecker" begin
    for (i, (file, data)) in enumerate(jsonchecker)
        parse_testfile2(i, file, data)
    end
end