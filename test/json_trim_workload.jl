# Trim-compile workload: covers typed and untyped parse, JSON writing, and —
# specifically for the trim-verifier fixes — the parse error paths (unknown
# fields with PtrString keys, the bad `unknown_fields` option message) and the
# hand-formatted Date/DateTime/Time lowers. Compiled by
# test/trim_compile_tests.jl with `juliac --trim=safe` (error budget zero),
# then executed so the assertions also prove runtime behavior.
using JSON
using Dates

struct TrimUser
    id::Int
    name::String
end

@defaults struct TrimConfig
    enabled::Bool = false
    label::String = "none"
    count::Int = 0
end

function _assert_typed_parse()::Nothing
    u = JSON.parse("""{"id":1,"name":"ab"}""", TrimUser)
    u.id == 1 || error("typed id")
    u.name == "ab" || error("typed name")

    c = JSON.parse("""{"enabled":true,"count":7}""", TrimConfig)
    c.enabled || error("kwdef bool")
    c.label == "none" || error("kwdef default")
    c.count == 7 || error("kwdef count")

    v = JSON.parse("""[1,2,3]""", Vector{Int})
    v == [1, 2, 3] || error("typed vector")

    d = JSON.parse("""{"a":1,"b":2}""", Dict{String,Int})
    d["a"] == 1 || error("typed dict")
    return nothing
end

# the error paths the trim fixes rewrote: these must not only compile under
# --trim but produce the exact messages at runtime
function _assert_error_paths()::Nothing
    threw = false
    try
        JSON.parse("""{"id":1,"name":"a","extra":2}""", TrimUser; unknown_fields = :error)
    catch e
        e isa ArgumentError || error("unknown-field error type")
        m = e.msg
        m isa String || error("unknown-field msg type")
        # PtrString key formatting (unknownfieldkey)
        occursin("unknown JSON member \"extra\"", m) || error("unknown-field msg")
        occursin("TrimUser", m) || error("unknown-field target type")
        threw = true
    end
    threw || error("unknown-field did not throw")

    threw = false
    try
        JSON.parse("""{"id":1,"name":"a"}""", TrimUser; unknown_fields = :bogus)
    catch e
        e isa ArgumentError || error("bad-option error type")
        m = e.msg
        m isa String || error("bad-option msg type")
        # plain symbol interpolation (not `repr`/Expr-show)
        occursin(":bogus", m) || error("bad-option msg")
        threw = true
    end
    threw || error("bad-option did not throw")
    return nothing
end

function _assert_untyped_parse()::Nothing
    # untyped parse returns Any by design (any JSON value type) — narrow the
    # top-level to the concrete Object before indexing, as trim-compiled
    # consumers must
    raw = JSON.parse("""{"a":[1,2],"b":{"c":null},"s":"x","f":1.5,"t":true}""")
    raw isa JSON.Object{String,Any} || error("untyped root type")
    o = raw
    a = o["a"]
    a isa Vector{Any} || error("untyped array type")
    length(a) == 2 || error("untyped array len")
    a1 = a[1]
    (a1 isa Int && a1 == 1) || error("untyped array elem")
    rawb = o["b"]
    rawb isa JSON.Object{String,Any} || error("untyped nested type")
    c = rawb["c"]
    c === nothing || error("untyped null")
    s = o["s"]
    (s isa String && s == "x") || error("untyped string")
    f = o["f"]
    (f isa Float64 && f == 1.5) || error("untyped float")
    t = o["t"]
    (t === true) || error("untyped bool")
    return nothing
end

function _assert_json_write()::Nothing
    JSON.json((; a = [1, 2], b = "x")) == "{\"a\":[1,2],\"b\":\"x\"}" || error("json nt")
    JSON.json([1, 2, 3]) == "[1,2,3]" || error("json vector")
    JSON.json(Dict("k" => 1)) == "{\"k\":1}" || error("json dict")
    JSON.json("q\"uote") == "\"q\\\"uote\"" || error("json escape")
    JSON.json(nothing) == "null" || error("json null")
    u = TrimUser(3, "n")
    JSON.json(u) == "{\"id\":3,\"name\":\"n\"}" || error("json struct")
    round = JSON.parse(JSON.json(u), TrimUser)
    round.id == 3 || error("roundtrip")
    return nothing
end

# hand-formatted ISO lowers: exact renderings, including millisecond padding
# and the ms-free forms
function _assert_date_lowers()::Nothing
    JSON.json(Date(2026, 7, 3)) == "\"2026-07-03\"" || error("date lower")
    JSON.json(DateTime(2026, 7, 3, 4, 5, 6)) == "\"2026-07-03T04:05:06\"" || error("datetime lower")
    JSON.json(DateTime(2026, 7, 3, 4, 5, 6, 70)) == "\"2026-07-03T04:05:06.070\"" || error("datetime ms pad")
    JSON.json(Time(1, 2, 3)) == "\"01:02:03\"" || error("time lower")
    JSON.json(Time(1, 2, 3, 45)) == "\"01:02:03.045\"" || error("time ms pad")
    JSON.json((; d = Date(2026, 1, 2), t = Time(23, 59, 59))) ==
        "{\"d\":\"2026-01-02\",\"t\":\"23:59:59\"}" || error("dates in object")
    return nothing
end

function run_json_trim_workload()::Nothing
    _assert_typed_parse()
    _assert_error_paths()
    _assert_untyped_parse()
    _assert_json_write()
    _assert_date_lowers()
    return nothing
end

function @main(args::Vector{String})::Cint
    _ = args
    run_json_trim_workload()
    return 0
end

Base.Experimental.entrypoint(main, (Vector{String},))
