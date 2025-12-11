# JSON Schema generation and validation from Julia types
# Provides a simple, convenient interface for generating JSON Schema v7 specifications

"""
    Schema{T}

A typed JSON Schema for type `T`. Contains the schema specification and can be used
for validation via `JSON.isvalid`.

# Fields
- `type::Type{T}`: The Julia type this schema describes
- `spec::Object{String, Any}`: The JSON Schema specification

# Example
```julia
schema = JSON.schema(User)
instance = User("alice", "alice@example.com", 25)
is_valid = JSON.isvalid(schema, instance)
```
"""
# Context for tracking type definitions during schema generation with $ref support
mutable struct SchemaContext
    # Map from Type to definition name
    type_names::Dict{Type, String}
    # Map from definition name to schema
    definitions::Object{String, Any}
    # Stack to detect circular references during generation
    generation_stack::Vector{Type}
    # Where to store definitions: :definitions (Draft 7) or :defs (Draft 2019+)
    defs_location::Symbol

    SchemaContext(defs_location::Symbol=:definitions) = new(
        Dict{Type, String}(),
        Object{String, Any}(),
        Type[],
        defs_location
    )
end

struct Schema{T}
    type::Type{T}
    spec::Object{String, Any}
    context::Union{Nothing, SchemaContext}

    # Existing constructor (unchanged for backwards compatibility)
    Schema{T}(type::Type{T}, spec::Object{String, Any}) where T = new{T}(type, spec, nothing)
    # New constructor with context
    Schema{T}(type::Type{T}, spec::Object{String, Any}, ctx::Union{Nothing, SchemaContext}) where T = new{T}(type, spec, ctx)
end

Base.getindex(s::Schema, key) = s.spec[key]
Base.haskey(s::Schema, key) = haskey(s.spec, key)
Base.keys(s::Schema) = keys(s.spec)
Base.get(s::Schema, key, default) = get(s.spec, key, default)

# Helper functions for $ref support

"""
    defs_key_name(defs_location::Symbol) -> String

Get the proper key name for definitions/defs.
Converts :defs to "\$defs" and :definitions to "definitions".
"""
function defs_key_name(defs_location::Symbol)
    return defs_location == :defs ? "\$defs" : String(defs_location)
end

"""
    type_to_ref_name(::Type{T}) -> String

Generate a reference name for a type. Uses fully qualified names for disambiguation.
"""
function type_to_ref_name(::Type{T}) where T
    mod = T.name.module
    typename = nameof(T)

    # Handle parametric types: Vector{Int} → "Vector_Int"
    if !isempty(T.parameters) && all(x -> x isa Type, T.parameters)
        param_str = join([type_to_ref_name(p) for p in T.parameters], "_")
        typename = "$(typename)_$(param_str)"
    end

    # Create clean reference name
    if mod === Main
        return String(typename)
    else
        # Use module path for disambiguation
        modpath = String(nameof(mod))
        return "$(modpath).$(typename)"
    end
end

"""
    should_use_ref(::Type{T}, ctx::Union{Nothing, SchemaContext}) -> Bool

Determine if a type should be referenced via \$ref instead of inlined.
"""
function should_use_ref(::Type{T}, ctx::Union{Nothing, SchemaContext}) where T
    # Never use refs if no context provided
    ctx === nothing && return false

    # Use ref for struct types that:
    # 1. Are concrete types (can be instantiated)
    # 2. Are struct types (not primitives)
    # 3. Are user-defined (not from Base/Core)

    if !isconcretetype(T) || !isstructtype(T)
        return false
    end

    modname = string(T.name.module)
    if modname in ("Core", "Base") || startswith(modname, "Base.")
        return false
    end

    return true
end

"""
    schema(T::Type; title=nothing, description=nothing, id=nothing, draft="https://json-schema.org/draft-07/schema#", all_fields_required=false, additionalProperties=nothing)

Generate a JSON Schema for type `T`. The schema is returned as a JSON-serializable `Object`.

# Keyword Arguments
- `all_fields_required::Bool=false`: If `true`, all fields of object schemas will be added to the required list.
- `additionalProperties::Union{Nothing,Bool}=nothing`: If `true` or `false`, sets `additionalProperties` recursively on the root and all child object schemas. If `nothing`, no additional action is taken.

Field-level schema properties can be specified using StructUtils field tags with the `json` key:

# Example
```julia
@defaults struct User
    id::Int = 0 &(json=(
        description="Unique user identifier",
        minimum=1
    ),)
    name::String = "" &(json=(
        description="User's full name",
        minLength=1,
        maxLength=100
    ),)
    email::Union{String, Nothing} = nothing &(json=(
        description="Email address",
        format="email"
    ),)
    age::Union{Int, Nothing} = nothing &(json=(
        minimum=0,
        maximum=150,
        exclusiveMaximum=false
    ),)
end

schema = JSON.schema(User)
```

# Supported Field Tag Properties

## String validation
- `minLength::Int`: Minimum string length
- `maxLength::Int`: Maximum string length
- `pattern::String`: Regular expression pattern (ECMA-262)
- `format::String`: Format hint (e.g., "email", "uri", "date-time", "uuid")

## Numeric validation
- `minimum::Number`: Minimum value (inclusive)
- `maximum::Number`: Maximum value (inclusive)
- `exclusiveMinimum::Bool|Number`: Exclusive minimum
- `exclusiveMaximum::Bool|Number`: Exclusive maximum
- `multipleOf::Number`: Value must be multiple of this

## Array validation
- `minItems::Int`: Minimum array length
- `maxItems::Int`: Maximum array length
- `uniqueItems::Bool`: All items must be unique

## Object validation
- `minProperties::Int`: Minimum number of properties
- `maxProperties::Int`: Maximum number of properties

## Generic
- `description::String`: Human-readable description
- `title::String`: Short title for the field
- `default::Any`: Default value
- `examples::Vector`: Example values
- `_const::Any`: Field must have this exact value (use `_const` since `const` is a reserved keyword)
- `enum::Vector`: Field must be one of these values
- `required::Bool`: Override required inference (default: true for non-Union{T,Nothing} types)

## Composition
- `allOf::Vector{Type}`: Must validate against all schemas
- `anyOf::Vector{Type}`: Must validate against at least one schema
- `oneOf::Vector{Type}`: Must validate against exactly one schema

The function automatically:
- Maps Julia types to JSON Schema types
- Marks non-`Nothing` union fields as required
- Handles nested types and arrays
- Supports custom types via registered converters

# Returns
A `Schema{T}` object that contains both the type information and the JSON Schema specification.
The schema can be used for validation with `JSON.isvalid(schema, instance)`.
"""
function schema(::Type{T};
                title::Union{String, Nothing}=nothing,
                description::Union{String, Nothing}=nothing,
                id::Union{String, Nothing}=nothing,
                draft::String="https://json-schema.org/draft-07/schema#",
                refs::Union{Bool, Symbol}=false,
                context::Union{Nothing, SchemaContext}=nothing,
                all_fields_required::Bool=false,
                additionalProperties::Union{Nothing,Bool}=nothing) where {T}

    # Determine context based on parameters
    ctx = if context !== nothing
        context  # Use provided context
    elseif refs !== false
        # Create new context based on refs option
        defs_loc = refs === true ? :definitions : refs
        SchemaContext(defs_loc)
    else
        nothing  # No refs - use current inline behavior
    end

    obj = Object{String, Any}()
    obj["\$schema"] = draft

    if id !== nothing
        obj["\$id"] = id
    end

    if title !== nothing
        obj["title"] = title
    elseif hasproperty(T, :name)
        obj["title"] = string(nameof(T))
    end

    if description !== nothing
        obj["description"] = description
    end

    # Generate the type schema and merge it (pass context and all_fields_required)
    type_schema = _type_to_schema(T, ctx; all_fields_required=all_fields_required)
    for (k, v) in type_schema
        obj[k] = v
    end

    # Add definitions if context was used
    if ctx !== nothing && !isempty(ctx.definitions)
        # Convert symbol to proper key name (defs => $defs, definitions => definitions)
        defs_key = ctx.defs_location == :defs ? "\$defs" : String(ctx.defs_location)
        obj[defs_key] = ctx.definitions
    end

    # Recursively set additionalProperties if specified
    # This will process the root schema and all nested schemas, including definitions
    if additionalProperties !== nothing
        _set_additional_properties_recursive!(obj, additionalProperties, ctx)
    end

    return Schema{T}(T, obj, ctx)
end

# Internal: Convert a Julia type to JSON Schema representation
function _type_to_schema(::Type{T}, ctx::Union{Nothing, SchemaContext}=nothing; all_fields_required::Bool=false) where {T}
    # Handle Any and abstract types specially to avoid infinite recursion
    if T === Any
        return Object{String, Any}()  # Allow any type
    end

    # Handle Union types (including Union{T, Nothing})
    if T isa Union
        return _union_to_schema(T, ctx; all_fields_required=all_fields_required)
    end

    # Primitive types (check Bool first since Bool <: Integer in Julia!)
    if T === Bool
        return Object{String, Any}("type" => "boolean")
    elseif T === Nothing || T === Missing
        return Object{String, Any}("type" => "null")
    elseif T === Int || T === Int64 || T === Int32 || T === Int16 || T === Int8 ||
           T === UInt || T === UInt64 || T === UInt32 || T === UInt16 || T === UInt8 ||
           T <: Integer
        return Object{String, Any}("type" => "integer")
    elseif T === Float64 || T === Float32 || T <: AbstractFloat
        return Object{String, Any}("type" => "number")
    elseif T === String || T <: AbstractString
        return Object{String, Any}("type" => "string")
    end

    # Handle parametric types
    if T <: AbstractVector
        return _array_to_schema(T, ctx; all_fields_required=all_fields_required)
    elseif T <: AbstractDict
        return _dict_to_schema(T, ctx; all_fields_required=all_fields_required)
    elseif T <: AbstractSet
        return _set_to_schema(T, ctx; all_fields_required=all_fields_required)
    elseif T <: Tuple
        return _tuple_to_schema(T, ctx; all_fields_required=all_fields_required)
    end

    # Struct types - try to process user-defined structs
    if isconcretetype(T) && !isabstracttype(T) && isstructtype(T)
        # Avoid processing internal compiler types that could cause issues
        modname = string(T.name.module)
        if (T <: NamedTuple) || (!(modname in ("Core", "Base")) && !startswith(modname, "Base."))
            try
                # Check if we should use $ref for this struct
                if should_use_ref(T, ctx)
                    return _struct_to_schema_with_refs(T, ctx; all_fields_required=all_fields_required)
                else
                    return _struct_to_schema_core(T, ctx; all_fields_required=all_fields_required)
                end
            catch
                # If struct processing fails, fall through to fallback
            end
        end
    end

    # Fallback: allow any type
    return Object{String, Any}()
end

# Handle Union types
function _union_to_schema(::Type{T}, ctx::Union{Nothing, SchemaContext}=nothing; all_fields_required::Bool=false) where {T}
    types = Base.uniontypes(T)

    # Special case: Union{T, Nothing} - make nullable
    if length(types) == 2 && (Nothing in types || Missing in types)
        non_null_type = types[1] === Nothing || types[1] === Missing ? types[2] : types[1]
        schema = _type_to_schema(non_null_type, ctx; all_fields_required=all_fields_required)

        # If the schema is a $ref, we need to use oneOf (can't mix $ref with other properties)
        if haskey(schema, "\$ref")
            obj = Object{String, Any}()
            obj["oneOf"] = [schema, Object{String, Any}("type" => "null")]
            return obj
        end

        # Otherwise, add null as allowed type
        if haskey(schema, "type")
            if schema["type"] isa Vector
                push!(schema["type"], "null")
            else
                schema["type"] = [schema["type"], "null"]
            end
        else
            schema["type"] = "null"
        end

        return schema
    end

    # General union: use oneOf (exactly one must match)
    # Note: We use oneOf instead of anyOf because Julia's Union types
    # require the value to be exactly one of the types, not multiple
    obj = Object{String, Any}()
    obj["oneOf"] = [_type_to_schema(t, ctx; all_fields_required=all_fields_required) for t in types]
    return obj
end

# Handle array types
function _array_to_schema(::Type{T}, ctx::Union{Nothing, SchemaContext}=nothing; all_fields_required::Bool=false) where {T}
    obj = Object{String, Any}("type" => "array")

    # Get element type
    if T <: AbstractVector
        eltype_t = eltype(T)
        obj["items"] = _type_to_schema(eltype_t, ctx; all_fields_required=all_fields_required)
    end

    return obj
end

# Handle dictionary types
function _dict_to_schema(::Type{T}, ctx::Union{Nothing, SchemaContext}=nothing; all_fields_required::Bool=false) where {T}
    obj = Object{String, Any}("type" => "object")

    # Get value type for additionalProperties
    if T <: AbstractDict
        valtype_t = valtype(T)
        if valtype_t !== Union{}
            # For Any type, we return an empty schema which means "allow anything"
            obj["additionalProperties"] = _type_to_schema(valtype_t, ctx; all_fields_required=all_fields_required)
        end
    end

    return obj
end

# Handle set types
function _set_to_schema(::Type{T}, ctx::Union{Nothing, SchemaContext}=nothing; all_fields_required::Bool=false) where {T}
    obj = Object{String, Any}("type" => "array")
    obj["uniqueItems"] = true

    # Get element type
    if T <: AbstractSet
        eltype_t = eltype(T)
        obj["items"] = _type_to_schema(eltype_t, ctx; all_fields_required=all_fields_required)
    end

    return obj
end

# Handle tuple types
function _tuple_to_schema(::Type{T}, ctx::Union{Nothing, SchemaContext}=nothing; all_fields_required::Bool=false) where {T}
    obj = Object{String, Any}("type" => "array")

    # Tuples have fixed-length items with specific types
    # JSON Schema Draft 7 uses "items" as an array for tuple validation
    if T.parameters !== () && all(x -> x isa Type, T.parameters)
        obj["items"] = [_type_to_schema(t, ctx; all_fields_required=all_fields_required) for t in T.parameters]
        obj["minItems"] = length(T.parameters)
        obj["maxItems"] = length(T.parameters)
    end

    return obj
end

# Handle struct types with $ref support (circular reference detection)
function _struct_to_schema_with_refs(::Type{T}, ctx::SchemaContext; all_fields_required::Bool=false) where {T}
    # Get the proper key name for definitions
    defs_key = defs_key_name(ctx.defs_location)

    # Check if we're already generating this type (circular reference!)
    if T in ctx.generation_stack
        # Generate $ref immediately - definition will be completed later
        ref_name = type_to_ref_name(T)
        ctx.type_names[T] = ref_name
        return Object{String, Any}("\$ref" => "#/$(defs_key)/$(ref_name)")
    end

    # Check if already defined (deduplication)
    if haskey(ctx.type_names, T)
        ref_name = ctx.type_names[T]
        return Object{String, Any}("\$ref" => "#/$(defs_key)/$(ref_name)")
    end

    # Mark as being generated (prevents infinite recursion)
    push!(ctx.generation_stack, T)
    ref_name = type_to_ref_name(T)
    ctx.type_names[T] = ref_name

    try
        # Generate the actual schema (may recursively call this function)
        schema_obj = _struct_to_schema_core(T, ctx; all_fields_required=all_fields_required)

        # Store in definitions
        ctx.definitions[ref_name] = schema_obj

        # Return a reference
        return Object{String, Any}("\$ref" => "#/$(defs_key)/$(ref_name)")
    finally
        # Always pop from stack, even if error occurs
        pop!(ctx.generation_stack)
    end
end

# Handle struct types (core logic without ref handling)
function _struct_to_schema_core(::Type{T}, ctx::Union{Nothing, SchemaContext}=nothing; all_fields_required::Bool=false) where {T}
    obj = Object{String, Any}("type" => "object")
    properties = Object{String, Any}()
    required = String[]

    # Iterate over fields
    if fieldcount(T) == 0
        obj["properties"] = properties
        return obj
    end

    style = StructUtils.DefaultStyle()
    # Get all field tags at once (returns NamedTuple with field names as keys)
    all_field_tags = StructUtils.fieldtags(style, T)

    for i in 1:fieldcount(T)
        fname = fieldname(T, i)
        ftype = fieldtype(T, i)

        # Get field tags for this specific field
        field_tags = haskey(all_field_tags, fname) ? all_field_tags[fname] : nothing
        tags = field_tags isa NamedTuple && haskey(field_tags, :json) ? field_tags.json : nothing

        # Determine JSON key name (may be renamed via tags)
        json_name = string(fname)
        if tags isa NamedTuple && haskey(tags, :name)
            json_name = string(tags.name)
        end

        # Skip ignored fields
        if tags isa NamedTuple && get(tags, :ignore, false)
            continue
        end

        # Generate schema for this field (pass context for ref support)
        field_schema = _type_to_schema(ftype, ctx; all_fields_required=all_fields_required)

        # Apply field tags to schema
        if tags isa NamedTuple
            _apply_field_tags!(field_schema, tags, ftype)
        end

        # Check if field should be required
        is_required = all_fields_required || _is_required_field(ftype, tags)
        if is_required
            push!(required, json_name)
        end

        properties[json_name] = field_schema
    end

    if length(properties) > 0
        obj["properties"] = properties
    end

    if length(required) > 0
        obj["required"] = required
    end

    return obj
end

# Determine if a field is required
function _is_required_field(::Type{T}, tags) where {T}
    # Check explicit required tag
    if tags isa NamedTuple && haskey(tags, :required)
        return Bool(tags.required)
    end

    # By default, Union{T, Nothing} fields are optional
    if T isa Union
        types = Base.uniontypes(T)
        if Nothing in types || Missing in types
            return false
        end
    end

    # All other fields are required by default
    return true
end

# Recursively set additionalProperties on all object schemas
function _set_additional_properties_recursive!(schema_obj::Object{String, Any}, value::Bool, ctx::Union{Nothing, SchemaContext})
    # Skip $ref schemas - they're references, not actual schemas
    if haskey(schema_obj, "\$ref")
        return
    end

    # Set additionalProperties on object schemas
    # Check if it's an object type or has properties (which indicates an object schema)
    if (haskey(schema_obj, "type") && schema_obj["type"] == "object") || haskey(schema_obj, "properties")
        schema_obj["additionalProperties"] = value
    end

    # Recursively process nested schemas
    # Properties
    if haskey(schema_obj, "properties")
        for (_, prop_schema) in schema_obj["properties"]
            if prop_schema isa Object{String, Any}
                _set_additional_properties_recursive!(prop_schema, value, ctx)
            end
        end
    end

    # Items (for arrays)
    if haskey(schema_obj, "items")
        items = schema_obj["items"]
        if items isa Object{String, Any}
            _set_additional_properties_recursive!(items, value, ctx)
        elseif items isa AbstractVector
            for item_schema in items
                if item_schema isa Object{String, Any}
                    _set_additional_properties_recursive!(item_schema, value, ctx)
                end
            end
        end
    end

    # Composition schemas
    for key in ["allOf", "anyOf", "oneOf"]
        if haskey(schema_obj, key) && schema_obj[key] isa AbstractVector
            for sub_schema in schema_obj[key]
                if sub_schema isa Object{String, Any}
                    _set_additional_properties_recursive!(sub_schema, value, ctx)
                end
            end
        end
    end

    # Conditional schemas
    for key in ["if", "then", "else"]
        if haskey(schema_obj, key) && schema_obj[key] isa Object{String, Any}
            _set_additional_properties_recursive!(schema_obj[key], value, ctx)
        end
    end

    # Not schema
    if haskey(schema_obj, "not") && schema_obj["not"] isa Object{String, Any}
        _set_additional_properties_recursive!(schema_obj["not"], value, ctx)
    end

    # Contains schema (for arrays)
    if haskey(schema_obj, "contains") && schema_obj["contains"] isa Object{String, Any}
        _set_additional_properties_recursive!(schema_obj["contains"], value, ctx)
    end

    # Pattern properties
    if haskey(schema_obj, "patternProperties")
        for (_, pattern_schema) in schema_obj["patternProperties"]
            if pattern_schema isa Object{String, Any}
                _set_additional_properties_recursive!(pattern_schema, value, ctx)
            end
        end
    end

    # Property names schema
    if haskey(schema_obj, "propertyNames") && schema_obj["propertyNames"] isa Object{String, Any}
        _set_additional_properties_recursive!(schema_obj["propertyNames"], value, ctx)
    end

    # Additional items (for tuples)
    if haskey(schema_obj, "additionalItems") && schema_obj["additionalItems"] isa Object{String, Any}
        _set_additional_properties_recursive!(schema_obj["additionalItems"], value, ctx)
    end

    # Dependencies (schema-based)
    if haskey(schema_obj, "dependencies")
        for (_, dep) in schema_obj["dependencies"]
            if dep isa Object{String, Any}
                _set_additional_properties_recursive!(dep, value, ctx)
            end
        end
    end

    # Definitions/$defs (process all definitions recursively)
    for defs_key in ["definitions", "\$defs"]
        if haskey(schema_obj, defs_key) && schema_obj[defs_key] isa Object{String, Any}
            for (_, def_schema) in schema_obj[defs_key]
                if def_schema isa Object{String, Any}
                    _set_additional_properties_recursive!(def_schema, value, ctx)
                end
            end
        end
    end
end

# Apply field tags to a schema object
function _apply_field_tags!(schema::Object{String, Any}, tags::NamedTuple, ftype::Type)
    # String validation
    haskey(tags, :minLength) && (schema["minLength"] = tags.minLength)
    haskey(tags, :maxLength) && (schema["maxLength"] = tags.maxLength)
    haskey(tags, :pattern) && (schema["pattern"] = tags.pattern)
    haskey(tags, :format) && (schema["format"] = string(tags.format))

    # Numeric validation
    haskey(tags, :minimum) && (schema["minimum"] = tags.minimum)
    haskey(tags, :maximum) && (schema["maximum"] = tags.maximum)
    haskey(tags, :exclusiveMinimum) && (schema["exclusiveMinimum"] = tags.exclusiveMinimum)
    haskey(tags, :exclusiveMaximum) && (schema["exclusiveMaximum"] = tags.exclusiveMaximum)
    haskey(tags, :multipleOf) && (schema["multipleOf"] = tags.multipleOf)

    # Array validation
    haskey(tags, :minItems) && (schema["minItems"] = tags.minItems)
    haskey(tags, :maxItems) && (schema["maxItems"] = tags.maxItems)
    haskey(tags, :uniqueItems) && (schema["uniqueItems"] = tags.uniqueItems)

    # Items schema (can be single schema or array for tuple validation)
    if haskey(tags, :items)
        items = tags.items
        if items isa AbstractVector
            # Tuple validation: array of schemas
            schema["items"] = [item isa Type ? _type_to_schema(item) : item for item in items]
        else
            # Single schema applies to all items
            schema["items"] = items isa Type ? _type_to_schema(items) : items
        end
    end

    # Object validation
    haskey(tags, :minProperties) && (schema["minProperties"] = tags.minProperties)
    haskey(tags, :maxProperties) && (schema["maxProperties"] = tags.maxProperties)

    # Generic properties
    haskey(tags, :description) && (schema["description"] = string(tags.description))
    haskey(tags, :title) && (schema["title"] = string(tags.title))
    haskey(tags, :examples) && (schema["examples"] = collect(tags.examples))
    (haskey(tags, :_const) || haskey(tags, Symbol("const"))) && (schema["const"] = get(tags, :_const, get(tags, Symbol("const"), nothing)))
    haskey(tags, :enum) && (schema["enum"] = collect(tags.enum))

    # Default value
    if haskey(tags, :default)
        schema["default"] = tags.default
    end

    # Composition (allOf, anyOf, oneOf)
    # These can be either Type objects or Dict/Object schemas
    if haskey(tags, :allOf) && tags.allOf isa Vector
        schema["allOf"] = [t isa Type ? _type_to_schema(t) : t for t in tags.allOf]
    end
    if haskey(tags, :anyOf) && tags.anyOf isa Vector
        schema["anyOf"] = [t isa Type ? _type_to_schema(t) : t for t in tags.anyOf]
    end
    if haskey(tags, :oneOf) && tags.oneOf isa Vector
        schema["oneOf"] = [t isa Type ? _type_to_schema(t) : t for t in tags.oneOf]
    end

    # Negation (not)
    if haskey(tags, :not)
        schema["not"] = tags.not isa Type ? _type_to_schema(tags.not) : tags.not
    end

    # Array contains
    if haskey(tags, :contains)
        schema["contains"] = tags.contains isa Type ? _type_to_schema(tags.contains) : tags.contains
    end
end

# Validation functionality

# Helper: Resolve a $ref reference
function _resolve_ref(ref_path::String, root_schema::Object{String, Any})
    # Handle JSON Pointer syntax: "#/definitions/User" or "#/$defs/User"
    if startswith(ref_path, "#/")
        parts = split(ref_path[3:end], '/')  # Skip "#/"
        current = root_schema
        for part in parts
            # Convert SubString to String for Object key lookup
            key = String(part)
            if !haskey(current, key)
                error("Reference not found: $ref_path")
            end
            current = current[key]
        end
        return current
    end

    error("External refs not supported: $ref_path")
end

"""
    ValidationResult

Result of a schema validation operation.

# Fields
- `is_valid::Bool`: Whether the validation was successful
- `errors::Vector{String}`: List of validation error messages (empty if valid)
"""
struct ValidationResult
    is_valid::Bool
    errors::Vector{String}
end

"""
    validate(schema::Schema{T}, instance::T) -> ValidationResult

Validate that `instance` satisfies all constraints defined in `schema`.
Returns a `ValidationResult` containing success status and any error messages.

# Example
```julia
result = JSON.validate(schema, instance)
if !result.is_valid
    for err in result.errors
        println(err)
    end
end
```
"""
function validate(schema::Schema{T}, instance::T) where {T}
    errors = String[]
    # Pass root schema for \$ref resolution
    _validate_instance(schema.spec, instance, T, "", errors, false, schema.spec)
    return ValidationResult(isempty(errors), errors)
end

"""
    isvalid(schema::Schema{T}, instance::T; verbose=false) -> Bool

Validate that `instance` satisfies all constraints defined in `schema`.

This function checks that the instance meets all validation requirements specified
in the schema's field tags, including:
- String constraints (minLength, maxLength, pattern, format)
- Numeric constraints (minimum, maximum, exclusiveMinimum, exclusiveMaximum, multipleOf)
- Array constraints (minItems, maxItems, uniqueItems)
- Enum and const values
- Nested struct validation

# Arguments
- `schema::Schema{T}`: The schema to validate against
- `instance::T`: The instance to validate
- `verbose::Bool=false`: If true, print detailed validation errors to stdout

# Returns
`true` if the instance is valid, `false` otherwise

# Example
```julia
JSON.@defaults struct User
    name::String = "" &(json=(minLength=1, maxLength=100),)
    age::Int = 0 &(json=(minimum=0, maximum=150),)
end

schema = JSON.schema(User)
user1 = User("Alice", 25)
user2 = User("", 200)  # Invalid: empty name, age too high

JSON.isvalid(schema, user1)  # true
JSON.isvalid(schema, user2)  # false
JSON.isvalid(schema, user2, verbose=true)  # false, with error messages
```
"""
function Base.isvalid(schema::Schema{T}, instance::T; verbose::Bool=false) where {T}
    result = validate(schema, instance)

    if verbose && !result.is_valid
        for err in result.errors
            println("  ❌ ", err)
        end
    end

    return result.is_valid
end

# Internal: Validate an instance against a schema
function _validate_instance(schema_obj, instance, ::Type{T}, path::String, errors::Vector{String}, verbose::Bool, root::Object{String, Any}) where {T}
    # Handle $ref - resolve and validate against resolved schema
    if haskey(schema_obj, "\$ref")
        ref_path = schema_obj["\$ref"]
        try
            resolved_schema = _resolve_ref(ref_path, root)
            return _validate_instance(resolved_schema, instance, T, path, errors, verbose, root)
        catch e
            push!(errors, "$path: error resolving \$ref: $(e.msg)")
            return
        end
    end

    # Handle structs
    if isstructtype(T) && isconcretetype(T) && haskey(schema_obj, "properties")
        properties = schema_obj["properties"]
        required = get(schema_obj, "required", String[])
        
        style = StructUtils.DefaultStyle()
        all_field_tags = StructUtils.fieldtags(style, T)
        
        for i in 1:fieldcount(T)
            fname = fieldname(T, i)
            ftype = fieldtype(T, i)
            fvalue = getfield(instance, fname)
            
            # Get field tags
            field_tags = haskey(all_field_tags, fname) ? all_field_tags[fname] : nothing
            tags = field_tags isa NamedTuple && haskey(field_tags, :json) ? field_tags.json : nothing
            
            # Skip ignored fields
            if tags isa NamedTuple && get(tags, :ignore, false)
                continue
            end
            
            # Get JSON name (may be renamed)
            json_name = string(fname)
            if tags isa NamedTuple && haskey(tags, :name)
                json_name = string(tags.name)
            end
            
            # Check if field is in schema
            if haskey(properties, json_name)
                field_schema = properties[json_name]
                field_path = isempty(path) ? json_name : "$path.$json_name"
                # Use actual value type for validation, not field type (handles Union{T, Nothing} properly)
                val_type = fvalue === nothing || fvalue === missing ? ftype : typeof(fvalue)
                _validate_value(field_schema, fvalue, val_type, tags, field_path, errors, verbose, root)
            end
        end

        # Validate propertyNames - property names must match schema
        if haskey(schema_obj, "propertyNames")
            prop_names_schema = schema_obj["propertyNames"]
            for i in 1:fieldcount(T)
                fname = fieldname(T, i)
                field_tags = haskey(all_field_tags, fname) ? all_field_tags[fname] : nothing
                tags = field_tags isa NamedTuple && haskey(field_tags, :json) ? field_tags.json : nothing

                # Skip ignored fields
                if tags isa NamedTuple && get(tags, :ignore, false)
                    continue
                end

                # Get JSON name
                json_name = string(fname)
                if tags isa NamedTuple && haskey(tags, :name)
                    json_name = string(tags.name)
                end

                # Validate the property name itself as a string
                prop_errors = String[]
                _validate_value(prop_names_schema, json_name, String, nothing, path, prop_errors, false, root)
                if !isempty(prop_errors)
                    push!(errors, "$path: property name '$json_name' is invalid")
                end
            end
        end

        # Validate dependencies - if property X exists, properties Y and Z must exist
        if haskey(schema_obj, "dependencies")
            dependencies = schema_obj["dependencies"]
            for i in 1:fieldcount(T)
                fname = fieldname(T, i)
                fvalue = getfield(instance, fname)
                field_tags = haskey(all_field_tags, fname) ? all_field_tags[fname] : nothing
                tags = field_tags isa NamedTuple && haskey(field_tags, :json) ? field_tags.json : nothing

                # Skip ignored fields
                if tags isa NamedTuple && get(tags, :ignore, false)
                    continue
                end

                # Skip fields with nothing/missing values (treat as "not present")
                if fvalue === nothing || fvalue === missing
                    continue
                end

                # Get JSON name
                json_name = string(fname)
                if tags isa NamedTuple && haskey(tags, :name)
                    json_name = string(tags.name)
                end

                # If this property exists in dependencies
                if haskey(dependencies, json_name)
                    dep = dependencies[json_name]

                    # Dependencies can be an array of required properties
                    if dep isa Vector
                        for required_prop in dep
                            # Check if the required property exists in the struct and is not nothing/missing
                            found = false
                            for j in 1:fieldcount(T)
                                other_fname = fieldname(T, j)
                                other_fvalue = getfield(instance, j)
                                other_tags = haskey(all_field_tags, other_fname) ? all_field_tags[other_fname] : nothing
                                other_json_tags = other_tags isa NamedTuple && haskey(other_tags, :json) ? other_tags.json : nothing

                                other_json_name = string(other_fname)
                                if other_json_tags isa NamedTuple && haskey(other_json_tags, :name)
                                    other_json_name = string(other_json_tags.name)
                                end

                                # Check if name matches and value is not nothing/missing
                                if other_json_name == required_prop && other_fvalue !== nothing && other_fvalue !== missing
                                    found = true
                                    break
                                end
                            end

                            if !found
                                push!(errors, "$path: property '$json_name' requires property '$required_prop' to exist")
                            end
                        end
                    # Dependencies can also be a schema (schema-based dependency)
                    elseif dep isa Object
                        # If the property exists, validate the whole instance against the dependency schema
                        _validate_value(dep, instance, T, nothing, path, errors, verbose, root)
                    end
                end
            end
        end

        # Validate additionalProperties for structs
        # Check if there are fields in the struct not defined in the schema
        if haskey(schema_obj, "additionalProperties")
            additional_allowed = schema_obj["additionalProperties"]

            # If additionalProperties is false, no extra properties allowed
            if additional_allowed === false
                for i in 1:fieldcount(T)
                    fname = fieldname(T, i)
                    field_tags = haskey(all_field_tags, fname) ? all_field_tags[fname] : nothing
                    tags = field_tags isa NamedTuple && haskey(field_tags, :json) ? field_tags.json : nothing

                    # Skip ignored fields
                    if tags isa NamedTuple && get(tags, :ignore, false)
                        continue
                    end

                    # Get JSON name
                    json_name = string(fname)
                    if tags isa NamedTuple && haskey(tags, :name)
                        json_name = string(tags.name)
                    end

                    # Check if this property is defined in the schema
                    if !haskey(properties, json_name)
                        push!(errors, "$path: additional property '$json_name' not allowed")
                    end
                end
            # If additionalProperties is a schema, validate extra properties against it
            elseif additional_allowed isa Object
                for i in 1:fieldcount(T)
                    fname = fieldname(T, i)
                    ftype = fieldtype(T, i)
                    fvalue = getfield(instance, fname)
                    field_tags = haskey(all_field_tags, fname) ? all_field_tags[fname] : nothing
                    tags = field_tags isa NamedTuple && haskey(field_tags, :json) ? field_tags.json : nothing

                    # Skip ignored fields
                    if tags isa NamedTuple && get(tags, :ignore, false)
                        continue
                    end

                    # Get JSON name
                    json_name = string(fname)
                    if tags isa NamedTuple && haskey(tags, :name)
                        json_name = string(tags.name)
                    end

                    # If this property is not in the schema, validate it against additionalProperties
                    if !haskey(properties, json_name)
                        field_path = isempty(path) ? json_name : "$path.$json_name"
                        val_type = fvalue === nothing || fvalue === missing ? ftype : typeof(fvalue)
                        _validate_value(additional_allowed, fvalue, val_type, tags, field_path, errors, verbose, root)
                    end
                end
            end
        end

        return
    end

    # For non-struct types, validate directly
    _validate_value(schema_obj, instance, T, nothing, path, errors, verbose, root)
end

# Internal: Validate a single value against schema constraints
function _validate_value(schema, value, ::Type{T}, tags, path::String, errors::Vector{String}, verbose::Bool, root::Object{String, Any}) where {T}
    # Handle $ref - resolve and validate against resolved schema
    if haskey(schema, "\$ref")
        ref_path = schema["\$ref"]
        try
            resolved_schema = _resolve_ref(ref_path, root)
            # Recursively validate with resolved schema
            return _validate_value(resolved_schema, value, T, tags, path, errors, verbose, root)
        catch e
            push!(errors, "$path: error resolving \$ref: $(e.msg)")
            return
        end
    end

    # Handle Nothing/Missing
    if value === nothing || value === missing
        # Check if null is allowed
        schema_type = get(schema, "type", nothing)
        if schema_type isa Vector && !("null" in schema_type)
            push!(errors, "$path: null value not allowed")
        elseif schema_type isa String && schema_type != "null"
            push!(errors, "$path: null value not allowed")
        end
        return
    end

    # Validate type if specified in schema
    if haskey(schema, "type")
        _validate_type(schema["type"], value, path, errors)
    end

    # String validation
    if value isa AbstractString
        _validate_string(schema, tags, string(value), path, errors)
    end

    # Numeric validation
    if value isa Number
        _validate_number(schema, tags, value, path, errors)
    end

    # Array validation
    if value isa AbstractVector
        _validate_array(schema, tags, value, path, errors, verbose, root)
    end

    # Tuple validation (treat as array for JSON Schema purposes)
    if value isa Tuple
        _validate_array(schema, tags, collect(value), path, errors, verbose, root)
    end

    # Set validation
    if value isa AbstractSet
        _validate_array(schema, tags, collect(value), path, errors, verbose, root)
    end

    # Enum validation
    if haskey(schema, "enum")
        if !(value in schema["enum"])
            push!(errors, "$path: value must be one of $(schema["enum"]), got $(repr(value))")
        end
    end

    # Const validation
    if haskey(schema, "const")
        if value != schema["const"]
            push!(errors, "$path: value must be $(repr(schema["const"])), got $(repr(value))")
        end
    end

    # Nested object validation
    if haskey(schema, "properties") && isstructtype(T) && isconcretetype(T)
        _validate_instance(schema, value, T, path, errors, verbose, root)
    end

    # Dict/Object validation (properties, patternProperties, propertyNames for Dicts)
    if value isa AbstractDict
        # Validate properties for Dict
        if haskey(schema, "properties")
            properties = schema["properties"]
            required = get(schema, "required", String[])

            # Validate each property
            for (prop_name, prop_schema) in properties
                if haskey(value, prop_name) || haskey(value, Symbol(prop_name))
                    prop_value = haskey(value, prop_name) ? value[prop_name] : value[Symbol(prop_name)]
                    val_path = isempty(path) ? string(prop_name) : "$path.$(prop_name)"
                    _validate_value(prop_schema, prop_value, typeof(prop_value), nothing, val_path, errors, verbose, root)
                elseif prop_name in required
                    push!(errors, "$path: required property '$prop_name' is missing")
                end
            end
        end

        # Validate propertyNames for Dict
        if haskey(schema, "propertyNames")
            prop_names_schema = schema["propertyNames"]
            for key in keys(value)
                key_str = string(key)
                prop_errors = String[]
                _validate_value(prop_names_schema, key_str, String, nothing, path, prop_errors, false, root)
                if !isempty(prop_errors)
                    push!(errors, "$path: property name '$key_str' is invalid")
                end
            end
        end

        # Validate patternProperties for Dict
        if haskey(schema, "patternProperties")
            pattern_props = schema["patternProperties"]
            for (pattern_str, prop_schema) in pattern_props
                pattern_regex = Regex(pattern_str)
                for (key, val) in value
                    key_str = string(key)
                    # If key matches the pattern, validate value against the schema
                    if occursin(pattern_regex, key_str)
                        val_path = isempty(path) ? key_str : "$path.$key_str"
                        _validate_value(prop_schema, val, typeof(val), nothing, val_path, errors, verbose, root)
                    end
                end
            end
        end

        # Validate dependencies for Dict
        if haskey(schema, "dependencies")
            dependencies = schema["dependencies"]
            for (prop_name, dep) in dependencies
                # If the property exists in the dict
                if haskey(value, prop_name) || haskey(value, Symbol(prop_name))
                    # Dependencies can be an array of required properties
                    if dep isa Vector
                        for required_prop in dep
                            if !haskey(value, required_prop) && !haskey(value, Symbol(required_prop))
                                push!(errors, "$path: property '$prop_name' requires property '$required_prop' to exist")
                            end
                        end
                    # Dependencies can also be a schema
                    elseif dep isa Object
                        _validate_value(dep, value, T, nothing, path, errors, verbose, root)
                    end
                end
            end
        end
    end

    # Composition validation
    _validate_composition(schema, value, T, path, errors, verbose, root)
end

# Validate composition keywords (oneOf, anyOf, allOf)
function _validate_composition(schema, value, ::Type{T}, path::String, errors::Vector{String}, verbose::Bool, root::Object{String, Any}) where {T}
    # Use the actual value's type for validation
    actual_type = typeof(value)

    # oneOf: exactly one schema must validate
    if haskey(schema, "oneOf")
        schemas = schema["oneOf"]
        valid_count = 0

        for sub_schema in schemas
            sub_errors = String[]
            _validate_value(sub_schema, value, actual_type, nothing, path, sub_errors, false, root)
            if isempty(sub_errors)
                valid_count += 1
            end
        end

        if valid_count == 0
            push!(errors, "$path: value does not match any oneOf schemas")
        elseif valid_count > 1
            push!(errors, "$path: value matches multiple oneOf schemas (expected exactly one)")
        end
    end

    # anyOf: at least one schema must validate
    if haskey(schema, "anyOf")
        schemas = schema["anyOf"]
        any_valid = false

        for sub_schema in schemas
            sub_errors = String[]
            _validate_value(sub_schema, value, actual_type, nothing, path, sub_errors, false, root)
            if isempty(sub_errors)
                any_valid = true
                break
            end
        end

        if !any_valid
            push!(errors, "$path: value does not match any anyOf schemas")
        end
    end

    # allOf: all schemas must validate
    if haskey(schema, "allOf")
        schemas = schema["allOf"]

        for sub_schema in schemas
            _validate_value(sub_schema, value, actual_type, nothing, path, errors, verbose, root)
        end
    end

    # not: schema must NOT validate
    if haskey(schema, "not")
        not_schema = schema["not"]
        sub_errors = String[]
        _validate_value(not_schema, value, actual_type, nothing, path, sub_errors, false, root)

        # If validation succeeds (no errors), it means the value DOES match the not schema, which is invalid
        if isempty(sub_errors)
            push!(errors, "$path: value must NOT match the specified schema")
        end
    end

    # Conditional validation: if/then/else
    if haskey(schema, "if")
        if_schema = schema["if"]
        sub_errors = String[]
        _validate_value(if_schema, value, actual_type, nothing, path, sub_errors, false, root)

        # If the "if" schema is valid, apply "then" schema (if present)
        if isempty(sub_errors)
            if haskey(schema, "then")
                then_schema = schema["then"]
                _validate_value(then_schema, value, actual_type, nothing, path, errors, verbose, root)
            end
        # If the "if" schema is invalid, apply "else" schema (if present)
        else
            if haskey(schema, "else")
                else_schema = schema["else"]
                _validate_value(else_schema, value, actual_type, nothing, path, errors, verbose, root)
            end
        end
    end
end

# String validation
function _validate_string(schema, tags, value::String, path::String, errors::Vector{String})
    # Check minLength
    min_len = get(schema, "minLength", nothing)
    if min_len !== nothing && length(value) < min_len
        push!(errors, "$path: string length $(length(value)) is less than minimum $min_len")
    end
    
    # Check maxLength
    max_len = get(schema, "maxLength", nothing)
    if max_len !== nothing && length(value) > max_len
        push!(errors, "$path: string length $(length(value)) exceeds maximum $max_len")
    end
    
    # Check pattern
    pattern = get(schema, "pattern", nothing)
    if pattern !== nothing
        try
            regex = Regex(pattern)
            if !occursin(regex, value)
                push!(errors, "$path: string does not match pattern $pattern")
            end
        catch e
            # Invalid regex pattern - skip validation
        end
    end
    
    # Format validation (basic checks)
    format = get(schema, "format", nothing)
    if format !== nothing
        _validate_format(format, value, path, errors)
    end
end

# Format validation
function _validate_format(format::String, value::String, path::String, errors::Vector{String})
    if format == "email"
        # RFC 5322 compatible regex (simplified but better than before)
        # Disallows spaces, requires @ and domain part
        if !occursin(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", value)
            push!(errors, "$path: invalid email format")
        end
    elseif format == "uri" || format == "url"
        # URI validation: Scheme required, no whitespace
        # Matches "http://example.com", "ftp://file", "mailto:user@host", "urn:uuid:..."
        if !occursin(r"^[a-zA-Z][a-zA-Z0-9+.-]*:[^\s]*$", value)
            push!(errors, "$path: invalid URI format")
        end
    elseif format == "uuid"
        # UUID validation
        if !occursin(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"i, value)
            push!(errors, "$path: invalid UUID format")
        end
    elseif format == "date-time"
        # ISO 8601 date-time check (requires timezone)
        # Matches: YYYY-MM-DDThh:mm:ss[.sss]Z or YYYY-MM-DDThh:mm:ss[.sss]+hh:mm
        if !occursin(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[\+\-]\d{2}:?\d{2})$", value)
            push!(errors, "$path: invalid date-time format (expected ISO 8601 with timezone)")
        end
    end
    # Other formats could be added (ipv4, ipv6, etc.)
end

# Numeric validation
function _validate_number(schema, tags, value::Number, path::String, errors::Vector{String})
    # Check minimum
    min_val = get(schema, "minimum", nothing)
    exclusive_min = get(schema, "exclusiveMinimum", false)
    if min_val !== nothing
        if exclusive_min === true && value <= min_val
            push!(errors, "$path: value $value must be greater than $min_val")
        elseif exclusive_min === false && value < min_val
            push!(errors, "$path: value $value is less than minimum $min_val")
        end
    end
    
    # Check maximum
    max_val = get(schema, "maximum", nothing)
    exclusive_max = get(schema, "exclusiveMaximum", false)
    if max_val !== nothing
        if exclusive_max === true && value >= max_val
            push!(errors, "$path: value $value must be less than $max_val")
        elseif exclusive_max === false && value > max_val
            push!(errors, "$path: value $value exceeds maximum $max_val")
        end
    end
    
    # Check multipleOf
    multiple = get(schema, "multipleOf", nothing)
    if multiple !== nothing
        # Check if value is a multiple of 'multiple'
        if !isapprox(mod(value, multiple), 0.0, atol=1e-10) && !isapprox(mod(value, multiple), multiple, atol=1e-10)
            push!(errors, "$path: value $value is not a multiple of $multiple")
        end
    end
end

# Array validation
function _validate_array(schema, tags, value::AbstractVector, path::String, errors::Vector{String}, verbose::Bool, root::Object{String, Any})
    # Check minItems
    min_items = get(schema, "minItems", nothing)
    if min_items !== nothing && length(value) < min_items
        push!(errors, "$path: array length $(length(value)) is less than minimum $min_items")
    end

    # Check maxItems
    max_items = get(schema, "maxItems", nothing)
    if max_items !== nothing && length(value) > max_items
        push!(errors, "$path: array length $(length(value)) exceeds maximum $max_items")
    end

    # Check uniqueItems
    unique_items = get(schema, "uniqueItems", false)
    if unique_items && length(value) != length(unique(value))
        push!(errors, "$path: array items must be unique")
    end

    # Check contains: at least one item must match the contains schema
    if haskey(schema, "contains")
        contains_schema = schema["contains"]
        any_match = false

        for item in value
            sub_errors = String[]
            item_type = typeof(item)
            _validate_value(contains_schema, item, item_type, nothing, path, sub_errors, false, root)
            if isempty(sub_errors)
                any_match = true
                break
            end
        end

        if !any_match
            push!(errors, "$path: array must contain at least one item matching the specified schema")
        end
    end

    # Validate each item if items schema is present
    if haskey(schema, "items")
        items_schema = schema["items"]

        # Check if items is an array (tuple validation) or a single schema
        if items_schema isa AbstractVector
            # Tuple validation: each position has its own schema
            for (i, item) in enumerate(value)
                item_path = "$path[$(i-1)]"  # 0-indexed for JSON
                item_type = typeof(item)

                # Use the corresponding schema if available
                if i <= length(items_schema)
                    _validate_value(items_schema[i], item, item_type, nothing, item_path, errors, verbose, root)
                # For items beyond the tuple schemas, check additionalItems
                else
                    if haskey(schema, "additionalItems")
                        additional_items_schema = schema["additionalItems"]
                        # If additionalItems is false, extra items are not allowed
                        if additional_items_schema === false
                            push!(errors, "$path: additional items not allowed at index $(i-1)")
                        # If additionalItems is a schema, validate against it
                        elseif additional_items_schema isa Object
                            _validate_value(additional_items_schema, item, item_type, nothing, item_path, errors, verbose, root)
                        end
                    end
                end
            end
        else
            # Single schema: applies to all items
            for (i, item) in enumerate(value)
                item_path = "$path[$(i-1)]"  # 0-indexed for JSON
                item_type = typeof(item)
                _validate_value(items_schema, item, item_type, nothing, item_path, errors, verbose, root)
            end
        end
    end
end

# Allow JSON serialization of Schema objects
StructUtils.lower(::JSONWriteStyle, s::Schema) = s.spec

# Validate JSON Schema type
function _validate_type(schema_type, value, path::String, errors::Vector{String})
    # Handle array of types (e.g., ["string", "null"])
    if schema_type isa Vector
        type_matches = false
        for t in schema_type
            if _matches_type(t, value)
                type_matches = true
                break
            end
        end
        if !type_matches
            push!(errors, "$path: value type $(typeof(value)) does not match any of $schema_type")
        end
    elseif schema_type isa String
        if !_matches_type(schema_type, value)
            push!(errors, "$path: value type $(typeof(value)) does not match expected type $schema_type")
        end
    end
end

# Check if a value matches a JSON Schema type
function _matches_type(json_type::String, value)
    if json_type == "null"
        return value === nothing || value === missing
    elseif json_type == "boolean"
        return value isa Bool
    elseif json_type == "integer"
        # Explicitly exclude Bool since Bool <: Integer in Julia
        return value isa Integer && !(value isa Bool)
    elseif json_type == "number"
        # Explicitly exclude Bool since Bool <: Number in Julia
        return value isa Number && !(value isa Bool)
    elseif json_type == "string"
        return value isa AbstractString
    elseif json_type == "array"
        return value isa AbstractVector || value isa AbstractSet || value isa Tuple
    elseif json_type == "object"
        return value isa AbstractDict || (isstructtype(typeof(value)) && isconcretetype(typeof(value)))
    end
    return false
end
