using JSON
using Random
using Serialization

const MIN_JSON_BYTES = 512
const MAX_JSON_BYTES = 1024
const MAX_DEPTH = 3
const MIN_CONTAINER_LEN = 3
const MAX_CONTAINER_LEN = 8
const ROOT_STRING_MIN = 32
const ROOT_STRING_MAX = 72
const MAX_STRING_LEN = 64
const PRINT_INTERVAL = 256

function random_ascii_code(rng::AbstractRNG)::UInt8
    return rand(rng, UInt8(32):UInt8(126))
end

function random_string(rng::AbstractRNG, depth::Int)::String
    base = depth == 0 ? rand(rng, ROOT_STRING_MIN:ROOT_STRING_MAX) : rand(rng, 0:MAX_STRING_LEN)
    buffer = Vector{UInt8}(undef, base)
    for i in eachindex(buffer)
        buffer[i] = random_ascii_code(rng)
    end
    return String(buffer)
end

function random_leaf(rng::AbstractRNG)::Any
    choice = rand(rng, 1:8)
    choice == 1 && return rand(rng, -1_000_000:1_000_000)
    choice == 2 && return randn(rng)
    choice == 3 && return rand(rng)
    choice == 4 && return rand(rng, Bool)
    choice == 5 && return nothing
    choice == 6 && return missing
    choice == 7 && return random_string(rng, 1)
    return string(rand(rng, 1:1_000_000), "-", random_string(rng, 1))
end

function random_array(rng::AbstractRNG, depth::Int)::Vector{Any}
    len = rand(rng, MIN_CONTAINER_LEN:MAX_CONTAINER_LEN)
    values = Any[]
    sizehint!(values, len)
    for _ in 1:len
        push!(values, random_value(rng, depth + 1))
    end
    return values
end

function random_object(rng::AbstractRNG, depth::Int)::Dict{String, Any}
    len = rand(rng, MIN_CONTAINER_LEN:MAX_CONTAINER_LEN)
    dict = Dict{String, Any}()
    while length(dict) < len
        key = random_string(rng, depth)
        dict[key] = random_value(rng, depth + 1)
    end
    return dict
end

function random_value(rng::AbstractRNG, depth::Int)::Any
    depth >= MAX_DEPTH && return random_leaf(rng)
    choice = rand(rng)
    choice < 0.4 && return random_array(rng, depth)
    choice < 0.8 && return random_object(rng, depth)
    return random_leaf(rng)
end

function replay_candidate(seed::Integer, attempt::Integer)::Any
    rng = MersenneTwister(seed)
    candidate = nothing
    for i in 1:attempt
        candidate = random_value(rng, 0)
    end
    return candidate
end

function fuzz_pretty(; max_seeds::Int=50_000, attempts_per_seed::Int=64, indent::Int=2,
    min_bytes::Int=MIN_JSON_BYTES, max_bytes::Int=MAX_JSON_BYTES, verbose::Bool=true)
    for seed in 0:max_seeds - 1
        rng = MersenneTwister(seed)
        for attempt in 1:attempts_per_seed
            candidate = random_value(rng, 0)
            compact_len = 0
            try
                compact_len = ncodeunits(JSON.json(candidate))
            catch e
                if e isa BoundsError
                    println("BoundsError (compact) with seed=$(seed) attempt=$(attempt)")
                    filename = joinpath(@__DIR__, "fuzz_pretty_failure_seed$(seed)_attempt$(attempt).bin")
                    Serialization.serialize(filename, candidate)
                    println("Serialized failing candidate to $(filename)")
                    return (seed=seed, attempt=attempt, candidate=candidate, error=e)
                end
                rethrow()
            end
            if compact_len < min_bytes || compact_len > max_bytes
                continue
            end
            try
                JSON.json(candidate, indent)
            catch e
                if e isa BoundsError
                    println("BoundsError with seed=$(seed) attempt=$(attempt) compact_len=$(compact_len)")
                    context = IOContext(stdout, :limit => true)
                    println("Candidate Julia expression:")
                    show(context, MIME"text/plain"(), candidate)
                    println()
                    filename = joinpath(@__DIR__, "fuzz_pretty_failure_seed$(seed)_attempt$(attempt).bin")
                    Serialization.serialize(filename, candidate)
                    println("Serialized failing candidate to $(filename)")
                    return (seed=seed, attempt=attempt, candidate=candidate, error=e)
                end
                rethrow()
            end
            if verbose && attempt % PRINT_INTERVAL == 0
                println("Checked seed=$(seed) attempt=$(attempt) compact_len=$(compact_len)")
            end
        end
    end
    verbose && println("No failure found up to $(max_seeds) seeds")
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    max_seeds = parse(Int, get(ENV, "JSON_FUZZ_MAX_SEEDS", "50000"))
    attempts = parse(Int, get(ENV, "JSON_FUZZ_ATTEMPTS", "64"))
    result = fuzz_pretty(max_seeds=max_seeds, attempts_per_seed=attempts)
    result === nothing && exit(0)
    println("Replay with replay_candidate($(result.seed), $(result.attempt))")
end
