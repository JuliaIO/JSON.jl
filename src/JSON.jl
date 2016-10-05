isdefined(Base, :__precompile__) && __precompile__()

module JSON

using Compat

export json # returns a compact (or indented) JSON representation as a string

include("Parser.jl")
include("bytes.jl")

import .Parser.parse

# These are temporary ways to bypass excess memory allocation
# They can be removed once types define their own serialization behaviour again
"Internal JSON.jl implementation detail; do not depend on this type."
immutable AssociativeWrapper{T} <: Associative{Symbol, Any}
    wrapped::T
    fns::Array{Symbol, 1}
end
AssociativeWrapper(x) = AssociativeWrapper(x, fieldnames(x))

typealias JSONPrimitive Union{
        Associative, Tuple, AbstractArray, AbstractString, Integer,
        AbstractFloat, Bool, Void}

Base.getindex(w::AssociativeWrapper, s::Symbol) = getfield(w.wrapped, s)
Base.keys(w::AssociativeWrapper) = w.fns
Base.length(w::AssociativeWrapper) = length(w.fns)

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
lower(a) = AssociativeWrapper(a)
lower(a::JSONPrimitive) = a

if isdefined(Base, :Dates)
    lower(s::Base.Dates.TimeType) = string(s)
end

lower(s::Symbol) = string(s)

if VERSION < v"0.5.0-dev+2396"
    lower(f::Function) = "function at $(f.fptr)"
end

lower(c::Char) = string(c)
lower(d::DataType) = string(d)
lower(m::Module) = throw(ArgumentError("cannot serialize Module $m as JSON"))
lower(x::Real) = Float64(x)

const INDENT=true
const NOINDENT=false
const REVERSE_ESCAPES = Dict(map(reverse, ESCAPES))
const escaped = Array(Vector{UInt8}, 256)
for c in 0x00:0xFF
    escaped[c + 1] = if c == SOLIDUS
        [SOLIDUS]  # don't escape this one
    elseif c ≥ 0x80
        [c]  # UTF-8 character copied verbatim
    elseif haskey(REVERSE_ESCAPES, c)
        [BACKSLASH, REVERSE_ESCAPES[c]]
    elseif iscntrl(Char(c)) || !isprint(Char(c))
        UInt8[BACKSLASH, LATIN_U, hex(c, 4)...]
    else
        [c]
    end
end

type State{I}
    indentstep::Int
    indentlen::Int
    prefix::AbstractString
    otype::Array{Bool, 1}
    State(indentstep::Int) = new(indentstep,
                                 0,
                                 "",
                                 Bool[])
end
State(indentstep::Int=0) = State{indentstep>0}(indentstep)

function set_state(state::State{INDENT}, operate::Int)
    state.indentlen += state.indentstep * operate
    state.prefix = " "^state.indentlen
end

set_state(state::State{NOINDENT}, operate::Int) = nothing

suffix(::State{INDENT})   = "\n"
suffix(::State{NOINDENT}) = ""

prefix(s::State{INDENT})  = s.prefix
prefix(::State{NOINDENT}) = ""

separator(::State{INDENT})   = ": "
separator(::State{NOINDENT}) = ":"

# short hand for printing suffix then prefix
printsp(io::IO, state::State{INDENT}) = Base.print(io, suffix(state), prefix(state))
printsp(io::IO, state::State{NOINDENT}) = nothing

function start_object(io::IO, state::State{INDENT}, is_dict::Bool)
    push!(state.otype, is_dict)
    Base.print(io, is_dict ? "{": "[", suffix(state))
    set_state(state, 1)
end

function start_object(io::IO, state::State{NOINDENT}, is_dict::Bool)
    Base.print(io, is_dict ? "{": "[")
end

function end_object(io::IO, state::State{INDENT}, is_dict::Bool)
    set_state(state, -1)
    pop!(state.otype)
    printsp(io, state)
    Base.print(io, is_dict ? "}": "]")
end

function end_object(io::IO, state::State{NOINDENT}, is_dict::Bool)
    Base.print(io, is_dict ? "}": "]")
end

function print_escaped(io::IO, s::AbstractString)
    @inbounds for c in s
        c <= '\x7f' ? Base.write(io, escaped[UInt8(c) + 0x01]) :
                      Base.print(io, c) #JSON is UTF8 encoded
    end
end

function print_escaped(io::IO, s::Compat.UTF8String)
    @inbounds for c in s.data
        Base.write(io, escaped[c + 0x01])
    end
end

function _writejson(io::IO, state::State, s::AbstractString)
    Base.print(io, '"')
    JSON.print_escaped(io, s)
    Base.print(io, '"')
end

# workaround for issue in Julia 0.5.x where Float32 values are printed as
# 3.4f-5 instead of 3.4e-5
if v"0.5-" <= VERSION < v"0.6.0-dev.788"
    _writejson(io::IO, state::State, s::Float32) = _writejson(io, state, Float64(s))
end

function _writejson(io::IO, state::State, s::Union{Integer, AbstractFloat})
    if isnan(s) || isinf(s)
        Base.print(io, "null")
    else
        Base.print(io, s)
    end
end

function _writejson(io::IO, state::State, n::Void)
    Base.print(io, "null")
end

function _writejson(io::IO, state::State, a::Nullable)
    if isnull(a)
        Base.print(io, "null")
    else
        _writejson(io, state, get(a))
    end
end

function _writejson(io::IO, state::State, a::Associative)
    if length(a) == 0
        Base.print(io, "{}")
        return
    end
    start_object(io, state, true)
    first = true
    for key in keys(a)
        first ? (first = false) : Base.print(io, ",", suffix(state))
        Base.print(io, prefix(state))
        _writejson(io, state, string(key))
        Base.print(io, separator(state))
        _writejson(io, state, a[key])
    end
    end_object(io, state, true)
end

function _writejson(io::IO, state::State, a::Union{AbstractVector,Tuple})
    if length(a) == 0
        Base.print(io, "[]")
        return
    end
    start_object(io, state, false)
    Base.print(io, prefix(state))
    i = start(a)
    !done(a,i) && ((x, i) = next(a, i); _writejson(io, state, x); )

    while !done(a,i)
        (x, i) = next(a, i)
        Base.print(io, ",")
        printsp(io, state)
        _writejson(io, state, x)
    end
    end_object(io, state, false)
end

function _writejson(io::IO, state::State, a)
    # FIXME: This fallback is harming performance substantially.
    # Remove this fallback when _print removed.
    if applicable(_print, io, state, a)
        Base.depwarn(
            "Overloads to `_print` are deprecated; extend `lower` instead.",
            :_print)
        _print(io, state, a)
    else
        _writejson(io, state, lower(a))
    end
end

# Note: Arrays are printed in COLUMN MAJOR format.
# i.e. json([1 2 3; 4 5 6]) == "[[1,4],[2,5],[3,6]]"
function _writejson{T, N}(io::IO, state::State, a::AbstractArray{T, N})
    lengthN = size(a, N)
    if lengthN > 0
        start_object(io, state, false)
        if VERSION <= v"0.3"
            newdims = ntuple(N - 1, i -> 1:size(a, i))
        else
            newdims = ntuple(i -> 1:size(a, i), N - 1)
        end
        Base.print(io, prefix(state))
        _writejson(io, state, Compat.view(a, newdims..., 1))

        for j in 2:lengthN
            Base.print(io, ",")
            printsp(io, state)
            _writejson(io, state, Compat.view(a, newdims..., j))
        end
        end_object(io, state, false)
    else
        Base.print(io, "[]")
    end
end

# this is _print() instead of _print because we need to support v0.3
# FIXME: drop the parentheses when v0.3 support dropped
"Deprecated way to overload JSON printing behaviour. Use `lower` instead."
function _print(io::IO, s::State, a::JSONPrimitive)
    Base.depwarn(
        "Do not call internal function `JSON._print`; use `JSON.print`",
        :_print)
    _writejson(io, s, a)
end

function print(io::IO, a, indent=0)
    _writejson(io, State(indent), a)
    if indent > 0
        Base.print(io, "\n")
    end
end

function print(a, indent=0)
    _writejson(STDOUT, State(indent), a)
    if indent > 0
        println()
    end
end

json(a, indent=0) = sprint(JSON.print, a, indent)

function parsefile{T<:Associative}(filename::AbstractString; dicttype::Type{T}=Dict{Compat.UTF8String, Any}, use_mmap=true)
    sz = filesize(filename)
    open(filename) do io
        s = use_mmap ? Compat.UTF8String(Mmap.mmap(io, Vector{UInt8}, sz)) : readstring(io)
        JSON.parse(s; dicttype=dicttype)
    end
end

end # module
