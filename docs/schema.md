# JSON Schema Generation and Validation

JSON.jl provides a powerful, type-driven interface for generating JSON Schema v7 specifications from Julia types and validating instances against them. The system leverages Julia's type system and `StructUtils` annotations to provide a seamless schema definition experience.

## Quick Start

```julia
using JSON

# Define a struct with field tag annotations
JSON.@defaults struct User
    id::Int = 0 &(json=(
        description="Unique user ID",
        minimum=1
    ),)

    name::String = "" &(json=(
        description="User's full name",
        minLength=1,
        maxLength=100
    ),)

    email::String = "" &(json=(
        description="Email address",
        format="email"
    ),)

    age::Union{Int, Nothing} = nothing &(json=(
        description="User's age",
        minimum=0,
        maximum=150
    ),)
end

# Generate the JSON Schema
schema = JSON.schema(User)

# Validate an instance
user = User(1, "Alice", "alice@example.com", 30)
result = JSON.validate(schema, user)

if result.is_valid
    println("User is valid!")
else
    println("Validation errors:")
    foreach(println, result.errors)
end
```

## API

### `JSON.schema(T; options...)`

Generate a JSON Schema for type `T`.

**Parameters:**
- `T::Type`: The Julia type to generate a schema for.
- `title::String`: Schema title (defaults to type name).
- `description::String`: Schema description.
- `refs::Bool`: If `true`, generates `definitions` for nested types and uses `$ref` pointers. Essential for circular references or shared types.
- `all_fields_required::Bool`: If `true`, marks all fields as required (overriding `Union{T, Nothing}` behavior).
- `additionalProperties::Bool`: Recursively sets `additionalProperties` on all objects.

**Returns:** A `JSON.Schema{T}` object.

### `JSON.validate(schema, instance)`

Validate a Julia instance against the schema.

**Returns:** A `JSON.ValidationResult` struct:
- `is_valid::Bool`: `true` if validation passed.
- `errors::Vector{String}`: A list of error messages if validation failed.

### `JSON.isvalid(schema, instance; verbose=false)`

Convenience function that returns a `Bool`.
- `verbose=true`: Prints validation errors to stdout.

## Validation Features

Validation rules are specified using `StructUtils` field tags with the `json` key.

### String Validation
- `minLength::Int`, `maxLength::Int`
- `pattern::String` (Regex)
- `format::String`: 
  - `"email"`: Basic email validation (no spaces).
  - `"uri"`: URI validation (requires scheme).
  - `"uuid"`: UUID validation.
  - `"date-time"`: ISO 8601 date-time (requires timezone, e.g., `2023-01-01T12:00:00Z`).

### Numeric Validation
- `minimum::Number`, `maximum::Number`
- `exclusiveMinimum::Bool|Number`, `exclusiveMaximum::Bool|Number`
- `multipleOf::Number`

### Array Validation
- `minItems::Int`, `maxItems::Int`
- `uniqueItems::Bool`
- `contains`: A schema that at least one item in the array must match.

### Composition (Advanced)
- `oneOf`: Value must match exactly one of the provided schemas.
- `anyOf`: Value must match at least one of the provided schemas.
- `allOf`: Value must match all of the provided schemas.
- `not`: Value must *not* match the provided schema.

**Example:**
```julia
# Value must be either a string OR an integer (oneOf)
val::Union{String, Int} = 0

# Advanced composition via manual tags
value::Int = 0 &(json=(
    oneOf=[
        Dict("minimum" => 0, "maximum" => 10),
        Dict("minimum" => 100, "maximum" => 110)
    ]
),)
```

### Conditional Logic
- `if`, `then`, `else`: Apply schemas conditionally based on the result of the `if` schema.

## Handling Complex Types

### Recursive & Shared Types (`refs=true`)
By default, schemas are inlined. For complex data models with shared subtypes or circular references (e.g., A -> B -> A), use `refs=true`.

```julia
JSON.@defaults struct Node
    value::Int = 0
    children::Vector{Node} = Node[]
end

# Generates a schema with "definitions" and "$ref" recursion
schema = JSON.schema(Node, refs=true)
```

## Type Mapping

| Julia Type | JSON Schema Type | Notes |
|------------|------------------|-------|
| `Int`, `Float64` | `"integer"`, `"number"` | |
| `String` | `"string"` | |
| `Bool` | `"boolean"` | |
| `Nothing`, `Missing` | `"null"` | |
| `Union{T, Nothing}` | `[T, "null"]` | Automatically optional |
| `Vector{T}` | `"array"` | `items` = schema of `T` |
| `Set{T}` | `"array"` | `uniqueItems: true` |
| `Dict{K,V}` | `"object"` | `additionalProperties` = schema of `V` |
| `Tuple{...}` | `"array"` | Fixed length, positional types |
| Custom Struct | `"object"` | Properties map to fields |

## Best Practices

1. **Use `JSON.validate` for APIs:** It provides programmatic access to error messages, which is essential for reporting validation failures to users.
2. **Use Enums:** `enum=["a", "b"]` is often stricter and better than free-form strings.
3. **Use `refs=true` for Libraries:** If you are generating schemas for a library of types, using references keeps the schema size smaller and more readable.
4. **Be Specific with Formats:** The `date-time` format is strict (ISO 8601 with timezone). Ensure your data complies.