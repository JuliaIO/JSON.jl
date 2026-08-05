using JSON, Test

struct EscapedPlainKey
    alpha::Int
end

struct EscapedUnicodeKey
    café::Int
end

JSON.StructUtils.@tags struct EscapedQuoteTag
    value::Int & (name="display\"name",)
end

JSON.StructUtils.@tags struct EscapedAliasTag
    value::Int & (name=("alias", "slash\\key"),)
end

JSON.StructUtils.@tags struct EscapedSymbolTag
    value::Int & (name=:alpha,)
end

JSON.StructUtils.@defaults struct EscapedAliasCollision
    a::Int = -1 & (json=(name="b",),)
    b::Int = -2
end

@enum EscapedEnumKey alpha

struct EscapedOrderedKeys
    a::Int
    b::Int
    c::Int
end

struct LazyDispatchProbe end
JSON.parse(::JSON.LazyValue, ::Type{LazyDispatchProbe}; kw...) = :lazy_dispatch

module EscapedErrorScope
struct Box{T}
    value::T
end
end

function capture_error(f)
    try
        f()
        return nothing
    catch err
        return err
    end
end

@testset "escaped object keys" begin
    @test JSON.parse("{\"\\u0061lpha\":11}", EscapedPlainKey) == EscapedPlainKey(11)
    @test JSON.parse("{\"caf\\u00e9\":12}", EscapedUnicodeKey) == EscapedUnicodeKey(12)
    @test JSON.parse("{\"display\\\"name\":13}", EscapedQuoteTag) == EscapedQuoteTag(13)
    @test JSON.parse("{\"slash\\\\key\":14}", EscapedAliasTag) == EscapedAliasTag(14)
    @test JSON.parse("{\"\\u0061lpha\":15}", EscapedSymbolTag) == EscapedSymbolTag(15)
    @test JSON.parse("{\"b\":19}", EscapedAliasCollision) ==
        EscapedAliasCollision(19, -2)
    @test JSON.parse("{\"c\":3,\"\\u0061\":1,\"b\":2}", EscapedOrderedKeys) ==
        EscapedOrderedKeys(1, 2, 3)
    @test JSON.parse("{\"\\u0061lpha\":15}", EscapedPlainKey; unknown_fields=:error) ==
        EscapedPlainKey(15)

    key = Ref{Any}()
    source = JSON.lazy("{\"\\u0061lpha\":1}")
    GC.@preserve source begin
        JSON.applyobject(source) do k, _
            key[] = k
        end
    end
    @test key[] == "alpha"
    @test isequal(key[], "alpha")
    @test hash(key[]) == hash("alpha")
    @test convert(Symbol, key[]) === :alpha

    plain_key = Ref{Any}()
    escaped_key = Ref{Any}()
    plain_source = JSON.lazy("{\"alpha\":1}")
    escaped_source = JSON.lazy("{\"\\u0061lpha\":1}")
    GC.@preserve plain_source escaped_source begin
        JSON.applyobject(plain_source) do k, _
            plain_key[] = k
        end
        JSON.applyobject(escaped_source) do k, _
            escaped_key[] = k
        end
        @test plain_key[] == escaped_key[]
        @test isequal(plain_key[], escaped_key[])
        @test hash(plain_key[]) == hash(escaped_key[])
        keys = Dict{Any,Int}(plain_key[] => 1, escaped_key[] => 2)
        @test length(keys) == 1
        @test keys[plain_key[]] == 2
    end

    @test JSON.parse("{\"\\u0061lpha\":16}") == Dict("alpha" => 16)
    @test JSON.parse("{\"\\u0061lpha\":17}", Dict{Symbol,Int}) == Dict(:alpha => 17)
    @test JSON.parse("{\"\\u0061lpha\":18}", Dict{EscapedEnumKey,Int}) ==
        Dict(alpha => 18)

    for input in (
        "{\"alpha\":1,\"\\u0061lpha\":2}",
        "{\"café\":1,\"caf\\u00e9\":2}",
        "{\"display\\\"name\":1,\"display\\u0022name\":2}",
        "{\"slash\\\\key\":1,\"slash\\u005ckey\":2}",
    )
        @test_throws JSON.DuplicateKeyError JSON.parse(input; duplicate_keys=:error)
        @test_throws JSON.DuplicateKeyError JSON.parse(
            input,
            Dict{String,Int};
            duplicate_keys=:error,
        )
    end

    err = capture_error() do
        JSON.parse("{\"bog\\u0075s\":1}", EscapedPlainKey; unknown_fields=:error)
    end
    @test err isa ArgumentError
    @test occursin("unknown JSON member \"bogus\"", sprint(showerror, err))

    @testset "error rendering" begin
        for (input, rendered) in (
            ("{\"a\\\"b\":1}", "\"a\\\"b\""),
            ("{\"a\\\\b\":1}", "\"a\\\\b\""),
            ("{\"line\\nbreak\":1}", "\"line\\nbreak\""),
        )
            escaped = capture_error() do
                JSON.parse(input, EscapedPlainKey; unknown_fields=:error)
            end
            @test escaped isa ArgumentError
            @test occursin("unknown JSON member $rendered", sprint(showerror, escaped))
        end

        option = capture_error() do
            JSON.parse("{}", EscapedPlainKey; unknown_fields=Symbol("bad\n\""))
        end
        @test option isa ArgumentError
        option_message = sprint(showerror, option)
        @test occursin("Symbol(\"bad\\n\\\"\")", option_message)
        @test !occursin('\n', option_message)

        simple_option = capture_error() do
            JSON.parse("{}", EscapedPlainKey; unknown_fields=:boom)
        end
        @test simple_option isa ArgumentError
        @test occursin("got :boom", sprint(showerror, simple_option))

        symbol_key = JSON.unknownfielderror(EscapedPlainKey, :boom)
        @test occursin("unknown JSON member :boom", sprint(showerror, symbol_key))

        for T in (Vector{Int}, EscapedErrorScope.Box{Int}, Union{Float64,Int})
            typed = capture_error() do
                JSON.invalid(JSON.InvalidChar, "x", 1, T)
            end
            @test typed isa ArgumentError
            @test occursin("parsing type $(string(T))", sprint(showerror, typed))
        end

        scalar = capture_error() do
            JSON.parse("1", EscapedPlainKey)
        end
        @test scalar isa ArgumentError
        scalar_message = sprint(showerror, scalar)
        @test occursin(string(typeof(JSON.lazy("1"))), scalar_message)
        @test occursin("JSONTypes.NUMBER", scalar_message)
    end

    @test JSON.parse(JSON.lazy("{}"), LazyDispatchProbe) === :lazy_dispatch
end
