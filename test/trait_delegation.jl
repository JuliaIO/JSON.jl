module TraitDelegationTests
using JSON, StructUtils, Test

struct CustomStyle <: JSON.JSONStyle end
struct OwnedDict
    values::Dict{String,Int}
end
OwnedDict() = OwnedDict(Dict{String,Int}())
Base.keytype(::OwnedDict) = String
Base.valtype(::OwnedDict) = Int
StructUtils.dictlike(::StructUtils.StructStyle, ::Type{OwnedDict}) = true
StructUtils.addkeyval!(x::OwnedDict, k, v) = (x.values[k] = v)

struct OwnedArray
    values::Vector{Int}
end
OwnedArray() = OwnedArray(Int[])
Base.eltype(::Type{OwnedArray}) = Int
Base.ndims(::Type{OwnedArray}) = 1
StructUtils.arraylike(::StructUtils.StructStyle, ::Type{OwnedArray}) = true
StructUtils.initialize(::StructUtils.StructStyle, ::Type{OwnedArray}, source) = OwnedArray()
Base.push!(x::OwnedArray, v) = push!(x.values, v)

struct CustomDict
    values::Dict{String,Int}
end
CustomDict() = CustomDict(Dict{String,Int}())
Base.keytype(::CustomDict) = String
Base.valtype(::CustomDict) = Int
StructUtils.dictlike(::StructUtils.StructStyle, ::Type{CustomDict}) = false
StructUtils.dictlike(::CustomStyle, ::Type{CustomDict}) = true
StructUtils.addkeyval!(x::CustomDict, k, v) = (x.values[k] = v)

struct Nested
    dict::OwnedDict
    array::OwnedArray
    optional::Union{Nothing,OwnedDict}
    shape::Union{OwnedDict,OwnedArray}
end

@testset "Classification delegates without replacing parsing context" begin
    for style in (StructUtils.DefaultStyle(), CustomStyle())
        @test JSON.parse("{\"a\":1}", OwnedDict; style).values == Dict("a" => 1)
        @test JSON.parse("[1,2]", OwnedArray; style).values == [1,2]
        for (text, T, expected) in (("{\"a\":1}", OwnedDict, Dict("a"=>1)), ("[1,2]", OwnedArray, [1,2]))
            x = T()
            JSON.parse!(text, x; style)
            @test x.values == expected
        end
        @test only(JSON.parse("[{\"a\":1}]", Vector{OwnedDict}; style)).values == Dict("a"=>1)
        @test JSON.parse("{\"a\":1}", Union{Nothing,OwnedDict}; style).values == Dict("a"=>1)
        @test JSON.parse("null", Union{Nothing,OwnedDict}; style) === nothing
        for shape in ("{\"a\":1}", "[1,2]")
            text = "{\"dict\":{\"a\":1},\"array\":[1,2],\"optional\":null,\"shape\":" * shape * "}"
            x = JSON.parse(text, Nested; style)
            @test x.dict.values == Dict("a"=>1)
            @test x.array.values == [1,2]
            @test x.optional === nothing
            @test x.shape.values == (shape[1] == '{' ? Dict("a"=>1) : [1,2])
        end
        @test_throws ArgumentError JSON.parse("{\"extra\":1}", Nested; style, unknown_fields=:error)
        @test JSON.parse("{\"a\":[1]}", Any; style, dicttype=Dict) == Dict("a"=>[1])
    end
    @test isequal(JSON.parse("{\"a\":[null]}"; dicttype=Dict, null=missing), Dict("a"=>[missing]))
    # A custom-style override must beat a generic StructStyle method for the same type.
    @test JSON.parse("{\"a\":1}", CustomDict; style=CustomStyle()).values == Dict("a"=>1)
    x = CustomDict()
    JSON.parse!("{\"a\":1}", x; style=CustomStyle())
    @test x.values == Dict("a"=>1)
end
end
