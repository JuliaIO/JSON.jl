module JSON

# stdlibs
using Dates, UUIDs, Logging
# external dependencies
using PrecompileTools, Parsers, StructUtils

# reexport some StructUtils macros
import StructUtils: @noarg, @kwarg, @defaults, @tags, @choosetype, @nonstruct, lower, lift
export JSONText, StructUtils, @noarg, @kwarg, @defaults, @tags, @choosetype, @nonstruct, @omit_null, @omit_empty

# Mark documented API as `public` on Julia versions that support it (>= 1.11).
# Wrapped in `eval(Expr(...))` because `public` is a parse error on older versions.
@static if VERSION >= v"1.11"
    eval(Expr(:public,
        :parse, :parse!, :parsefile, :parsefile!,
        :lazy, :lazyfile, :LazyValue,
        :isvalidjson,
        :json, :print,
        :lower, :lift,
        :omit_null, :omit_empty,
        :Object, :Null, :Omit, :JSONStyle,
    ))
end

@enum Error InvalidJSON UnexpectedEOF ExpectedOpeningObjectChar ExpectedOpeningQuoteChar ExpectedOpeningArrayChar ExpectedClosingArrayChar ExpectedComma ExpectedColon ExpectedNewline InvalidChar InvalidNumber InvalidUTF16

@noinline function invalid(error, buf, pos::Int, @nospecialize(T))
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
    # the type renders via an isa ladder with per-branch typeasserts:
    # interpolating the type object infers show machinery per target type (a
    # large per-type TTFX tax) and is dynamic under --trim now that this
    # helper is @nospecialize
    tname = _typenamestr(T)
    msg = """
    invalid JSON at byte position $(pos) (line $line_no) parsing type $(tname): $error
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
include("tier0.jl")
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

function isvalidjson(buf::Union{AbstractVector{UInt8}, AbstractString}; kw...)
    try
        return isvalidjson(lazy(buf; kw...))
    catch
        return false
    end
end

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

"See [`json`](@ref)."
print

function __init__()
    # :hot-annotated struct definitions in downstream packages fire this hook
    # during their precompilation, compiling the typed parse/write paths for
    # each annotated type into that package's image
    StructUtils.register_hot_hook!(_hot_json_hook)
    return nothing
end

# exercises the untyped engine plus the tier-0 typed default (engine → field
# table interpreter), so a downstream user's first typed parse of any
# eligible struct costs a table build instead of compiling a descent
@kwarg struct _EngineWorkload
    a::Int = 0
    b::Union{String,Nothing} = nothing
    c::Vector{Float64} = Float64[]
end

@compile_workload begin
    x = JSON.parse("{\"a\": 1, \"b\": null, \"c\": true, \"d\": false, \"e\": \"\", \"f\": [1,null,true], \"g\": {\"key\": \"value\"}}")
    json = JSON.json(x)
    isvalidjson(json)
    JSON.parse("{\"a\": 1, \"b\": \"x\", \"c\": [1.5], \"z\": null}", _EngineWorkload)
end


end # module
