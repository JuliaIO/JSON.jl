# Run each mode in a fresh process with the JSON/StructUtils versions under test:
# julia --startup-file=no --project=<env> benchmarks/geojson_regressions.jl <mode>
# Modes: runtime (needs Chairmarks), cold, load, precompile.
# TSV output: runtime name/seconds/allocations/bytes; cold name/seconds/bytes/compile_seconds.
# Precompile measures rebuilding these packages with dependencies already cached.
# Repeat in alternating version order; do not run performance jobs concurrently.
mode = isempty(ARGS) ? "runtime" : only(ARGS)
if mode in ("load", "precompile")
    using UUIDs
    for (name, uuid) in (("StructUtils", "ec057cc2-7a8d-4b58-b3b3-92acb9f63b42"),
                         ("JSON", "682c06a0-de6a-54ab-a142-c8b1cf79cde6"))
        result = if mode == "load"
            @timed Core.eval(Main, Expr(:using, Expr(:., Symbol(name))))
        else
            @timed Base.compilecache(Base.PkgId(UUID(uuid), name))
        end
        println(join((name, result.time, result.bytes, get(result, :compile_time, NaN)), '\t'))
        flush(stdout)
    end
    exit()
end

using JSON, Dates
struct SmallRecord
    a::Int
    b::String
end
struct RecursiveRecord
    value::Int
    children::Vector{RecursiveRecord}
end
struct ConversionStyle <: JSON.JSONStyle end
JSON.lower(::ConversionStyle, x::String) = uppercase(x)
JSON.lift(::ConversionStyle, ::Type{String}, x::String) = uppercase(x)

if mode == "cold"
    for (name, expression) in (
        ("write_small", :(JSON.json(SmallRecord(1, "x")))),
        ("read_small", :(JSON.parse("{\"a\":1,\"b\":\"x\"}", SmallRecord))),
        ("write_any", :(JSON.json(JSON.Object{String,Any}("a" => Any[1, "x", nothing])))),
        ("read_any", :(JSON.parse("{\"a\":[1,\"x\",null]}", JSON.Object{String,Any}))),
        ("write_tree", :(JSON.json(RecursiveRecord(1, [RecursiveRecord(2, RecursiveRecord[])])))))
        result = @timed Core.eval(Main, expression)
        println(join((name, result.time, result.bytes, get(result, :compile_time, NaN)), '\t'))
        flush(stdout)
    end
    for width in (10, 30, 60)
        name = Symbol(:WideRecord, width)
        @eval struct $name
            $([:($(Symbol(:field, i))::Union{Nothing,Int,String,Float64,Bool}) for i in 1:width]...)
        end
        value = Core.eval(Main, Expr(:call, name, fill(1, width)...))
        result = @timed Core.eval(Main, :(JSON.json($value)))
        println(join((name, result.time, result.bytes, get(result, :compile_time, NaN)), '\t'))
        flush(stdout)
    end
    exit()
end
mode == "runtime" || error("unknown benchmark mode: $mode")
using Chairmarks, Statistics
function measure(name, f)
    f() # separate compilation from steady-state measurements
    result = median(@be f() seconds=0.3)
    println(join((name, result.time, result.allocs, result.bytes), '\t'))
    flush(stdout)
end
for n in (4, 137, 10000)
    # Numeric keys must retain string ordering without allocating for indices.
    for T in (Int, Float64), sort_keys in (true, false)
        dict = Dict(T(i) => i for i in 1:n)
        measure("write_numeric_keys_$(T)_$(sort_keys)_$n", () -> JSON.json(dict; sort_keys))
    end
    for (name, values) in (("Int32", Int32.(1:n)), ("Float32", Float32.(1:n)),
                           ("Float64", Float64.(1:n)), ("Date", fill(Date(2026, 1, 1), n)),
                           ("struct", fill(SmallRecord(1, "x"), n)),
                           ("Any", Any[isodd(i) ? i : "x" for i in 1:n]),
                           ("union", Union{Nothing,Int,String,Float64,Bool}[isodd(i) ? i : "x" for i in 1:n]))
        measure("write_array_$(name)_$n", () -> JSON.json(values))
        dict = Dict(string(i) => value for (i, value) in enumerate(values))
        measure("write_dict_$(name)_$n", () -> JSON.json(dict))
        measure("write_unsorted_$(name)_$n", () -> JSON.json(dict; sort_keys=false))
    end
    source = "{" * join(("\"k$i\":$i" for i in 1:n), ",") * "}"
    for T in (Any, JSON.Object{String,Any}, Dict{String,Any})
        measure("read_object_$(T)_$n", () -> JSON.parse(source, T))
    end
end
for depth in (1, 16, 64, 256)
    value = Any[1, "x", true, nothing]
    for level in 1:depth
        value = isodd(level) ? Any[value] :
            level % 4 == 0 ? Dict{String,Any}("a" => value) : JSON.Object{String,Any}("a" => value)
    end
    source = JSON.json(value)
    measure("write_nested_$depth", () -> JSON.json(value))
    measure("read_nested_$depth", () -> JSON.parse(source))
    io = IOBuffer()
    measure("write_io_nested_$depth", () -> (truncate(io, 0); seekstart(io); JSON.json(io, value; bufsize=64)))
end
for depth in (1, 16, 64, 256)
    tree = RecursiveRecord(1, RecursiveRecord[])
    for _ in 1:depth
        tree = RecursiveRecord(1, [tree])
    end
    measure("write_tree_$depth", () -> JSON.json(tree))
end
for n in (1, 1000, 100000)
    source = "[" * join(fill("{\"a\":1,\"b\":\"x\"}", n), ",") * "]"
    measure("read_bulk_any_$n", () -> JSON.parse(source, Vector{Any}))
    measure("read_bulk_struct_$n", () -> JSON.parse(source, Vector{SmallRecord}))
end
for width in (10, 30, 60)
    name = Symbol(:WideRecord, width)
    @eval struct $name
        $([:($(Symbol(:field, i))::Union{Nothing,Int,String,Float64,Bool}) for i in 1:width]...)
    end
    value = Core.eval(Main, Expr(:call, name, fill(1, width)...))
    measure("write_wide_$width", () -> JSON.json(value))
end
strings = fill("secret", 1000)
measure("write_custom_style", () -> JSON.json(strings; style=ConversionStyle()))
source = JSON.json(strings)
measure("read_custom_style", () -> JSON.parse(source, Vector{Any}; style=ConversionStyle()))
