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
        :isvalidjson, :DuplicateKeyError,
        :json, :print,
        :lower, :lift,
        :omit_null, :omit_empty,
        :Object, :Null, :Omit, :JSONStyle,
    ))
end

"""
    JSON.DuplicateKeyError

Error thrown when `duplicate_keys=:error` encounters a repeated object key.
`key` is the decoded JSON key and `position` is its one-based byte position.
"""
struct DuplicateKeyError <: Exception
    key::String
    position::Int
end

function Base.showerror(io::IO, err::DuplicateKeyError)
    Base.print(io, "duplicate JSON object key ", repr(err.key), " at byte position ", err.position)
end

@enum Error InvalidJSON UnexpectedEOF ExpectedOpeningObjectChar ExpectedOpeningQuoteChar ExpectedOpeningArrayChar ExpectedClosingArrayChar ExpectedComma ExpectedColon ExpectedNewline InvalidChar InvalidNumber InvalidUTF16

@generated _typename(::Type{T}) where {T} = QuoteNode(string(T))

@noinline invalid(error, buf, pos::Int, ::Type{T}) where {T} =
    _invalid(error, buf, pos, _typename(T))
@noinline invalid(error, buf, pos::Int, typename::String) =
    _invalid(error, buf, pos, typename)

@noinline function _invalid(error, buf, pos::Int, typename::String)
    # compute which line the error falls on by counting “\n” bytes up to pos
    cus = buf isa AbstractString ? codeunits(buf) : buf
    # `pos` can point one byte past the end: UnexpectedEOF is reported at the
    # position we wanted to read, so every input ending mid-token lands here
    # with pos == sizeof(cus) + 1. Clamp before slicing, or building the error
    # message throws BoundsError instead of the ArgumentError we mean to raise.
    n = sizeof(cus)
    line_no = count(b -> b == UInt8('\n'), view(cus, 1:min(pos, n))) + 1

    li = pos > 20 ? min(pos - 9, n) : 1
    ri = min(n, pos + 20)
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
    invalid JSON at byte position $(pos) (line $line_no) parsing type $(typename): $error
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

# typed-parse workload struct: exercising one struct with the common field
# shapes caches the shared make/lift/array-chain inference in this package's
# image, so downstream typed parses hit those caches instead of re-inferring
# (which also keeps `juliac --trim` edge inference precise on nested families)
struct _WorkloadInner
    x::Int
    y::Float64
end
struct _Workload
    item::Union{Nothing,_WorkloadInner}
    items::Vector{_WorkloadInner}
    tags::Vector{String}
    note::Union{Nothing,String}
end

@compile_workload begin
    x = JSON.parse("{\"a\": 1, \"b\": null, \"c\": true, \"d\": false, \"e\": \"\", \"f\": [1,null,true], \"g\": {\"key\": \"value\"}}")
    json = JSON.json(x)
    isvalidjson(json)
    JSON.parse(
        "{\"item\":{\"x\":1,\"y\":2.0},\"items\":[{\"x\":3,\"y\":4.0}],\"tags\":[\"p\"],\"note\":null}",
        _Workload,
    )
end


end # module
