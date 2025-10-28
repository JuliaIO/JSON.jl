# JSONX - Simple JSON Parser

A simple, no-dependency JSON parser that can be vendored (copied/pasted) into other packages.

## Features

### Parsing
- `JSONX.parse(json_str::String)` - Parse a JSON string
- `JSONX.parse(bytes::AbstractVector{UInt8})` - Parse JSON from byte array
- `JSONX.parsefile(filename::String)` - Parse JSON from a file

### Writing
- `JSONX.json(value)` - Convert a Julia value to JSON string
- `JSONX.JSONText(str)` - `str` will be treated as raw JSON and inserted
  directly into the output.

### Supported Types

**Reading (JSON → Julia):**
- `null` → `nothing`
- `true`/`false` → `Bool`
- Numbers → `Int64` or `Float64` (integers without decimal/exponent → Int64, with overflow fallback to Float64)
- Strings → `String` (with full Unicode support)
- Arrays → `Vector{Any}`
- Objects → `Dict{String, Any}`

**Writing (Julia → JSON):**
- `nothing`/`missing` → `null`
- `Bool` → `true`/`false`
- `Number` → JSON number
- `AbstractString` → JSON string
- `AbstractVector`/`AbstractSet`/`Tuple` → JSON array
- `AbstractDict`/`NamedTuple` → JSON object
- `Symbol`/`Enum` → JSON string

### Unicode Support

JSONX includes full Unicode support:
- Proper Unicode escape sequence parsing (`\uXXXX`)
- UTF-16 surrogate pair handling
- Lone surrogate handling
- All standard JSON escape sequences (`\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`)

## Usage

```julia
using JSONX

# Parse JSON
data = JSONX.parse("{\"name\":\"John\",\"age\":30}")
# Returns: Dict("name" => "John", "age" => 30.0)

# Parse from bytes
bytes = Vector{UInt8}("{\"key\":\"value\"}")
data = JSONX.parse(bytes)

# Parse from file
data = JSONX.parsefile("data.json")

# Write JSON
json_str = JSONX.json(Dict("a" => 1, "b" => 2))
# Returns: "{\"a\":1,\"b\":2}"

# Unicode examples
JSONX.parse("\"Hello 世界! 🌍\"")  # Full Unicode support
JSONX.parse("\"\\u0048\\u0065\\u006C\\u006C\\u006F\"")  # Unicode escapes
```

## Error Handling

JSONX provides detailed error messages for invalid JSON:
- Unexpected end of input
- Invalid escape sequences
- Malformed Unicode escapes
- Trailing commas
- Control characters in strings
- Invalid number formats

## Limitations

Compared to the full JSON.jl package, JSONX is intentionally simplified:

- **Limited numeric types**: Parses as Int64 or Float64 only (no BigInt/BigFloat for very large numbers)
- **No custom type parsing**: Only returns basic Julia types
- **No configuration options**: Uses fixed defaults
- **No streaming**: Loads entire input into memory
- **No pretty printing**: Output is compact only
- **No schema validation**: Basic JSON validation only
- **No performance optimizations**: Simple, readable implementation

## Implementation Notes

- **No dependencies**: Uses only Base Julia functionality
- **Byte-level processing**: Uses `codeunit` for accurate string handling
- **Memory efficient**: Avoids unnecessary string concatenation
- **Error robust**: Comprehensive error checking and reporting

Note: Functions are not exported, so use `JSONX.parse` and `JSONX.json` with the module prefix.

## Changelog

- Fixed unicode handling when unescaping strings (https://github.com/JuliaIO/JSON.jl/pull/405).
- **Breaking**: Added support for parsing Int64's (https://github.com/JuliaIO/JSON.jl/pull/396).
- Added `JSONText` (https://github.com/JuliaIO/JSON.jl/pull/394).
