module StyleFastpathTests
using JSON, StructUtils, Test

struct CustomStyle <: JSON.JSONStyle end
JSON.lower(::CustomStyle, x::String) = uppercase(x)
JSON.lower(::CustomStyle, ::Missing) = JSON.Omit()
JSON.lower(::CustomStyle, ::Nothing) = "NULL"
JSON.lift(::CustomStyle, ::Type{String}, x::String) = uppercase(x)
JSON.lift(::CustomStyle, ::Type{Number}, x::Number) = 2x
StructUtils.liftkey(::JSON.JSONReadStyle{O,N,CustomStyle}, ::Type{String}, x::String) where {O,N} = uppercase(x)

struct BareStyle <: StructUtils.StructStyle end
StructUtils.lower(::BareStyle, x::String) = uppercase(x)

struct KeyStyle <: JSON.JSONStyle
    seen::Vector{Int}
end
function StructUtils.lowerkey(st::KeyStyle, x::Int)
    push!(st.seen, x)
    return "key$x"
end

@testset "Every index is lowered; numeric object keys stay quoted and sorted" begin
    for x in ([10, 20], Any[10, 20], (10, 20), (v for v in [10, 20]),
              Union{Int,String}[10, "a"], Vector{Any}(undef, 2), Core.svec(10, 20))
        st = KeyStyle(Int[])
        @test JSON.json(x; style=st) == JSON.json(x)
        @test st.seen == [1, 2]
    end
    st = KeyStyle(Int[])
    @test JSON.json(Set([10]); style=st) == "[10]"
    @test st.seen == [1]
    for x in (Dict(2 => 20, 10 => 100), Dict{Int,Any}(2 => 20, 10 => 100))
        @test JSON.json(x) == "{\"10\":100,\"2\":20}"
        @test JSON.json(x; style=KeyStyle(Int[])) == "{\"key10\":100,\"key2\":20}"
        for sort_keys in (true, false)
            @test JSON.parse(JSON.json(x; sort_keys), typeof(x)) == x
        end
    end
    for k in (true, Int32(2), big(2), 1.5, big"1.5", 1//2, Inf, NaN)
        @test JSON.json(Dict(k => 1)) == "{" * JSON.json(string(k)) * ":1}"
        @test JSON.json([k => 1]) == "{" * JSON.json(string(k)) * ":1}"
    end
    # Mixed numeric/string keys must still sort by their serialized spelling.
    @test JSON.json(Dict{Any,Any}(2 => 1, "10" => 2, :a => 3)) == "{\"10\":2,\"2\":1,\"a\":3}"
    substring = SubString("_key_", 2, 4)
    @test JSON.checkkey(substring) === substring
    @test JSON.json(Dict(substring => 1)) == "{\"key\":1}"
end

struct ValueStyle <: JSON.JSONStyle end
for T in (Nothing, Missing, Bool, Int64, Float64, BigInt, BigFloat)
    @eval JSON.lower(::ValueStyle, x::$T) = string(typeof(x))
end

struct ContainerStyle <: JSON.JSONStyle end
JSON.lower(::ContainerStyle, x::Vector{Any}) = (length=length(x),)
JSON.lower(::ContainerStyle, x::Dict{String,Any}) = (length=length(x),)
JSON.lower(::ContainerStyle, x::JSON.Object{String,Any}) = (length=length(x),)
StructUtils.initialize(::JSON.JSONReadStyle{O,N,ContainerStyle}, ::Type{Vector{Any}}, source) where {O,N} = Any["prefix"]

@testset "Fast paths preserve custom styles" begin
    for sort_keys in (true, false, nothing)
        @test JSON.json(Dict{String,Any}("k" => "v"); style=BareStyle(), sort_keys, omit_null=false, omit_empty=false) == "{\"k\":\"V\"}"
    end
    for value in (nothing, missing, true, Int64(1), 1.5, big(1), big"1.5")
        lowered = JSON.lower(ValueStyle(), value)
        @test JSON.json(Any[value]; style=ValueStyle()) == JSON.json([lowered])
        @test JSON.json(Dict{String,Any}("k" => value); style=ValueStyle()) == JSON.json(Dict("k" => lowered))
    end
    for x in (["secret"], Any["secret"])
        @test JSON.json(x; style=CustomStyle()) == "[\"SECRET\"]"
    end
    for x in (Dict("k" => "secret"), Dict{String,Any}("k" => "secret"),
              JSON.Object{String,Any}("k" => "secret"), Pair{String,Any}["k" => "secret"])
        for sort_keys in (true, false, nothing)
            @test JSON.json(x; style=CustomStyle(), sort_keys) == "{\"k\":\"SECRET\"}"
        end
    end
    @test JSON.json(Any[missing, nothing]; style=CustomStyle()) == "[\"NULL\"]"
    @test JSON.json(Vector{Any}(undef, 1); style=CustomStyle()) == "[\"NULL\"]"
    for x in (Any[1, 2], Dict{String,Any}("a" => 1), JSON.Object{String,Any}("a" => 1))
        @test JSON.json((value=x,); style=ContainerStyle()) == "{\"value\":{\"length\":$(length(x))}}"
        @test JSON.json(Pair{String,Any}["value" => x]; style=ContainerStyle()) == "{\"value\":{\"length\":$(length(x))}}"
        @test JSON.json(Dict{String,Any}("value" => x); style=CustomStyle()) isa String
    end
    for T in (Dict{String,Any}, JSON.Object{String,Any})
        x = JSON.parse("{\"key\":\"secret\",\"n\":2}", T; style=CustomStyle())
        @test x["KEY"] == "SECRET"
        @test x["N"] == 4
        y = T()
        JSON.parse!("{\"key\":\"secret\",\"n\":2}", y; style=CustomStyle())
        @test x == y
    end
    @test JSON.parse("[\"secret\",2]", Vector{Any}; style=CustomStyle()) == Any["SECRET", 4]
    @test JSON.parse("[1]", Vector{Any}; style=ContainerStyle()) == Any["prefix", 1]
end

@testset "Nested Any containers" begin
    # Exercise alternating Object/Dict/array cycles in the call graph, without
    # requiring a different Julia type for every nesting level.
    for depth in (1, 16, 64, 256)
        value = Any[1, "x", true, nothing]
        text = "[1,\"x\",true,null]"
        for i in 1:depth
            if isodd(i)
                value = Any[value]
                text = "[" * text * "]"
            else
                value = i % 4 == 0 ? Dict{String,Any}("a" => value) : JSON.Object{String,Any}("a" => value)
                text = "{\"a\":" * text * "}"
            end
        end
        @test JSON.json(value) == text
        @test JSON.json(JSON.parse(text)) == text
    end
    cycle = Any[]
    push!(cycle, cycle)
    @test JSON.json(cycle) == "[null]"
    dict = Dict{String,Any}()
    dict["self"] = dict
    @test JSON.json(dict) == "{\"self\":null}"
end
@testset "duplicate keys across small-object threshold" begin
    for n in (0, 1, 4, 5, 6, 16, 137), T in (Any, JSON.Object{String,Any}, Dict{String,Any})
        members = ["\"k$i\":$i" for i in 1:n]
        push!(members, "\"k1\":-1")
        result = JSON.parse("{" * join(members, ",") * "}", T)
        @test length(result) == max(n, 1)
        @test result["k1"] == -1
        for i in 2:n
            @test result["k$i"] == i
        end
    end
end

JSON.lift(::CustomStyle, ::Type{Bool}, x::Bool) = !x
JSON.lift(::CustomStyle, ::Type{Nothing}, ::Nothing) = "nullvalue"

@testset "Custom materialization and mismatched container shapes" begin
    source = "{\"arr\":[true,false,null,1,\"x\",{}]}"
    value = JSON.parse(source, JSON.Object{String,Any}; style=CustomStyle())
    @test value["ARR"] == Any[false, true, "nullvalue", 2, "X", JSON.Object{String,Any}()]
    @test only(JSON.parse("[null]", Vector{Any}; style=CustomStyle())) == "nullvalue"
    @test only(JSON.parse("[false]", Vector{Any})) === false

    # The callback API must use the same custom hooks as typed parsing.
    style = JSON.JSONReadStyle{JSON.Object{String,Any}}(nothing, CustomStyle())
    values = Any[]
    pos = JSON.applyvalue(x -> push!(values, x), JSON.lazy(source), style)
    @test only(values) == value
    @test pos == ncodeunits(source) + 1

    # Fast container methods must preserve the generic shape fallback.
    @test JSON.parse("{}", Vector{Any}) == Any[]
    for T in (JSON.Object{String,Any}, Dict{String,Any})
        @test isempty(JSON.parse("[]", T))
    end
    for T in (Vector{Any}, JSON.Object{String,Any}, Dict{String,Any}), source in ("1", "null")
        @test_throws ArgumentError JSON.parse(source, T)
    end
end

end
