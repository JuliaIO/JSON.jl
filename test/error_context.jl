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

JSON.@nonstruct struct Checked
    value::Int
end
const seen = Int[]
const rejection = DomainError(-2, "must be nonnegative")
function checked_lift(value)
    push!(seen, value)
    value < 0 && throw(rejection)
    return Checked(value)
end
JSON.lift(::Type{Checked}, value) = checked_lift(value)

JSON.@tags struct Renamed
    count::Int &(json=(name="a/b~c",),)
end

JSON.@noarg mutable struct MutableEntry
    first::Int
    second::Int
end

struct ContextStyle <: StructUtils.StructStyle end
StructUtils.lift(::ContextStyle, ::Type{Checked}, value::Integer) = (checked_lift(value), nothing)

JSON.@nonstruct struct FatalValue end
const fatal = Ref{Exception}(InterruptException())
JSON.lift(::Type{FatalValue}, value) = throw(fatal[])

struct Recovered
    values::Vector{Int}
end
const caught = Ref{Any}(nothing)
function StructUtils.make(st::StructUtils.StructStyle, ::Type{Recovered}, x::JSON.LazyValue)
    try
        values, pos = StructUtils.make(st, Vector{Checked}, x)
        return Recovered(getfield.(values, :value)), pos
    catch err
        caught[] = err
        err isa DomainError || rethrow()
        values, pos = StructUtils.make(st, Vector{Int}, x)
        return Recovered(values), pos
    end
end

struct MethodRecovered
    values::Vector{Any}
end
function StructUtils.make(st::StructUtils.StructStyle, ::Type{MethodRecovered}, x::JSON.LazyValue)
    try
        values, pos = StructUtils.make(st, Vector{Int}, x)
        return MethodRecovered(values), pos
    catch err
        err isa MethodError || rethrow()
        values, pos = StructUtils.make(st, Vector{Any}, x)
        return MethodRecovered(values), pos
    end
end

struct NumberStyle <: StructUtils.StructStyle end
StructUtils.lift(::NumberStyle, ::Type{Number}, value::Integer) = (value + 100, nothing)

struct ForeignSource end
StructUtils.make(st::StructUtils.StructStyle, ::Type{ForeignSource}, x::JSON.LazyValue) =
    StructUtils.make(st, Vector{Int}, JSON.lazy("[\"foreign\"]"))

struct Retried{mode} end
throw_again() = throw(rejection)
function StructUtils.make(st::StructUtils.StructStyle, ::Type{Retried{mode}}, x::JSON.LazyValue) where {mode}
    for name in (:attempt, :final)
        try
            StructUtils.make(st, Vector{Checked}, getproperty(x, name))
        catch
            if mode === :throw
                throw_again()
            elseif mode === :rethrow
                StructUtils.make(st, Vector{Int}, x.final)
                rethrow()
            elseif name === :final
                rethrow()
            end
        end
    end
    error("expected a conversion failure")
end

captured(f) = try f(); nothing catch err; err end

function checkerror(text, target, path, token, cause; kw...)
    old = captured(() -> JSON.parse(text, target; kw...))
    @test old isa cause
    err = captured(() -> JSON.parse(text, target; kw..., error_context=true))
    @test err isa JSON.ParseError
    err isa JSON.ParseError || return err
    @test err.path == path
    @test err.position == first(findfirst(token, text))
    @test err.cause isa cause
    @test typeof(err.cause) === typeof(old)
    @test !isempty(err.backtrace)
    @test occursin("value starts at byte", sprint(showerror, err))
    return err
end

@testset "opt-in JSON error context" begin
    @testset "keyword forwarding" begin
        for source in (identity, IOBuffer, JSON.lazy)
            for context in (false, true)
                @test JSON.parse(source("{\"value\":7}"), Percent; error_context=context).value == 7
                value = MutableEntry()
                JSON.parse!(source("{\"first\":7,\"second\":8}"), value; error_context=context)
                @test (value.first, value.second) == (7, 8)
                @test captured(() -> JSON.parse(source("1"), Int;
                    unsupported_option=true, error_context=context)) isa MethodError
                @test captured(() -> JSON.parse!(source("{}"), MutableEntry();
                    unsupported_option=true, error_context=context)) isa MethodError
            end
            for invalid in (nothing, 1, :enabled)
                for call in (() -> JSON.parse(source("1"), Int; error_context=invalid),
                             () -> JSON.parse!(source("{}"), MutableEntry(); error_context=invalid))
                    err = captured(call)
                    @test err isa TypeError
                    @test (err.func, err.context, err.expected, err.got) ==
                        (Symbol("keyword argument"), :error_context, Bool, invalid)
                end
            end
        end
        for context in (false, true)
            @test JSON.parse("1 trailing", Int; isroot=false, error_context=context) == 1
            @test JSON.parse("1\n2\n", Vector{Int}; jsonlines=true, error_context=context) == [1, 2]
        end
    end

    checkerror("{\"path\":[{\"percent\":{\"value\":0.1}},{\"percent\":0.1}]}",
        Envelope, "/path/1/percent", "0.1}]", ArgumentError)
    checkerror("{\"rows\":[[1,2],[3,\"bad\"]]}", @NamedTuple{rows::Vector{Vector{Int}}},
        "/rows/1/1", "\"bad\"", MethodError)
    checkerror("{\"rows\":[[1,2],[3,1.5]]}", @NamedTuple{rows::Vector{Vector{Int}}},
        "/rows/1/1", "1.5", InexactError; allownan=true)
    checkerror("{\"path\":[{\"percent\":{\"value\":0.1,\"oops\":3}}]}",
        Envelope, "/path/0/percent/oops", "3", ArgumentError; unknown_fields=:error)
    checkerror("{\"path\":[{\"percent\":{}}]}", Envelope,
        "/path/0/percent", "{}", Union{ArgumentError,TypeError})
    checkerror("{\"rows\":[[1,2],[3,]]}", @NamedTuple{rows::Vector{Vector{Int}}},
        "/rows/1", "[3,]", ArgumentError)
    checkerror("{\"a/b~c\":\"bad\"}", Renamed,
        "/a~1b~0c", "\"bad\"", MethodError)
    checkerror("{\"a/b\":{\"m~n\":[1,\"bad\"]}}", Dict{String,Dict{String,Vector{Int}}},
        "/a~1b/m~0n/1", "\"bad\"", MethodError)
    checkerror("{\"\":{\"\\u03bb\":\"bad\"}}", Dict{String,Dict{String,Int}},
        "//λ", "\"bad\"", MethodError)
    checkerror("[1,\"bad\"]", Tuple{Int,Int}, "/1", "\"bad\"", MethodError)
    checkerror("{\"left\":1,\"right\":\"bad\"}", Tuple{Int,Int},
        "/right", "\"bad\"", MethodError)
    checkerror("\"bad\"", Int, "", "\"bad\"", MethodError)

    for style in (StructUtils.DefaultStyle(), ContextStyle())
        empty!(seen)
        err = captured(() -> JSON.parse("[1,-2,3]", Vector{Checked}; style, error_context=true))
        @test err isa JSON.ParseError
        @test err.path == "/1"
        @test err.cause === rejection
        @test seen == [1,-2]
        @test any(frame -> frame.func == :checked_lift, stacktrace(err.backtrace))
    end

    for value in (InterruptException(), OutOfMemoryError(), StackOverflowError())
        fatal[] = value
        @test captured(() -> JSON.parse("[1]", Vector{FatalValue}; error_context=true)) === value
    end

    @testset "custom conversion recovery" begin
        for context in (false, true)
            empty!(seen)
            @test JSON.parse("[1,-2,3]", Recovered; error_context=context).values == [1,-2,3]
            @test caught[] === rejection
            @test seen == [1,-2]
            @test JSON.parse("[1,\"fallback\"]", MethodRecovered; error_context=context).values == [1,"fallback"]
            @test JSON.parse("[1,{\"x\":2}]"; style=NumberStyle(), error_context=context) ==
                [1,JSON.Object("x" => 2)]
        end
        err = captured(() -> JSON.parse("[100,200]", ForeignSource; error_context=true))
        @test err.path == ""
        @test err.position == 1
        @test err.cause isa MethodError

        # Preserve the existing dispatch when a style is itself passed as null.
        nullstyle = StructUtils.DefaultStyle()
        @test captured(() -> JSON.parse("null"; null=nullstyle)) isa MethodError
        err = captured(() -> JSON.parse("null"; null=nullstyle, error_context=true))
        @test err.cause isa MethodError
        @test err.path == ""
        nullstyle = JSON.JSONReadStyle{JSON.Object{String,Any}}(missing)
        for context in (false, true)
            @test JSON.parse("null"; null=nullstyle, error_context=context) === missing
        end

        text = "{\"attempt\":[-2],\"final\":[-2]}"
        for (mode, path, position) in ((:retry, "/final/0", first(findlast("-2", text))),
                                       (:throw, "", 1),
                                       (:rethrow, "/attempt/0", first(findfirst("-2", text))))
            err = captured(() -> JSON.parse(text, Retried{mode}; error_context=true))
            @test err.path == path
            @test err.position == position
            @test err.cause === rejection
            mode === :throw && @test any(frame -> frame.func == :throw_again, stacktrace(err.backtrace))
        end
    end

    for (text, path, pos) in (("{}\n{\"value\":1}\n", "/0", 1),
                              ("{\"value\":1}\n{}\n", "/1", 13))
        err = captured(() -> JSON.parse(text, Vector{Percent}; jsonlines=true, error_context=true))
        @test err isa JSON.ParseError
        @test err.path == path
        @test err.position == pos
    end

    text = "{\"outer\":{\"value\":\"bad\"}}"
    subtree = JSON.lazy(text).outer
    err = captured(() -> JSON.parse(subtree, Percent; error_context=true))
    @test err.path == "/value"
    @test err.position == first(findfirst("\"bad\"", text))

    for input in ("{\"first\":7,\"second\":\"bad\"}", IOBuffer("{\"first\":7,\"second\":\"bad\"}"),
                  JSON.lazy("{\"first\":7,\"second\":\"bad\"}"))
        value = MutableEntry()
        value.first, value.second = 1, 2
        err = captured(() -> JSON.parse!(input, value; error_context=true))
        @test err.path == "/second"
        @test err.cause isa MethodError
        @test (value.first, value.second) == (7,2)
    end

    mktemp() do path, io
        write(io, "{\"value\":\"bad\"}")
        close(io)
        err = captured(() -> JSON.parsefile(path, Percent; error_context=true))
        @test err.path == "/value"
    end

    for text in ("null", "true", "1", "1.5", "\"hello\"", "[1,{\"a\":2}]", "{\"a\":1,\"a\":2}")
        @test isequal(JSON.parse(text; error_context=true), JSON.parse(text))
        @test isequal(JSON.parse(IOBuffer(text); error_context=true), JSON.parse(text))
    end
    err = captured(() -> JSON.parse("{\"a\":{\"x\":1,\"x\":2}}"; duplicate_keys=:error, error_context=true))
    @test err isa JSON.ParseError
    @test err.path == "/a"
    @test err.cause isa JSON.DuplicateKeyError
end
end
