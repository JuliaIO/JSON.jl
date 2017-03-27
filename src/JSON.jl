isdefined(Base, :__precompile__) && __precompile__()

module JSON

using Compat

export json # returns a compact (or indented) JSON representation as a string

include("Common.jl")

# Parser modules
include("Parser.jl")

# Writer modules
include("Serializations.jl")

using .Common
import .Parser.parse
import .Serializations.StandardSerialization

"""
Internal JSON.jl implementation detail; do not depend on this type.

A JSON primitive that wraps around any composite type to enable `Dict`-like
serialization.
"""
immutable CompositeTypeWrapper{T}
    wrapped::T
    fns::Vector{Symbol}
end
CompositeTypeWrapper(x) = CompositeTypeWrapper(x, fieldnames(x))

const JSONPrimitive = Union{
        Associative, Tuple, AbstractArray, AbstractString, Integer,
        AbstractFloat, Void, CompositeTypeWrapper}

"""
Return a value of a JSON-encodable primitive type that `x` should be lowered
into before encoding as JSON. Supported types are: `Associative` to JSON
objects, `Tuple` and `AbstractVector` to JSON arrays, `AbstractArray` to nested
JSON arrays, `AbstractString` to JSON string, `Integer` and `AbstractFloat` to
JSON number, `Bool` to JSON boolean, and `Void` to JSON null.

Extensions of this method should preserve the property that the return value is
one of the aforementioned types. If first lowering to some intermediate type is
required, then extensions should call `lower` before returning a value.

Note that the return value need not be *recursively* lowered—this function may
for instance return an `AbstractArray{Any, 1}` whose elements are not JSON
primitives.
"""
function lower(a)
    if nfields(typeof(a)) > 0
        CompositeTypeWrapper(a)
    else
        error("Cannot serialize type $(typeof(a))")
    end
end

if isdefined(Base, :Dates)
    lower(s::Base.Dates.TimeType) = string(s)
end

if VERSION < v"0.5.0-dev+2396"
    lower(f::Function) = "function at $(f.fptr)"
end

lower(c::Char) = string(c)
lower(d::Type) = string(d)
lower(m::Module) = throw(ArgumentError("cannot serialize Module $m as JSON"))
lower(x::Real) = Float64(x)

"""
Abstract supertype of all JSON and JSON-like structural writer contexts.
"""
@compat abstract type StructuralContext <: IO end

"""
Internal implementation detail.

A JSON structural context around an `IO` object. Structural writer contexts
define the behaviour of serializing JSON structural objects, such as objects,
arrays, and strings to JSON. The translation of Julia types to JSON structural
objects is not handled by a `JSONContext`, but by a `Serialization` wrapper
around it. Abstract supertype of `PrettyContext` and `CompactContext`. Data can
be written to a JSON context in the usual way, but often higher-level operations
such as `begin_array` or `begin_object` are preferred to directly writing bytes
to the stream.
"""
@compat abstract type JSONContext <: StructuralContext end

"""
Internal implementation detail.

Keeps track of the current location in the array or object, which winds and
unwinds during serialization.
"""
type PrettyContext{T<:IO} <: JSONContext
    io::T
    step::Int     # number of spaces to step
    state::Int    # number of steps at present
    first::Bool   # whether an object/array was just started
end
PrettyContext(io::IO, step) = PrettyContext(io, step, 0, false)

"""
Internal implementation detail.

For compact printing, which in JSON is fully recursive.
"""
type CompactContext{T<:IO} <: JSONContext
    io::T
    first::Bool
end
CompactContext(io::IO) = CompactContext(io, false)

"""
Internal implementation detail.

Implements an IO context safe for printing into JSON strings.
"""
immutable StringContext{T<:IO} <: IO
    io::T
end

# These make defining additional methods on `show_json` easier.
const CS = Serializations.CommonSerialization
const SC = StructuralContext

# Low-level direct access
Base.write(io::JSONContext, byte::UInt8) = write(io.io, byte)
Base.write(io::StringContext, byte::UInt8) =
    write(io.io, ESCAPED_ARRAY[byte + 0x01])
#= turn on if there's a performance benefit
write(io::StringContext, char::Char) =
    char <= '\x7f' ? write(io, ESCAPED_ARRAY[@compat UInt8(c) + 0x01]) :
                     Base.print(io, c)
=#

"""
Internal implementation detail.

If appropriate, write a newline, then indent the IO by the appropriate number of
spaces. Otherwise, do nothing.
"""
@inline function indent(io::PrettyContext)
    write(io, NEWLINE)
    for _ in 1:io.state
        write(io, SPACE)
    end
end
@inline indent(io::CompactContext) = nothing

"""
Internal implementation detail.

Write a colon, followed by a space if appropriate.
"""
@inline separate(io::PrettyContext) = write(io, SEPARATOR, SPACE)
@inline separate(io::CompactContext) = write(io, SEPARATOR)

"""
Internal implementation detail.

If this is not the first item written in a collection, write a comma in the IO.
Otherwise, do not write a comma, but set a flag that the first element has been
written already.
"""
@inline function delimit(io::JSONContext)
    if !io.first
        write(io, DELIMITER)
    end
    io.first = false
end

for kind in ("object", "array")
    beginfn = Symbol("begin_", kind)
    beginsym = Symbol(uppercase(kind), "_BEGIN")
    endfn = Symbol("end_", kind)
    endsym = Symbol(uppercase(kind), "_END")
    # Begin and end objects
    @eval function $beginfn(io::PrettyContext)
        write(io, $beginsym)
        io.state += io.step
        io.first = true
    end
    @eval $beginfn(io::CompactContext) = (write(io, $beginsym); io.first = true)
    @eval function $endfn(io::PrettyContext)
        io.state -= io.step
        if !io.first
            indent(io)
        end
        write(io, $endsym)
        io.first = false
    end
    @eval $endfn(io::CompactContext) = (write(io, $endsym); io.first = false)
end

function show_string(io::IO, x)
    write(io, STRING_DELIM)
    Base.print(StringContext(io), x)
    write(io, STRING_DELIM)
end

show_null(io::IO) = Base.print(io, "null")

function show_element(io::JSONContext, s, x)
    delimit(io)
    indent(io)
    show_json(io, s, x)
end

function show_key(io::JSONContext, k)
    delimit(io)
    indent(io)
    show_string(io, k)
    separate(io)
end

function show_pair(io::JSONContext, s, k, v)
    show_key(io, k)
    show_json(io, s, v)
end
show_pair(io::JSONContext, s, kv) = show_pair(io, s, first(kv), last(kv))

# Default serialization rules for CommonSerialization (CS)
show_json(io::SC, ::CS, x::Union{AbstractString, Symbol}) = show_string(io, x)

function show_json(io::SC, s::CS, x::Union{Integer, AbstractFloat})
    # workaround for issue in Julia 0.5.x where Float32 values are printed as
    # 3.4f-5 instead of 3.4e-5
    @static if v"0.5-" <= VERSION < v"0.6.0-dev.788"
        if isa(x, Float32)
            return show_json(io, s, Float64(x))
        end
    end
    if isfinite(x)
        Base.print(io, x)
    else
        show_null(io)
    end
end

show_json(io::SC, ::CS, ::Void) = show_null(io)

function show_json(io::SC, s::CS, a::Nullable)
    if isnull(a)
        Base.print(io, "null")
    else
        show_json(io, s, get(a))
    end
end

function show_json(io::SC, s::CS, a::Associative)
    begin_object(io)
    for kv in a
        show_pair(io, s, kv)
    end
    end_object(io)
end

function show_json(io::SC, s::CS, x::CompositeTypeWrapper)
    begin_object(io)
    fns = x.fns
    for k in 1:length(fns)
        show_pair(io, s, fns[k], getfield(x.wrapped, k))
    end
    end_object(io)
end

function show_json(io::SC, s::CS, x::Union{AbstractVector, Tuple})
    begin_array(io)
    for elt in x
        show_element(io, s, elt)
    end
    end_array(io)
end

"""
Serialize a multidimensional array to JSON in column-major format. That is,
`json([1 2 3; 4 5 6]) == "[[1,4],[2,5],[3,6]]"`.
"""
function show_json{T,n}(io::SC, s::CS, A::AbstractArray{T,n})
    begin_array(io)
    newdims = ntuple(_ -> :, Val{n - 1})
    for j in 1:size(A, n)
        show_element(io, s, Compat.view(A, newdims..., j))
    end
    end_array(io)
end

show_json(io::SC, s::CS, a) = show_json(io, s, lower(a))

# Fallback show_json for non-SC types
"""
Serialize Julia object `obj` to IO `io` using the behaviour described by `s`. If
`indent` is provided, then the JSON will be pretty-printed; otherwise it will be
printed on one line. If pretty-printing is enabled, then a trailing newline will
be printed; otherwise there will be no trailing newline.
"""
function show_json(io::IO, s::Serializations.Serialization, obj; indent=nothing)
    ctx = indent === nothing ? CompactContext(io) : PrettyContext(io, indent)
    show_json(ctx, s, obj)
    if indent !== nothing
        println(io)
    end
end

print(io::IO, obj, indent) =
    show_json(io, StandardSerialization(), obj; indent=indent)
print(io::IO, obj) = show_json(io, StandardSerialization(), obj)

print(a, indent) = print(STDOUT, a, indent)
print(a) = print(STDOUT, a)

json(a) = sprint(JSON.print, a)
json(a, indent) = sprint(JSON.print, a, indent)

function parsefile{T<:Associative}(filename::AbstractString; dicttype::Type{T}=Dict{Compat.UTF8String, Any}, use_mmap=true)
    sz = filesize(filename)
    open(filename) do io
        s = use_mmap ? Compat.UTF8String(Mmap.mmap(io, Vector{UInt8}, sz)) : readstring(io)
        JSON.parse(s; dicttype=dicttype)
    end
end

end # module
