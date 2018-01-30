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
    @testset "Standard Serializer" begin
        include("standard-serializer.jl")
    end

    @testset "Lowering" begin
        include("lowering.jl")
    end

    @testset "Custom Serializer" begin
        include("serializer.jl")
    end
end

@testset "Integration" begin
    # ::Nothing values should be encoded as null
    testDict = Dict("a" => nothing)
    nothingJson = JSON.json(testDict)
    nothingDict = JSON.parse(Typ(nothingJson))
    @test testDict == nothingDict

    @testset "async" begin
        include("async.jl")
    end

    @testset "indentation" begin
        include("indentation.jl")
    end

    @testset "JSON Checker" begin
        include("json-checker.jl")
    end
end

@testset "Regression" begin
    @testset "for issue #$i" for i in [21, 26, 57, 109, 152, 163]
        include("regression/issue$(lpad(i, 3, '0')).jl")
    end
end
end

# Check that printing to the default STDOUT doesn't fail
JSON.print(["JSON.jl tests pass!"], 1)
