# API Reference

```@contents
```

## JSON Schema Support

JSON.jl can derive JSON Schema documents directly from Julia types via [`JSON.jsonschema`](@ref). The returned value is a structured object built from helper types in the `JSON.JSONSchema` module (for example `JSON.JSONSchema.String`, `JSON.JSONSchema.Object`, etc.) so it can be further inspected or converted to JSON with the regular `JSON.json` function.

```julia
using JSON, StructUtils

@tags struct Example
    id::Int
    name::String &(json=(name="fullName",),)
    score::Union{Nothing, Float64}
end

schema = JSON.jsonschema(Example)
println(JSON.json(schema))
```

Schema generation understands StructUtils field tags (for example `minimum`, `maximum`, or `pattern`) and common idioms such as `Union{Nothing, T}` optional fields, arrays, dictionaries, sets, tuples, enums, and nested structs. Unsupported or ambiguous types throw an `ArgumentError` so they can be handled manually.

```@autodocs
Modules = [JSON]
```
