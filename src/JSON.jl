module JSON

# stdlibs
using Dates, UUIDs, Logging
# external dependencies
using PrecompileTools, Parsers, StructUtils

# reexport some StructUtils macros
import StructUtils: @noarg, @defaults, @tags, @choosetype, @nonstruct, lower, lift
export JSONText, StructUtils, @noarg, @defaults, @tags, @choosetype, @nonstruct, @omit_null, @omit_empty

@enum Error InvalidJSON UnexpectedEOF ExpectedOpeningObjectChar ExpectedOpeningQuoteChar ExpectedOpeningArrayChar ExpectedClosingArrayChar ExpectedComma ExpectedColon ExpectedNewline InvalidChar InvalidNumber InvalidUTF16

@noinline function invalid(error, buf, pos::Int, T)
    # compute which line the error falls on by counting “\n” bytes up to pos
    cus = buf isa AbstractString ? codeunits(buf) : buf
    line_no = count(b -> b == UInt8('\n'), view(cus, 1:pos)) + 1

    li = pos > 20 ? pos - 9 : 1
    ri = min(sizeof(cus), pos + 20)
    snippet_bytes = cus[li:ri]
    snippet_pos = pos - li + 1
    snippet = String(copy(snippet_bytes))
    # find error position; if snippet has multi-codepoint chars,
    # translate pos to char index, accounting for textwidth of char
    erri = 1
    st = iterate(snippet)
    while st !== nothing
        c, i = st
        i > snippet_pos && break
        erri += textwidth(c)
        st = iterate(snippet, i)
    end
    snippet = replace(snippet, r"[\b\f\n\r\t]" => " ")
    # we call @invoke here to avoid --trim verify errors
    caret = @invoke(repeat(" "::String, (erri + 2)::Integer)) * "^"
    msg = """
    invalid JSON at byte position $(pos) (line $line_no) parsing type $T: $error
    $snippet$(error == UnexpectedEOF ? " <EOF>" : "...")
    $caret
    """
    throw(ArgumentError(msg))
end

include("utils.jl")
include("object.jl")

# default object type for parse
const DEFAULT_OBJECT_TYPE = Object{String, Any}

"""
    JSON.JSONText

Wrapper around a string containing JSON data.
Can be used to insert raw JSON in JSON output, like:
```julia
json(JSONText("{\"key\": \"value\"}"))
```
This will output the JSON as-is, without escaping.
Note that no check is done to ensure that the JSON is valid.

Can also be used to read "raw JSON" when parsing, meaning
no specialized structure (JSON.Object, Vector{Any}, etc.) is created.
Example:
```julia
x = JSON.parse("[1,2,3]", JSONText)
# x.value == "[1,2,3]"
```
"""
struct JSONText
    value::String
end

include("lazy.jl")
include("parse.jl")
include("write.jl")

"""
    JSON.isvalidjson(json) -> Bool

Check if the given JSON is valid.
This function will return `true` if the JSON is valid, and `false` otherwise.
Inputs can be a string, a vector of bytes, or an IO stream, the same inputs
as supported for `JSON.lazy` and `JSON.parse`.
"""
function isvalidjson end

isvalidjson(io::Union{IO, Base.AbstractCmd}; kw...) = isvalidjson(Base.read(io); kw...)

isvalidjson(buf::Union{AbstractVector{UInt8}, AbstractString}; kw...) =
    isvalidjson(lazy(buf; kw...))

function isvalidjson(x::LazyValue)
    try
        skip(x)
        return true
    catch
        return false
    end
end

# convenience aliases for pre-1.0 JSON compat
print(io::IO, obj, indent=nothing) = json(io, obj; pretty=something(indent, 0))
print(a, indent=nothing) = print(stdout, a, indent)
@doc (@doc json) print

"""
    JSON.write_json(Vector{UInt8}, x; kw...)::Vector{UInt8}
    JSON.write_json(io::IO, x; kw...)
    JSON.write_json(filename::AbstractString, x; kw...)

Serialize `x` to JSON format. This function provides the same functionality as [`JSON.json`](@ref)

The first method returns the JSON output as a `Vector{UInt8}`.
The second method writes JSON output to an `IO` object.
The third method writes JSON output to a file specified by `filename` which will
be created if it does not exist yet or overwritten if it does exist.

This function is provided for backward compatibility when upgrading from 
older versions of JSON.jl where the `json` function signature differed.
For new code, prefer using [`JSON.json`](@ref) directly.

See [`JSON.json`](@ref) for detailed documentation of all keyword arguments and more examples.

# Examples
```julia
# Write to IO
io = IOBuffer()
JSON.write_json(io, Dict("key" => "value"))
String(take!(io))  # "{\"key\":\"value\"}"

# Write to file
JSON.write_json("output.json", [1, 2, 3])

# Get as bytes
bytes = JSON.write_json(Vector{UInt8}, Dict("hello" => "world"))
String(bytes)  # "{\"hello\":\"world\"}"
```
"""
function write_json end

function write_json(::Type{Vector{UInt8}}, x; pretty::Union{Integer,Bool}=false, kw...)
    opts = WriteOptions(; pretty=pretty === true ? 2 : Int(pretty), kw...)
    _write_options_check(opts)
    y = StructUtils.lower(opts.style, x)
    buf = Vector{UInt8}(undef, sizeguess(y))
    pos = json!(buf, 1, y, opts, Any[y], nothing)
    resize!(buf, pos - 1)
    return buf
end

function write_json(io::IO, x; kw...)
    json(io, x; kw...)
end

function write_json(filename::AbstractString, x; kw...)
    open(filename; write=true) do io
        write_json(io, x; kw...)
    end
end

@compile_workload begin
    x = JSON.parse("{\"a\": 1, \"b\": null, \"c\": true, \"d\": false, \"e\": \"\", \"f\": [1,null,true], \"g\": {\"key\": \"value\"}}")
    json = JSON.json(x)
    isvalidjson(json)
end


end # module
