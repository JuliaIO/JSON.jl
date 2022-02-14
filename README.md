# JSON.jl

This package provides for parsing and printing JSON in pure Julia.

[![Build Status](https://github.com/JuliaIO/JSON.jl/workflows/CI/badge.svg)](https://github.com/JuliaIO/JSON.jl/actions/workflows/CI.yml?query=branch%3Amaster)
[![codecov.io](http://codecov.io/github/JuliaIO/JSON.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaIO/JSON.jl?branch=master)

## Installation

Type `] add JSON` and then hit ⏎ Return at the REPL. You should see `pkg> add JSON`.

## Basic Usage

```julia
import JSON

# JSON.parse - string or stream to Julia data structures
s = "{\"a_number\" : 5.0, \"an_array\" : [\"string\", 9]}"
j = JSON.parse(s)
#  Dict{AbstractString,Any} with 2 entries:
#    "an_array" => {"string",9}
#    "a_number" => 5.0

# JSON.json - Julia data structures to a string
JSON.json([2,3])
#  "[2,3]"
JSON.json(j)
#  "{\"an_array\":[\"string\",9],\"a_number\":5.0}"
```

## Documentation

```julia
JSON.print(io::IO, s::AbstractString)
JSON.print(io::IO, s::Union{Integer, AbstractFloat})
JSON.print(io::IO, n::Nothing)
JSON.print(io::IO, b::Bool)
JSON.print(io::IO, a::AbstractDict)
JSON.print(io::IO, v::AbstractVector)
JSON.print(io::IO, v::Array)
```

Writes a compact (no extra whitespace or indentation) JSON representation
to the supplied IO.

```julia
JSON.print(a::AbstractDict, indent)
JSON.print(io::IO, a::AbstractDict, indent)
```

Writes a JSON representation with newlines, and indentation if specified. Non-zero `indent` will be applied recursively to nested elements.


```julia
json(a::Any)
```

Returns a compact JSON representation as an `AbstractString`.

```julia
JSON.parse(s::AbstractString; dicttype=Dict, inttype=Int64)
JSON.parse(io::IO; dicttype=Dict, inttype=Int64)
JSON.parsefile(filename::AbstractString; dicttype=Dict, inttype=Int64, use_mmap=true)
```

Parses a JSON `AbstractString` or IO stream into a nested `Array` or `Dict`.

The `dicttype` indicates the dictionary type (`<: Associative`), or a function that
returns an instance of a dictionary type,
that JSON objects are parsed to.  It defaults to `Dict` (the built-in Julia
dictionary), but a different type can be passed for additional functionality.
For example, if you `import DataStructures`
(assuming the [DataStructures
package](https://github.com/JuliaLang/DataStructures.jl) is
installed)

 - you can pass `dicttype=DataStructures.OrderedDict` to maintain the insertion order
   of the items in the object;
 - or you can pass `()->DefaultDict{String,Any}(Missing)` to having any non-found keys
   return `missing` when you index the result.


The `inttype` argument controls how integers are parsed.  If a number in a JSON
file is recognized to be an integer, it is parsed as one; otherwise it is parsed
as a `Float64`.  The `inttype` defaults to `Int64`, but, for example, if you know
that your integer numbers are all small and want to save space, you can pass
`inttype=Int32`.  Alternatively, if your JSON input has integers which are too large
for Int64, you can pass `inttype=Int128` or `inttype=BigInt`.  `inttype` can be any
subtype of `Real`.

```julia
JSONText(s::AbstractString)
```
A wrapper around a Julia string representing JSON-formatted text,
which is inserted *as-is* in the JSON output of `JSON.print` and `JSON.json`.

```julia
JSON.lower(p::Point2D) = [p.x, p.y]
```

Define a custom serialization rule for a particular data type. Must return a
value that can be directly serialized; see help for more details.

### Customizing JSON

Users may find the default behaviour of JSON inappropriate for their use case. In
such cases, JSON provides two mechanisms for users to customize serialization. The
first method, `JSON.Writer.StructuralContext`, is used to customize the cosmetic
properties of the serialized JSON. (For example, the default pretty printing vs.
compact printing is supported by provided two different `StructuralContext`s.)
Examples of applications for which `StructuralContext` is appropriate include:
particular formatting demands for JSON (maybe not in compliance with the JSON
standard) or JSON-like formats with different syntax.

The second method, `JSON.Serializations.Serialization`, is used to control the
translation of Julia objects into JSON serialization instructions. In most cases,
writing a method for `JSON.lower` (as mentioned above) is sufficient to define
JSON serializations for user-defined objects. However, this is not appropriate for
overriding or deleting predefined serializations (since that would globally affect
users of the `JSON` module and is an instance of dangerous
[type piracy](https://docs.julialang.org/en/v1/manual/style-guide/index.html#Avoid-type-piracy-1)).
For these use-cases, users should define a custom instance of `Serialization`.
An example of an application for this use case includes: a commonly requested
extension to JSON which serializes float NaN and infinite values as `NaN` or `Inf`,
in contravention of the JSON standard.

Both methods are controlled by the `JSON.show_json` function, which has the following
signature:

```
JSON.show_json(io::StructuralContext, serialization::Serialization, object)
```

which is expected to write to `io` in a way appropriate based on the rules of
`Serialization`, but here `io` is usually (but not required to be) handled in a
higher-level manner than a raw `IO` object would ordinarily be.

#### StructuralContext

To define a new `StructuralContext`, the following boilerplate is recommended:

```julia
import JSON.Writer.StructuralContext
[mutable] struct MyContext <: StructuralContext
    io::IO
    [ ... additional state / settings for context goes here ... ]
end
```

If your structural context is going to be very similar to the existing JSON
contexts, it is also possible to instead subtype the abstract subtype
`JSONContext` of `StructuralContext`. If this is the case, an `io::IO` field (as
above) is preferred, although the default implementation will only use this
for `write`, so replacing that method is enough to avoid this requirement.

The following methods should be defined for your context, regardless of whether it
subtypes `JSONContext` or `StructuralContext` directly. If some of these methods
are omitted, then `CommonSerialization` cannot be generally used with this context.

```
# called when the next object in a vector or next pair of a dict is to be written
# (requiring a newline and indent for some contexts)
# can do nothing if the context need not support indenting
JSON.Writer.indent(io::MyContext)

# called for vectors/dicts to separate items, usually writes ","
# unless this is the first element in a JSON array
# (default implementation for JSONContext exists, but requires a mutable bool
#  `first` field, and this is an implementation detail not to be relied on; 
#  to define own or delegate explicitly)
JSON.Writer.delimit(io::MyContext)

# called for dicts to separate key and value, usually writes ": "
JSON.Writer.separate(io::MyContext)

# called to indicate start and end of a vector
JSON.Writer.begin_array(io::MyContext)
JSON.Writer.end_array(io::MyContext)

# called to indicate start and end of a dict
JSON.Writer.begin_object(io::MyContext)
JSON.Writer.end_object(io::MyContext)
```

For the following methods, `JSONContext` provides a default implementation,
but it can be specialized. For `StructuralContext`s which are not
`JSONContext`s, the `JSONContext` defaults are not appropriate and so are
not available.

```julia
# directly write a specific byte (if supported)
# default implementation writes to underlying `.io` field
# note that this enables JSONContext to act as any `io::IO`,
# i.e. one can use `print`, `show`, etc.
Base.write(io::MyContext, byte::UInt8)

# write "null"
# default implementation writes to underlying `.io` field
JSON.Writer.show_null(io::MyContext)

# write an object or string in a manner safe for JSON string
# default implementation calls `print` but escapes each byte as appropriate
# and adds double quotes around the content of `elt`
JSON.Writer.show_string(io::MyContext, elt)

# write a new element of JSON array
# default implementation calls delimit, then indent, then show_json
JSON.Writer.show_element(io::MyContext, elt)

# write a key for a JSON object
# default implementation calls delimit, then indent, then show_string,
# then seperate
JSON.Writer.show_key(io::MyContext, elt)

# write a key-value pair for a JSON object
# default implementation calls show key, then show_json
JSON.Writer.show_pair(io::MyContext, s::Serialization, key, value)
```

What follows is an example of a `JSONContext` subtype which is very similar
to the default context, but which uses `None` instead of `null` for JSON nulls,
which is then generally compatible with Python object literal notation (PYON). It
wraps a default `JSONContext` to delegate all the required methods to. Since
the wrapped context already has a `.io`, this object does not need to include
an `.io` field, and so the `write` method must also be delegated, since the default
is not appropriate. The only other specialization needed is `show_null`.

```julia
import JSON.Writer
import JSON.Writer.JSONContext
mutable struct PYONContext <: JSONContext
    underlying::JSONContext
end

for delegate in [:indent,
                 :delimit,
                 :separate,
                 :begin_array,
                 :end_array,
                 :begin_object,
                 :end_object]
    @eval JSON.Writer.$delegate(io::PYONContext) = JSON.Writer.$delegate(io.underlying)
end
Base.write(io::PYONContext, byte::UInt8) = write(io.underlying, byte)

JSON.Writer.show_null(io::PYONContext) = print(io, "None")
pyonprint(io::IO, obj) = let io = PYONContext(JSON.Writer.PrettyContext(io, 4))
    JSON.print(io, obj)
    return
end
```

The usage of this `pyonprint` function is as any other `print` function, e.g.

```julia
julia> pyonprint(stdout, [1, 2, nothing])
[
    1,
    2,
    None
]

julia> sprint(pyonprint, missing)
"None"
```

#### Serialization

For cases where the JSON cosmetics are unimportant, but how objects are converted into their
JSON equivalents (arrays, objects, numbers, etc.) need to be changed, the appropriate
abstraction is `Serialization`. A `Serialization` instance is used as the second argument in
`show_json`. Thus, specializing `show_json` for custom `Serialization` instances enables
either creating more restrictive or different ways to convert objects into JSON.

The default serialization is called `JSON.Serializations.StandardSerialization`, which is a
subtype of `CommonSerialization`. Methods of `show_json` are not added to
`StandardSerialization`, but rather to `CommonSerialization`, by both `JSON` and by
other packages for their own types. The `lower` functionality is also specific to
`CommonSerialization`. Therefore, to create a serialization instance that inherits from and
may extend or override parts of the standard serialization, it suffices to define a new
serialization subtyping `CommonSerialization`. In the example below, the new serialization
is the same as `StandardSerialization` except that numbers are serialized with an additional
type tag.

```julia
import JSON.Serializations: CommonSerialization, StandardSerialization
import JSON.Writer: StructuralContext, show_json
struct TaggedNumberSerialization <: CommonSerialization end

tag(f::Real) = Dict(:type => string(typeof(f)), :value => f)
show_json(io::StructuralContext,
            ::TaggedNumberSerialization,
           f::Union{Integer, AbstractFloat}) =
    show_json(io, StandardSerialization(), tag(f))
```

Note that the recursive call constructs a `StandardSerialization()`, as otherwise this would
result in a stack overflow, and serializes a `Dict` using that. In this toy example, this is
fine (with only the overhead of constructing a `Dict`), but this is not always possible.
(For instance, if the constructed `Dict` could have other numbers within its values that
need to be tagged.)

To deal with these more complex cases, or simply to eliminate the overhead of constructing
the intermediate `Dict`, the `show_json` method can be implemented more carefully by
explicitly calling the context’s `begin_object`, `show_pair`, and `end_object` methods, as
documented above, and use the `StandardSerialization()` only for the `show_pair` call for
`f`.

```julia
# More careful implementation
# No difference in this case, but could be needed if recursive data structures are to be
# serialized in more complex cases.
import JSON.Writer: begin_object, show_pair, end_object
function show_json(io::StructuralContext,
                    s::TaggedNumberSerialization,
                    f::Union{Integer, AbstractFloat})
    begin_object(io)
    show_pair(io, s, :tag => string(typeof(f)))
    show_pair(io, StandardSerialization(), :value => f)
    end_object(io)
end
```

To use the custom serialization, `sprint` can be used (and this can be encapsulated by a
convenient user-defined inteface):

```julia
julia> JSON.parse(sprint(show_json, TaggedNumberSerialization(), Any[1, 2.0, "hi"]))
3-element Array{Any,1}:
 Dict{String,Any}("value" => 1,"type" => "Int64")
 Dict{String,Any}("value" => 2.0,"type" => "Float64")
 "hi"
```

If it is not desired to inherit all the functionality of `StandardSerialization`, users may
also choose to start from scratch by directly subtyping `JSON.Serializations.Serialization`.
This is useful if the user wishes to enforce a strict JSON which throws errors when
attempting to serialize objects that aren’t explicitly supported. Note that this means you
will need to define a method to support serializing any kind of object, including the
standard JSON objects like booleans, integers, strings, etc.!
