# JSON Writing

This guide to writing JSON in the JSON.jl package aims to:
  - Provide a comprehensive overview of the JSON serialization process.
  - Explain the various options and configurations available for writing JSON data.
  - Offer practical examples to illustrate the usage of different functions and options.

```@contents
```

## Core JSON Serialization - `JSON.json`

The main entrypoint for serializing Julia values to JSON in JSON.jl is the `JSON.json` function. This function offers flexible output options:

```julia
# Serialize to a String
JSON.json(x) -> String

# Serialize to an IO object
JSON.json(io::IO, x) -> IO

# Serialize to a file
JSON.json(file_name::String, x) -> String
```

The `JSON.json` function accepts a wide range of Julia types and transforms them into their JSON representation by knowing how to serialize a core set of types:

| Julia type                         | JSON representation                       |
|------------------------------------|------------------------------------------|
| `Nothing`                          | `null`                                    |
| `Bool`                             | `true` or `false`                         |
| `Number`                           | Numeric value (integer or floating point) |
| `AbstractString`                   | String with escaped characters            |
| `AbstractDict`/`NamedTuple`        | Object (`{}`)                             |
| `AbstractVector`/`Tuple`/`Set`     | Array (`[]`)                              |
| Custom structs                     | Object (`{}`) with fields as keys         |
| `JSONText`                         | Raw JSON (inserted as-is)                 |

For values that don't fall into one of the above categories, `JSON.lower` will be called allowing a "domain transformation" from Julia value to an appropriate representation of the categories above.

## Customizing JSON Output

`JSON.json` supports numerous keyword arguments to control how data is serialized:

### Pretty Printing

By default, `JSON.json` produces compact JSON without extra whitespace. For human-readable output:

```julia
# Boolean flag for default pretty printing (2-space indent)
JSON.json(x; pretty=true)

# Or specify custom indentation level
JSON.json(x; pretty=4)  # 4-space indentation
```

Example of pretty printing:

```julia
data = Dict("name" => "Alice", "scores" => [95, 87, 92])

# Compact output
JSON.json(data)
# {"name":"Alice","scores":[95,87,92]}

# Pretty printed
JSON.json(data; pretty=true)
# {
#   "name": "Alice",
#   "scores": [
#     95,
#     87,
#     92
#   ]
# }
```

When pretty printing, you can also control which arrays get printed inline versus multiline using the `inline_limit` option:

```julia
JSON.json(data; pretty=true, inline_limit=10)
# {
#   "name": "Alice",
#   "scores": [95, 87, 92]
# }
```

### Null and Empty Value Handling

JSON.json provides options to control how `nothing`, `missing`, and empty collections are handled:

```julia
struct Person
    name::String
    email::Union{String, Nothing}
    phone::Union{String, Nothing}
    tags::Vector{String}
end

person = Person("Alice", "alice@example.com", nothing, String[])

# Default behavior writes all values, including null
JSON.json(person)
# {"name":"Alice","email":"alice@example.com","phone":null,"tags":[]}

# Exclude null values
JSON.json(person; omit_null=true)
# {"name":"Alice","email":"alice@example.com","tags":[]}

# Omit empty collections as well
JSON.json(person; omit_null=true, omit_empty=true)
# {"name":"Alice","email":"alice@example.com"}
```

Note that we can also control whether null or empty values are omitted at the type level, either by overloading `omit_null`/`omit_empty` functions:
```julia
JSON.omit_null(::Type{Person}) = true
```

Or by using a convenient macro annotation when defining the struct:
```julia
@omit_null struct Person
    name::String
    email::Union{String, Nothing}
    phone::Union{String, Nothing}
    tags::Vector{String}
end
```

#### Field-level overrides with `JSON.Null` / `JSON.Omit`

Sometimes you want a struct to opt into `omit_null=true` globally, while still forcing specific
fields to emit `null`, or vice-versa. JSON.jl provides two sentinel constructors (defined in the
`JSON` module but intentionally not exported) to cover those cases:

- `JSON.Null()` always serializes as the literal `null`, even when omit-null logic would normally
  skip it.
- `JSON.Omit()` drops the enclosing field/entry regardless of omit settings. (It is only valid
  inside an object/array; using it as the top-level value throws an error.)

You can reference these sentinels directly in your data types or return them from custom `lower`
functions attached via field tags.

```julia
struct Profile
    id::Int
    email::Union{String, JSON.Null}
    nickname::Union{String, JSON.Omit}
end

profile = Profile(1, JSON.Null(), JSON.Omit())

# `email` stays in the payload even with omit_null=true
JSON.json(profile; omit_null=true)
# {"id":1,"email":null}

@tags struct User
    id::Int
    display_name::Union{Nothing, String} &(json=(lower=n -> something(n, JSON.Omit()),),)
end

user = User(2, nothing)

# Field-level lowering can return JSON.Omit() to remove the entry entirely
JSON.json(user)
# {"id":2}
```

### Special Numeric Values

By default, JSON.json throws an error when trying to serialize `NaN`, `Inf`, or `-Inf` as they are not valid JSON. However, you can enable them with the `allownan` option:

```julia
numbers = [1.0, NaN, Inf, -Inf]

# Default behavior throws an error
try
    JSON.json(numbers)
catch e
    println(e)
end
# ArgumentError("NaN not allowed to be written in JSON spec; pass `allownan=true` to allow anyway")

# With allownan=true
JSON.json(numbers; allownan=true)
# [1.0,NaN,Infinity,-Infinity]

# Custom representations
JSON.json(numbers; allownan=true, nan="null", inf="1e999", ninf="-1e999")
# [1.0,null,1e999,-1e999]
```

### Float Formatting

Control how floating-point numbers are formatted in the JSON output:

```julia
pi_value = [Float64(π)]

# Default format (shortest representation)
JSON.json(pi_value)
# [3.141592653589793]

# Fixed decimal notation
JSON.json(pi_value; float_style=:fixed, float_precision=2)
# [3.14]

# Scientific notation
JSON.json(pi_value; float_style=:exp, float_precision=3)
# [3.142e+00]
```

`float_precision` must be a positive integer when `float_style` is `:fixed` or `:exp`.

### JSON Lines Format

The JSON Lines format is useful for streaming records where each line is a JSON value:

```julia
records = [
    Dict("id" => 1, "name" => "Alice"),
    Dict("id" => 2, "name" => "Bob"),
    Dict("id" => 3, "name" => "Charlie")
]

# Standard JSON array
JSON.json(records)
# [{"id":1,"name":"Alice"},{"id":2,"name":"Bob"},{"id":3,"name":"Charlie"}]

# JSON Lines format; each object on its own line, no begining or ending square brackets
JSON.json(records; jsonlines=true)
# {"id":1,"name":"Alice"}
# {"id":2,"name":"Bob"}
# {"id":3,"name":"Charlie"}
```

## Customizing Types

### Using `JSON.JSONText`

The `JSONText` type allows you to insert raw, pre-formatted JSON directly:

```julia
data = Dict(
    "name" => "Alice",
    "config" => JSON.JSONText("{\"theme\":\"dark\",\"fontSize\":16}")
)

JSON.json(data)
# {"name":"Alice","config":{"theme":"dark","fontSize":16}}
```

### Custom Type Serialization with `lower`

For full control over how a type is serialized, you can define a `JSON.lower` method:

```julia
struct Coordinate
    lat::Float64
    lon::Float64
end

# Serialize as an array instead of an object
JSON.lower(c::Coordinate) = [c.lat, c.lon]

point = Coordinate(40.7128, -74.0060)
JSON.json(point)
# [40.7128,-74.006]

# For serializing custom formats
struct UUID
    value::String
end

JSON.lower(u::UUID) = u.value

JSON.json(UUID("123e4567-e89b-12d3-a456-426614174000"))
# "123e4567-e89b-12d3-a456-426614174000"
```

### Custom Serialization for Non-Owned Types

To customize serialization for types you don't own (those from other packages), you can use a custom style:

```julia
using Dates

# Create a custom style that inherits from JSONStyle
struct DateTimeStyle <: JSON.JSONStyle end

# Define how to serialize Date and DateTime in this style
JSON.lower(::DateTimeStyle, d::Date) = string(d)
JSON.lower(::DateTimeStyle, dt::DateTime) = Dates.format(dt, "yyyy-mm-dd HH:MM:SS")

# Use the custom style
JSON.json(Date(2023, 1, 1); style=DateTimeStyle())
# "2023-01-01"

JSON.json(DateTime(2023, 1, 1, 12, 30, 45); style=DateTimeStyle())
# "2023-01-01 12:30:45"
```

## Customizing Struct Serialization

### Field Names and Tags

The JSON.jl package integrates with StructUtils.jl for fine-grained control over struct serialization. StructUtils.jl provides convenient "struct" macros:
  - `@noarg`: generates a "no-argument" constructor (`T()`)
  - `@kwarg`: generates an all-keyword-argument constructor, similar to `Base.@kwdef`; (`T(; kw1=v1, kw2=v2, ...)`)
  - `@tags`/`@defaults`: convenience macros to enable specifying field defaults and field tags
  - `@nonstruct`: marks a struct as non-struct-like, treating it as a primitive type for serialization

Each struct macro also supports the setting of field default values (using the same syntax as `Base.@kwdef`), as well as specifying "field tags"
using the `&(tag=val,)` syntax.

```julia
using JSON, StructUtils

# Using the @tags macro to customize field serialization
@tags struct User
    user_id::Int &(json=(name="id",),)
    first_name::String &(json=(name="firstName",),)
    last_name::String &(json=(name="lastName",),)
    created_at::DateTime &(json=(dateformat="yyyy-mm-dd",),)
    internal_note::String &(json=(ignore=true,),)
end

user = User(123, "Jane", "Doe", DateTime(2023, 5, 8), "Private note")

JSON.json(user)
# {"id":123,"firstName":"Jane","lastName":"Doe","created_at":"2023-05-08"}
```

The various field tags allow:
- Renaming fields with `name`
- Custom date formatting with `dateformat`
- Excluding fields from JSON output with `ignore=true`

### Default Values with `@defaults`

Combine with the `@defaults` macro to provide default values:

```julia
@defaults struct Configuration
    port::Int = 8080
    host::String = "localhost"
    debug::Bool = false
    timeout::Int = 30
end

config = Configuration(9000)
JSON.json(config)
# {"port":9000,"host":"localhost","debug":false,"timeout":30}
```

## Handling Circular References

`JSON.json` automatically detects circular references to prevent infinite recursion:

```julia
mutable struct Node
    value::Int
    next::Union{Nothing, Node}
end

# Create a circular reference
node = Node(1, nothing)
node.next = node

# Without circular detection, this would cause a stack overflow
JSON.json(node; omit_null=false)
# {"value":1,"next":null}
```

## Custom Dictionary Key Serialization

For dictionaries with non-string keys, `JSON.json` has a few default `lowerkey` definitions to convert keys to strings:

```julia
# Integer keys
JSON.json(Dict(1 => "one", 2 => "two"))
# {"1":"one","2":"two"}

# Symbol keys
JSON.json(Dict(:name => "Alice", :age => 30))
# {"name":"Alice","age":30}

# Custom key serialization
struct CustomKey
    id::Int
end

dict = Dict(CustomKey(1) => "value1", CustomKey(2) => "value2")
try
    JSON.json(dict)
catch e
    println(e)
end
# ArgumentError("No key representation for CustomKey. Define StructUtils.lowerkey(::CustomKey)")

# Define how the key should be converted to a string
StructUtils.lowerkey(::JSON.JSONStyle, k::CustomKey) = "key-$(k.id)"

JSON.json(dict)
# {"key-1":"value1","key-2":"value2"}
```

## Advanced Example: The FrankenStruct

Let's explore a comprehensive example that showcases many of JSON.jl's advanced serialization features:

```julia
using Dates, JSON, StructUtils

abstract type AbstractMonster end

struct Dracula <: AbstractMonster
    num_victims::Int
end

struct Werewolf <: AbstractMonster
    witching_hour::DateTime
end

struct Percent <: Number
    value::Float64
end

JSON.lower(x::Percent) = x.value
StructUtils.lowerkey(x::Percent) = string(x.value)

@noarg mutable struct FrankenStruct
    id::Int
    name::String # no default to show serialization of an undefined field
    address::Union{Nothing, String} = nothing
    rate::Union{Missing, Float64} = missing
    type::Symbol = :a &(json=(name="franken_type",),)
    notsure::Any = JSON.Object("key" => "value")
    monster::AbstractMonster = Dracula(10) &(json=(lower=x -> x isa Dracula ? 
        (monster_type="vampire", num_victims=x.num_victims) : 
        (monster_type="werewolf", witching_hour=x.witching_hour),),)
    percent::Percent = Percent(0.5)
    birthdate::Date = Date(2025, 1, 1) &(json=(dateformat="yyyy/mm/dd",),)
    percentages::Dict{Percent, Int} = Dict{Percent, Int}(Percent(0.0) => 0, Percent(1.0) => 1)
    json_properties::JSONText = JSONText("{\"key\": \"value\"}")
    matrix::Matrix{Float64} = [1.0 2.0; 3.0 4.0]
    extra_field::Any = nothing &(json=(ignore=true,),)
end

franken = FrankenStruct()
franken.id = 1

json = JSON.json(franken)
# "{\"id\":1,\"name\":null,\"address\":null,\"rate\":null,\"franken_type\":\"a\",\"notsure\":{\"key\":\"value\"},\"monster\":{\"monster_type\":\"vampire\",\"num_victims\":10},\"percent\":0.5,\"birthdate\":\"2025/01/01\",\"percentages\":{\"1.0\":1,\"0.0\":0},\"json_properties\":{\"key\": \"value\"},\"matrix\":[[1.0,3.0],[2.0,4.0]]}"
```

Let's analyze each part of this complex example to understand how JSON.jl's serialization features work:

### Custom Type Serialization Strategy

1. **The `AbstractMonster` Type Hierarchy**:
   - We define an abstract type `AbstractMonster` with two concrete subtypes: `Dracula` and `Werewolf`
   - Each type contains type-specific data (number of victims vs. witching hour)

2. **Custom Numeric Type**:
   - `Percent` is a custom numeric type that wraps a `Float64`
   - We provide two serialization methods:
     - `JSON.lower(x::Percent) = x.value`: This tells JSON how to serialize a `Percent` value (convert to the underlying Float64)
     - `StructUtils.lowerkey(x::Percent) = string(x.value)`: This handles when a `Percent` is used as a dictionary key

3. **The `FrankenStruct`**:
   - Created with `@noarg` making it a mutable struct that can be default constructed like `FrankenStruct()`

### Field-Level Serialization Control

Let's examine each field of `FrankenStruct` in detail:

1. **Basic Fields**: 
   - `id::Int`: Standard integer field (initialized explicitly to 1)
   - `name::String`: Intentionally left uninitialized to demonstrate `#undef` serialization

2. **Null Handling and Unions**:
   - `address::Union{Nothing, String} = nothing`: Demonstrates how `Nothing` values are serialized
   - `rate::Union{Missing, Float64} = missing`: Shows how `Missing` values are serialized (both become `null` in JSON)

3. **Field Renaming with Tags**:
   - `type::Symbol = :a &(json=(name="franken_type",),)`: 
     - The `name` tag changes the output JSON key from `"type"` to `"franken_type"`
     - The value `:a` is automatically serialized as the string `"a"` through a default `lower` method for symbols

4. **Any Type**:
   - `notsure::Any = JSON.Object("key" => "value")`: Shows how JSON handles arbitrary types

5. **Field-Specific Custom Serialization**:
   - ```
     monster::AbstractMonster = Dracula(10) &(json=(lower=x -> x isa Dracula ? 
         (monster_type="vampire", num_victims=x.num_victims) : 
         (monster_type="werewolf", witching_hour=x.witching_hour),),)
     ```
     - This demonstrates **field-specific custom serialization** using the `lower` field tag
     - The lambda function checks the concrete type and produces a different JSON structure based on the type
     - For `Dracula`, it adds a `"monster_type": "vampire"` field
     - For `Werewolf`, it would add a `"monster_type": "werewolf"` field
     - Unlike a global `JSON.lower` method, this approach only applies when this specific field is serialized

6. **Custom Numeric Type**:
   - `percent::Percent = Percent(0.5)`: Uses the global `JSON.lower` we defined to serialize as `0.5`

7. **Custom Date Formatting**:
   - `birthdate::Date = Date(2025, 1, 1) &(json=(dateformat="yyyy/mm/dd",),)`:
     - The `dateformat` field tag controls how the date is formatted
     - Instead of ISO format (`"2025-01-01"`), it's serialized as `"2025/01/01"`

8. **Dictionary with Custom Keys**:
   - `percentages::Dict{Percent, Int} = Dict{Percent, Int}(Percent(0.0) => 0, Percent(1.0) => 1)`:
     - This dictionary uses our custom `Percent` type as keys
     - JSON uses our `StructUtils.lowerkey` method to convert the keys to strings

9. **Raw JSON Inclusion**:
   - `json_properties::JSONText = JSONText("{\"key\": \"value\"}")`:
     - The `JSONText` wrapper indicates this should be included as-is in the output
     - No escaping or processing is done; the string is inserted directly into the JSON

10. **Matrices and Multi-dimensional Arrays**:
    - `matrix::Matrix{Float64} = [1.0 2.0; 3.0 4.0]`:
      - 2D array serialized as nested arrays in column-major order

11. **Ignoring Fields**:
    - `extra_field::Any = nothing &(json=(ignore=true,),)`:
      - The `ignore=true` field tag means this field will be completely excluded from serialization
      - Useful for internal fields that shouldn't be part of the JSON representation

### Output Analysis

When we serialize this struct, we get a JSON string with all the specialized serialization rules applied:

```json
{
  "id": 1,
  "name": null,
  "address": null,
  "rate": null,
  "franken_type": "a",
  "notsure": {"key": "value"},
  "monster": {"monster_type": "vampire", "num_victims": 10},
  "percent": 0.5,
  "birthdate": "2025/01/01",
  "percentages": {"1.0": 1, "0.0": 0},
  "json_properties": {"key": "value"},
  "matrix": [[1.0, 3.0], [2.0, 4.0]]
}
```

Some key observations:
- `extra_field` is completely omitted due to the `ignore` tag
- Field names are either their originals (`id`, `name`) or renamed versions (`franken_type` instead of `type`)
- The nested `monster` field has custom serialization, producing a specialized format
- The date is in the custom format we specified
- Dictionary keys using our custom `Percent` type are properly converted to strings
- The matrix is serialized in column-major order as nested arrays
- The `JSONText` data is inserted directly without any additional processing

This example demonstrates how JSON.jl provides extensive control over JSON serialization at multiple levels: global type rules, field-specific customization, and overall serialization options.
