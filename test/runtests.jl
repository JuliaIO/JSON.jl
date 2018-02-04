using JSON
using Compat.Test
using Compat
using Compat.Dates
using OffsetArrays

import DataStructures

include("json-samples.jl")

include("parser.jl")

@testset "Issue #152" begin
    @test json([Int64[] Int64[]]) == "[[],[]]"
    @test json([Int64[] Int64[]]') == "[]"
end

@testset "Serializer" begin
    @testset "Standard Serializer" begin ; include("standard-serializer.jl")  ; end
    @testset "Lowering"            begin ; include("lowering.jl")             ; end
    @testset "Custom Serializer"   begin ; include("serializer.jl")           ; end
end

@testset "Integration" begin
    # ::Nothing values should be encoded as null
    testDict = Dict("a" => nothing)
    nothingJson = JSON.json(testDict)
    for Typ in (String, IOBuffer)
        nothingDict = JSON.parse(Typ(nothingJson))
        @test testDict == nothingDict
    end

    for Typ in (String, IOBuffer)
        @testset "indentation: $Typ" begin
            # check indented json has same final value as non indented
            fb = JSON.parse(Typ(facebook))
            fbjson1 = json(fb, 2)
            fbjson2 = json(fb)
            @test JSON.parse(Typ(fbjson1)) == JSON.parse(Typ(fbjson2))

            ev = JSON.parse(Typ(svg_tviewer_menu))
            ejson1 = json(ev, 2)
            ejson2 = json(ev)
            @test JSON.parse(Typ(ejson1)) == JSON.parse(Typ(ejson2))
        end
    end

    @testset "async"        begin ; include("async.jl")        ; end
    @testset "JSON Checker" begin ; include("json-checker.jl") ; end
end

# Check that printing to the default STDOUT doesn't fail
JSON.print(["JSON.jl tests pass!"], 1)
