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

@testset "fuzz_catch" begin
    x = [
        "688665-N6iC);2mb[)>uBbVU@].&/r7[8bB",
        false,
        Any[Dict{String, Any}("nMJe 9'H9l1z;15`(\"{a62V[N[y:GWb" => 339018, "8<\"7-~fgEzt5edi@-Q" => -0.24880373028918779, "UT)*=)&kQu[,< g;E+.('v=,1_zZUZuV*" => 939542, "=BYKHNx>y" => "UsTIrR[.G!(9a~y V8eX\",3q8Ue^B]lFpbU7x6@8]l5.wr;RN~", "" => false, "JOg*[CX.c4Zd!qG )CQN;RPq3J&Iq]0,!rc+,XWd}'`[ZE:/e[\$Py}<CCS\\Op" => "8+iqM[[x7U9M?\\`?DNm", "QMW<`6S[" => missing, "mf&,q;4=fIsz5&Hf:H!1<Y2?qCSYT|o5qW/}0:vDJ*^FX!*|F\" N=8.1+{#\\ +IH" => 710995), Any[936790, false, nothing, "954676-=\$\"u+bblP;RihZ}ME{0h^C`#F4!2AY[VvYD\$eqK0x-)GOn_o3gc` nf^1_MZuh", "850152-\$:QqPP8-v%{'U^& B0%"], Any[true, false, 0.22466108267242246, 841509, "%?-NI"]],
        nothing
    ]
    @test JSON.json(x, 2) isa String
end
