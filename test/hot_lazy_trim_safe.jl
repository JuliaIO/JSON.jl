# :hot typed parsing under `juliac --trim=safe`: the specialized lazy
# descent for annotated types, driven from real JSON text. Unlike
# tree-shaped sources (where the hot findfield's field x value-type
# cross-product limits scalar variety), the lazy source is uniform — every
# field branch sees a LazyValue — so heterogeneous scalars (dates, UUIDs,
# symbols) are exercised here. Compiled in an env with the StructUtils
# `trim_build` preference, which prunes the tier-0 tree route and its
# invokelatest boundary out of the typed-parse entry.
using JSON, StructUtils, Dates, UUIDs

@kwarg :hot struct LTier
    name::String
    amount::Int = 0
    currency::String = "usd"
end

@kwarg :hot struct LEvent
    name::String
    day::Date = Date(0)
    at::Union{DateTime,Nothing} = nothing
    uid::Union{UUID,Nothing} = nothing
    cap::Union{Int,Nothing} = nothing
    kind::Symbol = :none
    venue::Union{LTier,Nothing} = nothing
    tiers::Vector{LTier} = LTier[]
    score::Union{Float64,Missing} = missing
end

const SAMPLE = """
{"name":"Kickoff","day":"2026-08-01","at":"2026-07-25T23:59:59",
 "uid":"c8b1cf79-de6a-54ab-a142-682c06a0de6a","cap":64,"kind":"league",
 "venue":{"name":"Gym","amount":1},
 "tiers":[{"name":"Early","amount":2500,"currency":"eur"},{"name":"Late"}],
 "score":null,"unknown_extra":[1,2,3]}
"""

function run_hot_lazy_trim_sample()
    evx = JSON.parse(SAMPLE, LEvent)
    evx isa LEvent || error("type")
    e = evx::LEvent
    e.name == "Kickoff" || error("name")
    e.day == Date(2026, 8, 1) || error("day")
    e.at == DateTime(2026, 7, 25, 23, 59, 59) || error("at")
    e.uid == UUID("c8b1cf79-de6a-54ab-a142-682c06a0de6a") || error("uid")
    e.cap == 64 || error("cap")
    e.kind === :league || error("kind")
    v = e.venue
    v isa LTier || error("venue")
    (v::LTier).amount == 1 || error("venue amount")
    length(e.tiers) == 2 || error("tiers")
    e.tiers[1].currency == "eur" || error("cur1")
    e.tiers[2].currency == "usd" || error("cur2")
    e.score === missing || error("score")
    # defaults-only parse
    m = JSON.parse("{\"name\":\"m\"}", LEvent)
    (m::LEvent).cap === nothing || error("m cap")
    isempty((m::LEvent).tiers) || error("m tiers")
    # untyped parse + isa-narrow (the #472 pattern)
    u = JSON.parse(SAMPLE)
    if u isa JSON.Object{String,Any}
        c = u["cap"]
        c isa Int64 || error("untyped cap")
        c == 64 || error("untyped cap value")
    else
        error("untyped root")
    end
    # TODO(write-side trim): JSON.json of a struct is not yet verifier-clean
    # on master — the writer's BigFloat arm reaches string(::BigFloat) MPFR
    # internals and an array-show typeinfo invoke_in_world. Write tiering is
    # follow-up work; this workload pins the read path.
    # required-field error path
    threw = false
    try
        JSON.parse("{\"amount\":1}", LTier)
    catch
        threw = true
    end
    threw || error("required")
    return nothing
end

function @main(args::Vector{String})::Cint
    _ = args
    run_hot_lazy_trim_sample()
    Core.println("HOT_LAZY_TRIM_OK")
    return 0
end

Base.Experimental.entrypoint(main, (Vector{String},))
