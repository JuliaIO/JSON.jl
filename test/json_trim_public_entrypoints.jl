using Dates, JSON

const ARRAY_JSON = "[1,2,3]"
const STRING_JSON = "\"Ada\""
const TRIM_FIXTURE_DIR = joinpath(@__DIR__, "trim")

JSON.@nonstruct struct TrimCode
    value::String
end

JSON.lower(x::TrimCode) = x.value

struct TrimLeaf
    id::Int
    name::String
end

struct TrimRoot
    item::Union{Nothing,TrimLeaf}
    items::Vector{TrimLeaf}
    tags::Vector{String}
    note::Union{Nothing,String}
end

JSON.StructUtils.@defaults struct TrimTagged
    value::Int = 0 & (json=(name="wire",),)
    secret::Int = 9 & (json=(ignore=true,),)
end

JSON.StructUtils.@noarg mutable struct TrimMutable
    value::Int = 0
end

struct TrimTemporal
    day::Dates.Date
    stamp::Dates.DateTime
    tick::Dates.Time
end

function checked(cond::Bool, msg::String)::Nothing
    cond || error(msg)
    return nothing
end

function exercise_lazy_entrypoints()::Nothing
    checked(JSON.lazy(ARRAY_JSON) isa JSON.LazyValue, "lazy failed")
    checked(JSON.lazyfile(joinpath(TRIM_FIXTURE_DIR, "value.json")) isa JSON.LazyValue, "lazyfile failed")
    return nothing
end

function exercise_parse_entrypoints()::Nothing
    # Open-ended untyped results are data-dependent. Narrow their runtime shape
    # before use in a safe-trim binary; `lazy` remains the arbitrary-shape path.
    untyped = JSON.parse("{\"name\":\"Ada\"}")
    checked(untyped isa JSON.Object{String,Any}, "untyped object parse failed")
    name = (untyped::JSON.Object{String,Any})["name"]
    checked(name isa String, "untyped string shape failed")
    checked((name::String) == "Ada", "untyped string value failed")

    checked(JSON.parse("7", Int) == 7, "typed scalar parse failed")
    checked(JSON.parse(IOBuffer(STRING_JSON), String) == "Ada", "typed IO parse failed")
    checked(JSON.parse(ARRAY_JSON, Vector{Int}) == [1, 2, 3], "typed array parse failed")
    checked(JSON.parse("{\"score\":7}", Dict{String,Int}) == Dict("score" => 7),
        "typed dictionary parse failed")

    root = JSON.parse(
        "{\"item\":{\"id\":1,\"name\":\"one\"},\"items\":[{\"id\":2,\"name\":\"two\"}],\"tags\":[\"a\"],\"note\":null}",
        TrimRoot,
    )
    checked(root.item !== nothing && root.item.id == 1, "nested struct parse failed")
    checked(length(root.items) == 1 && root.items[1].name == "two",
        "nested vector parse failed")
    checked(root.tags == ["a"] && root.note === nothing, "nullable field parse failed")

    tagged = JSON.parse(
        "{\"wire\":4,\"secret\":99}",
        TrimTagged;
        unknown_fields=:error,
    )
    checked(tagged == TrimTagged(4, 9), "field-tag parse failed")

    mutable_value = TrimMutable()
    JSON.parse!("{\"value\":8}", mutable_value; unknown_fields=:error)
    checked(mutable_value.value == 8, "parse! failed")

    unknown = try
        JSON.parse("{\"extra\":1}", TrimLeaf; unknown_fields=:error)
        nothing
    catch err
        err
    end
    checked(unknown isa ArgumentError, "unknown-field diagnostic failed")
    return nothing
end

function exercise_write_entrypoints()::Nothing
    obj = JSON.Object{String, Int}("score" => 7)
    obj[:score] = 10
    checked(obj.score == 10, "Object property access failed")
    checked(haskey(obj, "score"), "Object setindex! failed")
    delete!(obj, :score)
    checked(!haskey(obj, "score"), "Object delete! failed")

    checked(JSON.json([1, 2, 3]) == ARRAY_JSON, "json string output failed")

    io = IOBuffer()
    JSON.json(io, [1, 2, 3]; pretty = 2)
    checked(String(take!(io)) == "[\n  1,\n  2,\n  3\n]", "pretty IO json output failed")

    print_io = IOBuffer()
    JSON.print(print_io, [1, 2, 3], 2)
    checked(String(take!(print_io)) == "[\n  1,\n  2,\n  3\n]", "JSON.print failed")

    jsonlines = JSON.json([[1], [2]]; jsonlines = true)
    checked(jsonlines == "[1]\n[2]\n", "jsonlines write failed")
    checked(JSON.json(JSON.JSONText("{\"raw\":true}")) == "{\"raw\":true}", "JSONText write failed")
    checked(JSON.json(JSON.Null()) == "null", "JSON.Null write failed")
    checked(JSON.json(TrimCode("beta")) == "\"beta\"", "custom lower write failed")

    # Date, DateTime, and Time round-trip through their canonical ISO text.
    temporal = TrimTemporal(
        Dates.Date(2026, 8, 7),
        Dates.DateTime(2026, 8, 7, 15, 0, 0, 76),
        Dates.Time(12, 30, 15, 250),
    )
    temporal_json = JSON.json(temporal)
    checked(
        temporal_json ==
        "{\"day\":\"2026-08-07\",\"stamp\":\"2026-08-07T15:00:00.076\",\"tick\":\"12:30:15.25\"}",
        "temporal write failed",
    )
    checked(
        JSON.parse(temporal_json, TrimTemporal) == temporal,
        "temporal read failed",
    )
    checked(
        JSON.json(Dates.DateTime(2026, 1, 1)) == "\"2026-01-01T00:00:00\"",
        "zero-millisecond DateTime write failed",
    )
    return nothing
end

function run_json_trim_public_entrypoints()::Nothing
    exercise_lazy_entrypoints()
    exercise_parse_entrypoints()
    exercise_write_entrypoints()
    return nothing
end

function @main(args::Vector{String})::Cint
    _ = args
    run_json_trim_public_entrypoints()
    return 0
end

Base.Experimental.entrypoint(main, (Vector{String},))
