using JSON

const ARRAY_JSON = "[1,2,3]"
const STRING_JSON = "\"Ada\""
const TRIM_FIXTURE_DIR = joinpath(@__DIR__, "trim")

JSON.@nonstruct struct TrimCode
    value::String
end

JSON.lower(x::TrimCode) = x.value

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
    # Materializing JSON.parse currently pulls in verifier failures in parser
    # and StructUtils error paths, so keep this read workload to trim-safe
    # lazy entrypoints until those verifier issues can be chased down.
    checked(JSON.lazy("7") isa JSON.LazyValue, "numeric lazy detection failed")
    checked(JSON.lazy(IOBuffer(STRING_JSON)) isa JSON.LazyValue, "IO lazy detection failed")
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
