# JSON Schema Generation

JSON.jl provides a simple, elegant interface for generating JSON Schema v7 specifications from Julia types. The schema generation leverages StructUtils field tag annotations to specify validation rules and constraints.

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

# Output as JSON
println(JSON.json(schema, pretty=true))
```

Output:
```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "title": "User",
  "type": "object",
  "properties": {
    "id": {
      "type": "integer",
      "description": "Unique user ID",
      "minimum": 1
    },
    "name": {
      "type": "string",
      "description": "User's full name",
      "minLength": 1,
      "maxLength": 100
    },
    "email": {
      "type": "string",
      "description": "Email address",
      "format": "email"
    },
    "age": {
      "type": ["integer", "null"],
      "description": "User's age",
      "minimum": 0,
      "maximum": 150
    }
  },
  "required": ["id", "name", "email"]
}
```

## API

### `JSON.schema(T; options...)`

Generate a JSON Schema for type `T`.

**Parameters:**
- `T::Type`: The Julia type to generate a schema for
- `title::String` (optional): Schema title (defaults to type name)
- `description::String` (optional): Schema description
- `id::String` (optional): Schema `$id` field
- `draft::String` (optional): JSON Schema draft version (default: `"https://json-schema.org/draft-07/schema#"`)

**Returns:** A `JSON.Object{String, Any}` containing the JSON Schema

### `JSON.@schema T`

Macro version for convenient schema generation.

```julia
schema = JSON.@schema User
```

## Field Tag Properties

All validation properties are specified using StructUtils field tags with the `json` key:

```julia
field::Type = default &(json=(property=value, ...),)
```

### String Validation

- `minLength::Int`: Minimum string length
- `maxLength::Int`: Maximum string length
- `pattern::String`: Regular expression pattern (ECMA-262)
- `format::String`: Format hint (e.g., `"email"`, `"uri"`, `"date-time"`, `"uuid"`, `"ipv4"`, `"ipv6"`)

**Example:**
```julia
email::String = "" &(json=(
    description="Email address",
    format="email",
    minLength=5,
    maxLength=254
),)

username::String = "" &(json=(
    pattern="^[a-zA-Z0-9_]+\$",
    minLength=3,
    maxLength=20
),)
```

### Numeric Validation

- `minimum::Number`: Minimum value (inclusive)
- `maximum::Number`: Maximum value (inclusive)
- `exclusiveMinimum::Bool|Number`: Exclusive minimum
- `exclusiveMaximum::Bool|Number`: Exclusive maximum
- `multipleOf::Number`: Value must be a multiple of this number

**Example:**
```julia
age::Int = 0 &(json=(
    minimum=0,
    maximum=150
),)

price::Float64 = 0.0 &(json=(
    minimum=0.0,
    exclusiveMinimum=true  # price must be > 0
),)

percentage::Float64 = 0.0 &(json=(
    minimum=0.0,
    maximum=100.0,
    multipleOf=0.1  # one decimal place
),)
```

### Array Validation

- `minItems::Int`: Minimum array length
- `maxItems::Int`: Maximum array length
- `uniqueItems::Bool`: All items must be unique

**Example:**
```julia
tags::Vector{String} = String[] &(json=(
    minItems=1,
    maxItems=10,
    uniqueItems=true
),)
```

### Object Validation

- `minProperties::Int`: Minimum number of properties
- `maxProperties::Int`: Maximum number of properties

### Generic Properties

- `description::String`: Human-readable description
- `title::String`: Short title for the field
- `default::Any`: Default value
- `examples::Vector`: Example values
- `_const::Any`: Field must have this exact value (use `_const` since `const` is a reserved keyword)
- `enum::Vector`: Field must be one of these values
- `required::Bool`: Override automatic required field detection

**Example:**
```julia
status::String = "active" &(json=(
    description="Account status",
    enum=["active", "inactive", "suspended"],
    default="active"
),)

api_version::String = "v1" &(json=(
    _const="v1",  # field must always be "v1"
    description="API version (fixed)"
),)

color::String = "blue" &(json=(
    examples=["red", "green", "blue", "yellow"]
),)
```

## Advanced Features

### Field Renaming

Use the `name` tag to specify a different name in the JSON Schema:

```julia
JSON.@defaults struct APIResponse
    internal_id::String = "" &(json=(name="id",),)
    status_code::Int = 200 &(json=(name="status",),)
end
```

The schema will have fields named `"id"` and `"status"` instead of `"internal_id"` and `"status_code"`.

### Ignored Fields

Use `ignore=true` to exclude fields from the schema:

```julia
JSON.@defaults struct Config
    public_setting::String = ""
    private_key::String = "" &(json=(ignore=true,),)  # won't appear in schema
end
```

### Optional Fields

Fields with type `Union{T, Nothing}` are automatically marked as optional (not required):

```julia
JSON.@defaults struct Person
    name::String = ""           # required
    age::Union{Int, Nothing} = nothing  # optional (not in "required" array)
end
```

Override this behavior with the `required` tag:

```julia
must_provide::Union{String, Nothing} = nothing &(json=(required=true,),)
can_skip::String = "" &(json=(required=false,),)
```

### Nested Structs

Nested struct types are automatically converted to nested object schemas:

```julia
JSON.@defaults struct Address
    street::String = ""
    city::String = ""
    zipcode::String = "" &(json=(pattern="^[0-9]{5}\$",),)
end

JSON.@defaults struct Person
    name::String = ""
    address::Address = Address()  # nested object schema
end
```

### Collections

**Arrays:**
```julia
tags::Vector{String} = String[]  # array of strings
matrix::Vector{Vector{Int}} = Vector{Vector{Int}}()  # array of arrays
```

**Sets** (automatically marked with `uniqueItems: true`):
```julia
unique_tags::Set{String} = Set{String}()
```

**Dictionaries** (become objects with `additionalProperties`):
```julia
metadata::Dict{String, Any} = Dict{String, Any}()
settings::Dict{String, String} = Dict{String, String}()
```

**Tuples** (fixed-length arrays with specific types):
```julia
coordinates::Tuple{Float64, Float64} = (0.0, 0.0)  # [longitude, latitude]
rgb::Tuple{Int, Int, Int} = (0, 0, 0)              # [r, g, b]
```

## Type Mapping

Julia types are automatically mapped to JSON Schema types:

| Julia Type | JSON Schema Type |
|------------|------------------|
| `Int`, `Int64`, etc. | `"integer"` |
| `Float64`, `Float32` | `"number"` |
| `Bool` | `"boolean"` |
| `String` | `"string"` |
| `Nothing`, `Missing` | `"null"` |
| `Union{T, Nothing}` | `[<type-of-T>, "null"]` |
| `Vector{T}` | `{"type": "array", "items": <schema-of-T>}` |
| `Set{T}` | `{"type": "array", "items": <schema-of-T>, "uniqueItems": true}` |
| `Dict{K,V}` | `{"type": "object", "additionalProperties": <schema-of-V>}` |
| `Tuple{T1,T2,...}` | `{"type": "array", "prefixItems": [<schemas>], "minItems": N, "maxItems": N}` |
| Custom struct | `{"type": "object", "properties": {...}}` |
| `Any` | `{}` (allows anything) |

## Complete Example

```julia
using JSON

# Nested type for price
JSON.@defaults struct Price
    amount::Float64 = 0.0 &(json=(
        description="Price in specified currency",
        minimum=0.0,
        exclusiveMinimum=true
    ),)

    currency::String = "USD" &(json=(
        description="ISO 4217 currency code",
        pattern="^[A-Z]{3}\$",
        default="USD",
        examples=["USD", "EUR", "GBP"]
    ),)
end

# Main product type
JSON.@defaults struct Product
    id::String = "" &(json=(
        description="Unique product ID",
        format="uuid"
    ),)

    name::String = "" &(json=(
        description="Product name",
        minLength=1,
        maxLength=200
    ),)

    description::String = "" &(json=(
        maxLength=2000
    ),)

    price::Price = Price()

    tags::Vector{String} = String[] &(json=(
        description="Product tags",
        uniqueItems=true,
        maxItems=20
    ),)

    in_stock::Bool = true

    quantity::Int = 0 &(json=(minimum=0,),)
end

# Generate schema
schema = JSON.schema(Product,
    title="Product Schema",
    description="E-commerce product specification",
    id="https://api.example.com/schemas/product.json"
)

# Serialize to JSON
println(JSON.json(schema, pretty=true))
```

## Integration with JSON Parsing

The same field tags used for schema generation also work seamlessly with JSON parsing:

```julia
JSON.@defaults struct Config
    port::Int = 8080 &(json=(
        description="Server port",
        minimum=1,
        maximum=65535
    ),)

    host::String = "localhost" &(json=(
        description="Server hostname"
    ),)
end

# Generate schema
schema = JSON.schema(Config)

# Parse JSON using the same type
json_str = """{"port": 3000, "host": "example.com"}"""
config = JSON.parse(json_str, Config)
```

## Best Practices

1. **Use descriptive field names**: They become property names in the schema
2. **Add descriptions**: They serve as documentation
3. **Be specific with validation**: Use min/max, patterns, and formats where appropriate
4. **Use enums for fixed sets**: Better than free-form strings
5. **Mark optional fields correctly**: Use `Union{T, Nothing}` for optional fields
6. **Provide examples**: Especially helpful for complex formats
7. **Use `@defaults`**: Makes structs easier to work with and provides default values

## Comparison with Other Languages

### Python (Pydantic)
```python
from pydantic import BaseModel, Field

class User(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    age: Optional[int] = Field(None, ge=0, le=150)

schema = User.model_json_schema()
```

### Julia (JSON.jl)
```julia
JSON.@defaults struct User
    name::String = "" &(json=(minLength=1, maxLength=100),)
    age::Union{Int, Nothing} = nothing &(json=(minimum=0, maximum=150),)
end

schema = JSON.schema(User)
```

The Julia approach:
- ✅ Uses native Julia syntax
- ✅ Leverages the type system
- ✅ Works seamlessly with existing StructUtils infrastructure
- ✅ Same tags work for both schema generation AND JSON parsing
- ✅ Zero additional dependencies beyond StructUtils

## See Also

- [JSON Schema Specification](https://json-schema.org/)
- [StructUtils.jl Documentation](https://github.com/JuliaData/StructUtils.jl)
- [JSON.jl Documentation](https://github.com/JuliaIO/JSON.jl)
