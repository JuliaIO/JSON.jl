# JSON Reading

This guide to reading JSON in the JSON.jl package aims to:
  - Provide a comprehensive overview of the JSON reading process.
  - Explain the various options and configurations available for reading JSON data.
  - Offer practical examples to illustrate the usage of different functions and options.

```@contents
```
  
## Core JSON Parsing - `JSON.lazy` and `JSON.LazyValue`

There are several "entrypoints" to reading JSON in JSON.jl, including:
  - `JSON.parse`/`JSON.parse!`
  - `JSON.parsefile`/`JSON.parsefile!`
  - `JSON.lazy`/`JSON.lazyfile`
  - `JSON.isvalidjson`

These functions are all built to accept the same kinds of JSON inputs:

| Accepted `json` sources                    | Notes                                             |
|--------------------------------------------|---------------------------------------------------|
| `AbstractString`                           | UTF‑8; UTF‑8‑BOM handled automatically            |
| `AbstractVector{UInt8}`                    | zero‑copy if already bytes                        |
| `IO`, `IOStream`, `Base.AbstractCmd`       | stream fully read into a byte vector              |

The core JSON parsing machinery is hence built around having an `AbstractVector{UInt8}` or `AbstractString` JSON input where individual bytes can be parsed to identify JSON structure, validate syntax, and ultimately produce Julia-level values.

Each entrypoint function first calls `JSON.lazy`, which will consume the JSON input until the type of the next JSON value can be identified (`{` for objects, `[` for arrays, `"` for strings, `t` for true, `f` for false, `n` for null, and `-` or a digit for numbers). `JSON.lazy` returns a `JSON.LazyValue`, which wraps the JSON input buffer (`AbstractVector{UInt8}` or `AbstractString`), and marks the byte position the value starts at, the type of the value, and any keyword arguments that were provided that may affect parsing. Currently supported parsing-specific keyword arguments to `JSON.lazy` (and thus all other entrypoint functions) include:

  - `allownan::Bool = false`: whether "special" float values shoudl be allowed while parsing (`NaN`, `Inf`, `-Inf`); these values are specifically _not allowed_ in the JSON spec, but many JSON libraries allow reading/writing
  - `ninf::String = "-Infinity"`: the string that will be used to parse `-Inf` if `allownan=true`
  - `inf::String = "Infinity"`: the string that will be used to parse `Inf` if `allownan=true`
  - `nan::String = "NaN"`: the string that will be sued to parse `NaN` if `allownan=true`
  - `jsonlines::Bool = false`: whether the JSON input should be treated as an implicit array, with newlines separating individual JSON elements with no leading `'['` or trailing `']'` characters. Common in logging or streaming workflows. Defaults to `true` when used with `JSON.parsefile` and the filename extension is `.jsonl` or `ndjson`. Note this ensures that parsing will _always_ return an array at the root-level.
  - Materialization-specific keyword arguments (i.e. they affect materialization, but not parsing)
    - `dicttype = JSON.Object{String, Any}`: type to parse JSON objects as by default (recursively)
    - `null = nothing`: value to return for JSON `null` value

So what can we do with a `JSON.LazyValue`?

```julia-repl
julia> x = JSON.lazy("{\"a\": 1, \"b\": null, \"c\": true, \"d\": false, \"e\": \"\", \"f\": [1,2,3], \"g\": {\"h\":{\"i\":\"foo\"}}}")
LazyObject{String} with 7 entries:
  "a" => JSON.LazyValue(1)
  "b" => JSON.LazyValue(nothing)
  "c" => JSON.LazyValue(true)
  "d" => JSON.LazyValue(false)
  "e" => JSON.LazyValue("")
  "f" => LazyValue[JSON.LazyValue(1), JSON.LazyValue(2), JSON.LazyValue(3)]
  "g" => LazyObject{String}("h"=>LazyObject{String}("i"=>JSON.LazyValue("foo")))
```

Note that for convenience at the REPL, special `show` overloads enable displaying the full contents of lazy values. In reality, remember the `LazyValue` only marks the _position_ of a value within the JSON.
`LazyValue`s support convenient syntax for both _navigating_ their structure and _materializing_, with an aim
to support lazy workflows. Examples include:

```julia-repl
# convenient "get" syntax on lazy objects
julia> x.a
JSON.LazyValue(1)

julia> x[:b]
JSON.LazyValue(nothing)

julia> x["c"]
JSON.LazyValue(true)

julia> propertynames(x)
7-element Vector{Symbol}:
 :a
 :b
 :c
 :d
 :e
 :f
 :g

julia> x.g.h.i
JSON.LazyValue("foo")

# array indexing on lazy arrays
julia> x.f[1]
JSON.LazyValue(1)

julia> x.f[end]
JSON.LazyValue(3)

julia> x.f[1:3]
3-element StructUtils.Selectors.List{Any}:
 JSON.LazyValue(1)
 JSON.LazyValue(2)
 JSON.LazyValue(3)

# default materialization of any LazyValue via empty getindex
julia> x.a[]
1

julia> x[]
JSON.Object{String, Any} with 7 entries:
  "a" => 1
  "b" => nothing
  "c" => true
  "d" => false
  "e" => ""
  "f" => Any[1, 2, 3]
  "g" => Object{String, Any}("h"=>Object{String, Any}("i"=>"foo"))
```

Let's take a closer look at one of these examples and talk through what's going on under the hood. For `x.g.h.i`, this deeply nested access of the `"foo"` value, is a chain of `getproperty` calls, with each call (i.e. `y = x.g`, then `z = y.h`, etc.) returning a `LazyValue` of where the next nested object begins in the raw JSON. With the final `getproperty` call (`h.i`), a non-object `LazyValue("foo")` is returned. In our raw JSON, the `"foo"` value is located near the end, so we can infer that by doing `x.g.h.i`, the underlying JSON was parsed or _navigated_ until the `i` key was found and its value returned. In this example, `"foo"` is indeed the last value in our raw JSON, but in the example of `x.c`, we can also be assured that only as much JSON as necessary was parsed/navigated before returning `LazyValue(true)`. In this way, the various syntax calls (`getproperty`, `getindex`, etc.) on `LazyValue`s can be thought of as purely _navigational_ as opposed to anything related to _materialization_. Indeed, the very purpose of the lazy machinery in JSON.jl is to _allow_ lazily navigating, specifically _without_ needing to materialize anything along the way.

Ok, but at some point, we _do_ actually need Julia values to operate on, so let's shift to how _materialization_ works in JSON.jl.

## `JSON.parse` - Untyped materialization

In the `LazyValue` syntax example, it was shown that empty `getindex` will result in a "default" materialization of a `LazyValue`:

```julia-repl
julia> x[]
JSON.Object{String, Any} with 7 entries:
  "a" => 1
  "b" => nothing
  "c" => true
  "d" => false
  "e" => ""
  "f" => Any[1, 2, 3]
  "g" => Object{String, Any}("h"=>Object{String, Any}("i"=>"foo"))
```

Under the hood, this `getindex` call is really calling `JSON.parse(lazyvalue)`. `JSON.parse` can also be called as a main entrypoint function with all the same input types as `JSON.lazy`. This form of `parse` is referred to as "untyped parsing" or "untyped materialization". It allocates and _materializes_ the raw JSON values into appropriate "default" Julia-level values. In particular:

| JSON construct | Default Julia value                                                       |
|----------------|---------------------------------------------------------------------------|
| object         | `JSON.Object{String,Any}` (order‑preserving drop-in replacement for Dict) |
| array          | `Vector{Any}`                                                             |
| string         | `String`                                                                  |
| number         | `Int64`, `BigInt`, `Float64`, or `BigFloat`                               |
| `null`         | `nothing`                                                                 |
| `true/false`   | `Bool`                                                                    |

Mostly vanilla, but what is `JSON.Object`? It is a custom `AbstractDict` using an internal linked-list implementation that preserves insertion order, behaves as a drop-in replacement for `Dict`, and allows memory and performance benefits vs. `Dict` for small # of entries. It also supports natural JSON-object-like
syntax for accessing or setting values, like `x.g.h.i` and `x.c = false`.

Because `Object` uses a linked-list implementation, key lookups are `O(n)`, performing a linear scan on each access. For small number of entries (dozens), the real-performance difference vs. `Dict` hash-lookup is negligible, but for large objects, this can be prohibitive. For these cases, it's recommended to materialize JSON objects as regular Julia `Dict`, by utilizing the `dicttype` keyword argument, like: `JSON.parse(json; dicttype=Dict{String, Any})`.

## `JSON.parse` - Typed materialization

While untyped materialization is convenient for quick exploration, one of the most powerful features of JSON.jl is its ability to directly parse JSON into concrete Julia types. This is done by providing a type as the second argument to `JSON.parse` and opens up a world of type-safe JSON parsing with minimal boilerplate.

### Basic usage with structs

Let's start with a simple example. Suppose we have a Julia struct and a JSON string we want to parse into that type:

```julia
struct Person
    name::String
    age::Int
end

json = """{"name": "Alice", "age": 30}"""
person = JSON.parse(json, Person)
# Person("Alice", 30)
```

With this approach, JSON.jl automatically:
- Matches JSON object keys to struct field names
- Converts values to the appropriate field types
- Constructs the struct with the parsed values

This works for nested structs too:

```julia
struct Address
    street::String
    city::String
    country::String
end

struct Employee
    name::String
    age::Int
    address::Address
end

json = """
{
    "name": "Bob",
    "age": 42,
    "address": {
        "street": "123 Main St",
        "city": "Anytown",
        "country": "USA"
    }
}
"""

employee = JSON.parse(json, Employee)
```

### Arrays and collections

You can parse JSON arrays directly into Julia arrays with a specific element type:

```julia
# Parse into a Vector of integers
ints = JSON.parse("[1, 2, 3, 4, 5]", Vector{Int})
# 5-element Vector{Int64}: [1, 2, 3, 4, 5]

# Parse into a Vector of custom structs
people = JSON.parse("""
[
    {"name": "Alice", "age": 30},
    {"name": "Bob", "age": 42}
]
""", Vector{Person})
# 2-element Vector{Person}: [Person("Alice", 30), Person("Bob", 42)]
```

A particularly powerful feature is the ability to parse nested arrays into multi-dimensional arrays:

```julia
# Parse a nested array into a Matrix
matrix = JSON.parse("[[1, 2], [3, 4]]", Matrix{Int})
# 2×2 Matrix{Int64}:
#  1  3
#  2  4
```

Note that for matrices, JSON.jl expects column-major order (Julia's native format). The innermost arrays become the columns of the matrix.

### Primitive and simple types

JSON.jl can also parse JSON values directly into primitive types:

```julia
# Parse a JSON number into an Int
n = JSON.parse("42", Int)
# 42

# Parse a JSON string into a String
s = JSON.parse("\"hello\"", String)
# "hello"

# Parse a JSON string into a custom type like UUID
uuid = JSON.parse("\"123e4567-e89b-12d3-a456-426614174000\"", UUID)
# UUID("123e4567-e89b-12d3-a456-426614174000")

# Parse a JSON string into a Date
date = JSON.parse("\"2023-05-08\"", Date)
# Date("2023-05-08")
```

### Type conversions and handling nulls

JSON.jl provides smart handling for Union types, especially for dealing with potentially null values:

```julia
struct OptionalData
    id::Int
    description::Union{String, Nothing}
    score::Union{Float64, Missing}
end

json = """
{
    "id": 123,
    "description": null,
    "score": null
}
"""

data = JSON.parse(json, OptionalData)
# OptionalData(123, nothing, missing)
```

Note how JSON.jl automatically:
- Converts JSON `null` to Julia `nothing` for `Union{T, Nothing}` fields
- Converts JSON `null` to Julia `missing` for `Union{T, Missing}` fields

### Field customization through tags

You can customize how JSON fields map to struct fields using "field tags" from StructUtils.jl via the struct macros (`@tags`, `@defaults`, `@kwarg`, or `@noarg`):

```julia
using JSON, StructUtils

@tags struct UserProfile
    user_id::Int &(json=(name="id",),)
    first_name::String &(json=(name="firstName",),)
    last_name::String &(json=(name="lastName",),)
    birth_date::Date &(json=(dateformat=dateformat"yyyy/mm/dd",),)
end

json = """
{
    "id": 42,
    "firstName": "Jane",
    "lastName": "Doe",
    "birth_date": "1990/01/15"
}
"""

user = JSON.parse(json, UserProfile)
# UserProfile(42, "Jane", "Doe", Date("1990-01-15"))
```

The `&(json=(name="...",),)` syntax lets you:
- Map differently named JSON keys to your struct fields
- Specify custom date formats for parsing dates
- And many other customizations

Field tags are really named tuples of values, prefixed with the `&` character, so note the trailing `,` when the named tuple has a single element.
Also note that in this example, we "namespaced" our field tags with the `json=(...)` key. Then when "making" our struct, only the `json=(...)` field tags
are considered. This is because JSON.jl defines `json` as a "field tag key" for its custom `JSONStyle`, then passes a `JSONStyle` to be used when parsing.
That means you could specify the field tag like `&(name="id,)`, but if the field then is also used by any other package, it would also see that name.
Sometimes that may be desirable, but there are also cases where you want the namespacing, like: `&(json=(name="id",), postgres=(name="user_id",))`.

### Default values with `@defaults`

When some JSON fields might be missing, you can provide default values similar to field tags using any of the struct macros (`@tags`, `@defaults`, `@kwarg`, or `@noarg`):

```julia
@defaults struct Configuration
    port::Int = 8080
    host::String = "localhost"
    debug::Bool = false
    timeout::Int = 30
end

# Even with missing fields, parsing succeeds with defaults
json = """{"port": 9000}"""
config = JSON.parse(json, Configuration)
# Configuration(9000, "localhost", false, 30)
```

### Non-struct-like types with `@nonstruct`

What if you have a custom struct that you want to behave more like a primitive type rather than a struct? For example, you might want a custom email type that should be serialized as a JSON string rather than a JSON object.

The `@nonstruct` macro is perfect for this use case. By marking your struct as non-struct-like, you tell JSON.jl to treat it as a primitive type that should be converted directly using `lift` and `lower` methods rather than constructing it from field values.

Here's an example of a custom email type that should be serialized as a JSON string:

```julia
using JSON

@nonstruct struct Email
    value::String
    
    function Email(value::String)
        # Validate email format
        if !occursin(r"^[^@]+@[^@]+\.[^@]+$", value)
            throw(ArgumentError("Invalid email format: $value"))
        end
        new(value)
    end
end

# Define how to convert from various sources to Email
JSON.lift(::Type{Email}, x::String) = Email(x)

# Define how to convert Email to a serializable format
JSON.lower(x::Email) = x.value

# Now you can use Email in your structs and it will be serialized as a string
@defaults struct User
    id::Int = 1
    name::String = "default"
    email::Email
end

# Create a user with an email
user = User(email=Email("alice@example.com"))

# Convert to JSON - email will be a string, not an object
json_string = JSON.json(user)
# Result: {"id":1,"name":"default","email":"alice@example.com"}

# Parse back from JSON
user_again = JSON.parse(json_string, User)
```

Another example - a custom numeric type that represents a percentage:

```julia
@nonstruct struct Percent <: Number
    value::Float64
    
    function Percent(value::Real)
        if value < 0 || value > 100
            throw(ArgumentError("Percentage must be between 0 and 100"))
        end
        new(Float64(value))
    end
end

# Convert from various numeric types
JSON.lift(::Type{Percent}, x::Number) = Percent(x)
JSON.lift(::Type{Percent}, x::String) = Percent(parse(Float64, x))

# Convert to a simple number for serialization
JSON.lower(x::Percent) = x.value

# Use in a struct
@defaults struct Product
    name::String = "default"
    discount::Percent = Percent(0.0)
end

# Create and serialize
product = Product(discount=Percent(15.5))
json_string = JSON.json(product)
# Result: {"name":"default","discount":15.5}
```

The key points about `@nonstruct`:

1. **No field defaults or tags**: Since you're opting out of struct-like behavior, field defaults and tags are not supported.

2. **Requires `lift` and `lower` methods**: You must define how to convert to/from your type.

3. **Fields are private**: The struct's fields are considered implementation details for the parsing process.

4. **Perfect for wrapper types**: Great for types that wrap primitives but need custom validation or behavior.

### Advanced Example: The FrankenStruct

Let's explore a more comprehensive example that showcases many of JSON.jl's advanced typed parsing features:

```julia
using Dates, JSON, StructUtils

# First, define some types for polymorphic parsing
abstract type AbstractMonster end

struct Dracula <: AbstractMonster
    num_victims::Int
end

struct Werewolf <: AbstractMonster
    witching_hour::DateTime
end

# Define a custom type chooser for AbstractMonster
JSON.@choosetype AbstractMonster x -> x.monster_type[] == "vampire" ? Dracula : Werewolf

# Define a custom numeric type with special parsing
struct Percent <: Number
    value::Float64
end

# Custom lifting for the Percent type
JSON.lift(::Type{Percent}, x) = Percent(Float64(x))
StructUtils.liftkey(::Type{Percent}, x::String) = Percent(parse(Float64, x))

# Our complex struct with various field types and defaults
@defaults struct FrankenStruct
    id::Int = 0
    name::String = "Jim"
    address::Union{Nothing, String} = nothing
    rate::Union{Missing, Float64} = missing
    type::Symbol = :a &(json=(name="franken_type",),)
    notsure::Any = nothing
    monster::AbstractMonster = Dracula(0)
    percent::Percent = Percent(0.0)
    birthdate::Date = Date(0) &(json=(dateformat="yyyy/mm/dd",),)
    percentages::Dict{Percent, Int} = Dict{Percent, Int}()
    json_properties::JSONText = JSONText("")
    matrix::Matrix{Float64} = Matrix{Float64}(undef, 0, 0)
end

# A complex JSON input with various features to demonstrate
json = """
{
    "id": 1,
    "address": "123 Main St",
    "rate": null,
    "franken_type": "b",
    "notsure": {"key": "value"},
    "monster": {
        "monster_type": "vampire",
        "num_victims": 10
    },
    "percent": 0.1,
    "birthdate": "2023/10/01",
    "percentages": {
        "0.1": 1,
        "0.2": 2
    },
    "json_properties": {"key": "value"},
    "matrix": [[1.0, 2.0], [3.0, 4.0]],
    "extra_key": "extra_value"
}
"""

franken = JSON.parse(json, FrankenStruct)
```

Let's walk through some notable features of the example above:
  * The `name` field isn't present in the JSON input, so the default value of `"Jim"` is used.
  * The `address` field uses a default `@choosetype` to determine that the JSON value is not `null`, so a `String` should be parsed for the field value.
  * The `rate` field has a `null` JSON value, so the default `@choosetype` recognizes it should be "lifted" to `Missing`, which then uses a predefined `lift` definition for `Missing`.
  * The `type` field is a `Symbol`, and has a fieldtag `json=(name="franken_type",)` which means the JSON key `franken_type` will be used to set the field value instead of the default `type` field name. A default `lift` definition for `Symbol` is used to convert the JSON string value to a `Symbol`.
  * The `notsure` field is of type `Any`, so the default object type `JSON.Object{String, Any}` is used to materialize the JSON value.
  * The `monster` field is a polymorphic type, and the JSON value has a `monster_type` key that determines which concrete type to use. The `@choosetype` macro is used to define the logic for choosing the concrete type based on the JSON input. Note that teh `x` in `@choosetype` is a `LazyValue`, so we materialize via `x.monster_type[]` in order to compare with the string `"vampire"`.
  * The `percent` field is a custom type `Percent` and the `JSON.lift` macro defines how to construct a `Percent` from the JSON value, which is a `Float64` in this case.
  * The `birthdate` field uses a custom date format for parsing, specified in the JSON input.
  * The `percentages` field is a dictionary with keys of type `Percent`, which is a custom type. The `liftkey` function is defined to convert the JSON string keys to `Percent` types (parses the Float64 manually)
  * The `json_properties` field has a type of `JSONText`, which means the raw JSON will be preserved as a String of the `JSONText` type.
  * The `matrix` field is a `Matrix{Float64}`, so the JSON input array-of-arrays are materialized as such.
  * The `extra_key` field is not defined in the `FrankenStruct` type, so it is ignored and skipped over.
