using Test, JSON, Dates, UUIDs, StructUtils

# tier-0 default typed parsing: every non-:hot typed parse under the default
# read configuration drives the StructUtils field-table interpreter in one
# lazy pass; :hot types and custom dicttype/null take the specialized
# descent. These tests pin parity across the routing boundary.

@kwarg struct IDTier
    name::String
    amount::Int = 0
    currency::String = "usd"
end

@kwarg :hot struct IDHotTier
    name::String
    amount::Int = 0
    currency::String = "usd"
end

@kwarg struct IDEvent
    name::String
    day::Date = Date(0)
    at::Union{DateTime,Nothing} = nothing
    uid::Union{UUID,Nothing} = nothing
    cap::Union{Int,Nothing} = nothing
    kind::Symbol = :none &(json=(name="event_kind",),)
    venue::Union{IDTier,Nothing} = nothing
    tiers::Vector{IDTier} = IDTier[]
    note::Any = nothing
    score::Union{Float64,Missing} = missing
end

@nonstruct struct IDPct
    v::Float64
end
JSON.lift(::Type{IDPct}, x) = IDPct(Float64(x))

@kwarg struct IDCustom
    p::IDPct = IDPct(0.0)
end

const IDJSON = """
{"name":"Kickoff","day":"2026-08-01","at":"2026-07-25T23:59:59",
 "uid":"c8b1cf79-de6a-54ab-a142-682c06a0de6a","cap":64,"event_kind":"league",
 "venue":{"name":"Gym","amount":1},
 "tiers":[{"name":"Early","amount":2500,"currency":"eur"},{"name":"Late"}],
 "note":{"k":"v"},"score":null,"unknown":123}
"""

@testset "tier-0 default typed parse" begin
    ev = JSON.parse(IDJSON, IDEvent)
    @test ev.name == "Kickoff"
    @test ev.day == Date(2026, 8, 1)
    @test ev.at == DateTime(2026, 7, 25, 23, 59, 59)
    @test ev.uid == UUID("c8b1cf79-de6a-54ab-a142-682c06a0de6a")
    @test ev.cap == 64
    @test ev.kind === :league # :json tagkey rename resolved in the field table
    @test ev.venue isa IDTier && ev.venue.amount == 1 && ev.venue.currency == "usd"
    @test length(ev.tiers) == 2
    @test ev.tiers[1].currency == "eur" && ev.tiers[2].currency == "usd"
    @test ev.note isa JSON.Object{String,Any} && ev.note["k"] == "v"
    @test ev.score === missing

    # defaults + fresh containers per parse
    a = JSON.parse("{\"name\":\"a\"}", IDEvent)
    b = JSON.parse("{\"name\":\"b\"}", IDEvent)
    @test isempty(a.tiers) && a.tiers !== b.tiers
    @test a.venue === nothing && a.cap === nothing && a.kind === :none

    # unknown_fields=:error preserved through the interpreter route
    @test_throws ArgumentError JSON.parse("{\"name\":\"x\",\"nope\":1}", IDTier; unknown_fields=:error)

    # :hot types keep the lazy descent, identical results
    @test StructUtils.ishot(IDHotTier)
    h = JSON.parse("{\"name\":\"h\",\"amount\":3}", IDHotTier)
    @test h.name == "h" && h.amount == 3 && h.currency == "usd"

    # custom lift leaf (CUSTOM kind, dynamic arm)
    c = JSON.parse("{\"p\": 0.25}", IDCustom)
    @test c.p.v == 0.25

    # custom dicttype and null take the specialized descent with their
    # existing semantics (note: on that path, Any-typed *fields* materialize
    # as JSON.Object via the lift fallback regardless of dicttype — same as
    # master)
    d = JSON.parse(IDJSON, IDEvent; dicttype=Dict{String,Any})
    @test d.note isa JSON.Object{String,Any} && d.note["k"] == "v"
    m = JSON.parse("{\"name\":\"x\",\"score\":null}", IDEvent; null=missing)
    @test m.score === missing

    # non-object roots drive the interpreter spec tree
    @test JSON.parse("[{\"name\":\"t\"}]", Vector{IDTier})[1].name == "t"

    # sample synthesis produces parseable JSON for eligible types
    s = JSON._synthesize_sample(IDEvent)
    @test s isa String
    sev = JSON.parse(s, IDEvent)
    @test sev isa IDEvent && sev.venue isa IDTier && length(sev.tiers) == 1

    # the hot hook is registered with StructUtils
    @test any(h -> h === JSON._hot_json_hook, StructUtils.HOT_HOOKS)
    # and runs cleanly under force for both annotated and plain types
    StructUtils._hot_precompile!(IDHotTier; force=true)
    StructUtils._hot_precompile!(IDEvent, ("{\"name\":\"s\"}",); force=true)
    @test true
end
