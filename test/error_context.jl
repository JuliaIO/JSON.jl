module ErrorContextTests
using JSON, StructUtils, Test

struct Percent
    value::Float64
end
struct Entry
    percent::Percent
end
struct Envelope
    path::Vector{Entry}
end

JSON.@tags struct Renamed
    count::Int &(json=(name="a/b~c",),)
end

JSON.@noarg mutable struct MutableEntry
    first::Int
    second::Int
end

JSON.@nonstruct struct Checked
    value::Int
end
JSON.lift(::Type{Checked}, value) = value < 0 ? throw(DomainError(value)) : Checked(value)

# Recovers from a failed conversion by building the same value another way.
struct Recovered
    values::Vector{Int}
end
function StructUtils.make(st::StructUtils.StructStyle, ::Type{Recovered}, x::JSON.LazyValue)
    try
        values, pos = StructUtils.make(st, Vector{Checked}, x)
        return Recovered([v.value for v in values]), pos
    catch
        values, pos = StructUtils.make(st, Vector{Int}, x)
        return Recovered(values), pos
    end
end

# Builds its value from separate input, using the style it was given.
struct Foreign end
StructUtils.make(st::StructUtils.StructStyle, ::Type{Foreign}, x::JSON.LazyValue) =
    StructUtils.make(st, Vector{Int}, JSON.lazy("[\"foreign\"]"))

struct PlusStyle <: StructUtils.StructStyle end
StructUtils.lift(::PlusStyle, ::Type{Number}, x::Integer) = (x + 100, nothing)

JSON.@nonstruct struct Interrupting end
JSON.lift(::Type{Interrupting}, value) = throw(InterruptException())

captured(f) = try f(); nothing catch err; err end

@testset "error_context" begin
    # (input, target type, path, text at the failing value, cause type, keywords)
    for (text, T, path, token, cause, kw) in (
        ("""{"path":[{"percent":{"value":0.1}},{"percent":0.1}]}""", Envelope, "/path/1/percent", "0.1}]", ArgumentError, (;)),
        ("""{"rows":[[1,2],[3,"bad"]]}""", @NamedTuple{rows::Vector{Vector{Int}}}, "/rows/1/1", "\"bad\"", MethodError, (;)),
        ("""{"rows":[[1,2],[3,1.5]]}""", @NamedTuple{rows::Vector{Vector{Int}}}, "/rows/1/1", "1.5", InexactError, (; allownan=true)),
        ("""{"path":[{"percent":{"value":0.1,"oops":3}}]}""", Envelope, "/path/0/percent/oops", "3", ArgumentError, (; unknown_fields=:error)),
        # missing fields and syntax errors point at the enclosing value
        ("""{"path":[{"percent":{}}]}""", Envelope, "/path/0/percent", "{}", Union{ArgumentError,TypeError}, (;)),
        ("""{"rows":[[1,2],[3,]]}""", @NamedTuple{rows::Vector{Vector{Int}}}, "/rows/1", "[3,]", ArgumentError, (;)),
        ("""{"a":{"b":[1,-]}}""", Dict{String,Any}, "/a/b/1", "-]", ArgumentError, (;)),
        # input key names, escaped per RFC 6901
        ("""{"a/b~c":"bad"}""", Renamed, "/a~1b~0c", "\"bad\"", MethodError, (;)),
        ("""{"":{"\\u03bb":"bad"}}""", Dict{String,Dict{String,Int}}, "//λ", "\"bad\"", MethodError, (;)),
        # tuples, custom lifts, and the input root
        ("[1,\"bad\"]", Tuple{Int,Int}, "/1", "\"bad\"", MethodError, (;)),
        ("""{"left":1,"right":"bad"}""", Tuple{Int,Int}, "/right", "\"bad\"", MethodError, (;)),
        ("[1,-2,3]", Vector{Checked}, "/1", "-2", DomainError, (;)),
        ("\"bad\"", Int, "", "\"bad\"", MethodError, (;)),
        # JSON Lines are indexed like an array; junk between lines is at the root
        ("{}\n{\"value\":1}\n", Vector{Percent}, "/0", "{}", Union{ArgumentError,TypeError}, (; jsonlines=true)),
        ("{\"value\":1}\n{}\n", Vector{Percent}, "/1", "{}", Union{ArgumentError,TypeError}, (; jsonlines=true)),
        ("{\"value\":1} {\"value\":2}\n", Vector{Percent}, "", "{", ArgumentError, (; jsonlines=true)),
    )
        plain = captured(() -> JSON.parse(text, T; kw...))
        @test plain isa cause
        err = captured(() -> JSON.parse(text, T; kw..., error_context=true))
        @test err isa JSON.ParseError
        @test (err.path, err.position) == (path, first(findfirst(token, text)))
        @test typeof(err.cause) == typeof(plain)
        @test occursin("value starts at byte", sprint(showerror, err))
    end

    @testset "inputs" begin
        for context in (false, true)
            @test JSON.parse("{\"value\":7}", Percent; error_context=context).value == 7
            @test JSON.parse("1 trailing", Int; isroot=false, error_context=context) == 1
        end
        text = """{"first":7,"second":"bad"}"""
        for input in (text, IOBuffer(text), JSON.lazy(text))
            value = MutableEntry()
            value.first, value.second = 1, 2
            err = captured(() -> JSON.parse!(input, value; error_context=true))
            @test err isa JSON.ParseError && err.path == "/second"
            @test (value.first, value.second) == (7, 2)
        end
        mktemp() do path, io
            write(io, """{"value":"bad"}""")
            close(io)
            @test captured(() -> JSON.parsefile(path, Percent; error_context=true)).path == "/value"
        end
        # a selected LazyValue: `path` is relative to it, `position` is in the whole input
        text = """{"outer":{"value":"bad"}}"""
        err = captured(() -> JSON.parse(JSON.lazy(text).outer, Percent; error_context=true))
        @test (err.path, err.position) == ("/value", first(findfirst("\"bad\"", text)))
    end

    @testset "untyped" begin
        for text in ("null", "true", "1.5", "\"hi\"", "[1,{\"a\":2}]", "{\"a\":1,\"a\":2}")
            @test isequal(JSON.parse(text; error_context=true), JSON.parse(text))
        end
        # untyped parses ignore `style`
        @test JSON.parse("[1]"; style=PlusStyle(), error_context=true) == [1]
        err = captured(() -> JSON.parse("""{"a":[1,{"x":1,"x":2}]}"""; duplicate_keys=:error, error_context=true))
        @test err.path == "/a/1"
        @test err.cause isa JSON.DuplicateKeyError
    end

    @testset "custom hooks" begin
        @test JSON.parse("[1,-2,3]", Recovered; error_context=true).values == [1, -2, 3]
        # the failure the hook recovered from is not reported for a later one
        err = captured(() -> JSON.parse("""{"r":[1,-2]}""", @NamedTuple{r::Recovered,n::Int}; error_context=true))
        @test err.path == ""
        # a failure in separate input is reported at the value whose hook read it
        err = captured(() -> JSON.parse("[100,200]", Foreign; error_context=true))
        @test (err.path, err.position) == ("", 1)
        @test captured(() -> JSON.parse("[1]", Vector{Interrupting}; error_context=true)) isa InterruptException
    end
end
end
