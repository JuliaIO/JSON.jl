using JSON, StructUtils, Chairmarks

# 1. Plain struct (no defaults) — the common case, must not regress
struct PlainStruct
    a::Int
    b::Int
    c::Int
    d::Int
end

# 2. Struct with simple (non-dependent) defaults
@defaults struct WithDefaults
    a::Int
    b::Int
    c::Int = 0
    d::Int = 0
end

# 3. Struct with computed/dependent defaults (the new feature)
@defaults struct WithComputed
    a::Int
    b::String = string(a)
end

# 4. Nested struct parsing (from existing benchmarks, for reference)
struct Inner
    x::Int
    y::Int
end

struct Outer
    name::String
    inner::Inner
    value::Float64
end

println("=== Struct parsing benchmarks ===")
println()

println("1. Plain struct (no defaults, all fields provided):")
print("   ")
display(@b JSON.parse("""{"a":1,"b":2,"c":3,"d":4}""", PlainStruct))
println()

println("2. Struct with simple defaults (all fields provided):")
print("   ")
display(@b JSON.parse("""{"a":1,"b":2,"c":3,"d":4}""", WithDefaults))
println()

println("3. Struct with simple defaults (defaults used):")
print("   ")
display(@b JSON.parse("""{"a":1,"b":2}""", WithDefaults))
println()

println("4. Struct with computed default (default used):")
try
    print("   ")
    display(@b JSON.parse("""{"a":42}""", WithComputed))
    println()
catch e
    println("   FAILED: $e")
end

println("5. Struct with computed default (all provided):")
print("   ")
display(@b JSON.parse("""{"a":42,"b":"hello"}""", WithComputed))
println()

println("6. Nested struct:")
print("   ")
display(@b JSON.parse("""{"name":"test","inner":{"x":1,"y":2},"value":3.14}""", Outer))
println()
