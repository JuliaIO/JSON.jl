struct JSONWriteStyle <: JSONStyle end

"""
    JSON.Null()

Singleton sentinel that always serializes as the JSON literal `null`,
even when `omit_null=true` at the struct or callsite level. Useful for
per-field overrides (e.g. `Union{Nothing, JSON.Null}`) or custom field
lowering that must force a `null` emission.
"""
struct Null end

"""
    JSON.Omit()

Singleton sentinel that removes the enclosing value from the JSON output,
regardless of `omit_null` / `omit_empty` settings. Valid within objects
and arrays; using it as the root value throws an error.
"""
struct Omit end

sizeguess(::Nothing) = 4
sizeguess(x::Bool) = 5
sizeguess(x::Integer) = 20
sizeguess(x::AbstractFloat) = 20
sizeguess(x::Union{Float16, Float32, Float64}) = Base.Ryu.neededdigits(typeof(x))
sizeguess(x::AbstractString) = 2 + sizeof(x)
sizeguess(::Null) = 4
sizeguess(::Omit) = 0
sizeguess(_) = 512

StructUtils.lower(::JSONStyle, ::Missing) = nothing
StructUtils.lower(::JSONStyle, x::Symbol) = String(x)
StructUtils.lower(::JSONStyle, x::Union{Enum, AbstractChar, VersionNumber, Cstring, Cwstring, UUID, Dates.TimeType, Type, Logging.LogLevel}) = string(x)
StructUtils.lower(::JSONStyle, x::Regex) = x.pattern
StructUtils.lower(::JSONStyle, x::AbstractArray{<:Any,0}) = x[1]
StructUtils.lower(::JSONStyle, x::AbstractArray{<:Any, N}) where {N} = (view(x, ntuple(_ -> :, N - 1)..., j) for j in axes(x, N))
StructUtils.lower(::JSONStyle, x::AbstractVector) = x
StructUtils.arraylike(::JSONStyle, x::AbstractVector{<:Pair}) = false
StructUtils.structlike(::JSONStyle, ::Type{<:NamedTuple}) = true

# for pre-1.0 compat, which serialized Tuple object keys by default
StructUtils.lowerkey(::JSONStyle, x::Tuple) = string(x)

"""
    JSON.omit_null(::Type{T})::Bool
    JSON.omit_null(::JSONStyle, ::Type{T})::Bool
    
Controls whether struct fields that are undefined or are `nothing` are included in the JSON output.
Returns `false` by default, meaning all fields are included, regardless of undef or `nothing`. To instead
ensure only *non-null* fields are written, set this to `true`.
This can also be controlled via the `omit_null` keyword argument in [`JSON.json`](@ref).

```julia
# Override for a specific type
JSON.omit_null(::Type{MyStruct}) = true

# Override for a custom style
struct MyStyle <: JSON.JSONStyle end
JSON.omit_null(::MyStyle, ::Type{T}) where {T} = true
```
"""
omit_null(::Type{T}) where {T} = false
omit_null(::JSONStyle, ::Type{T}) where {T} = omit_null(T)

"""
    @omit_null struct T ...
    @omit_null T

Convenience macro to set `omit_null(::Type{T})` to `true` for the struct `T`.
Can be used in three ways:
1. In front of a struct definition: `@omit_null struct T ... end`
2. Applied to an existing struct name: `@omit_null T`
3. Chained with other macros: `@omit_null @defaults struct T ... end`

The macro automatically handles complex macro expansions by walking the expression
tree to find struct definitions, making it compatible with macros like `StructUtils.@defaults`.

# Examples
```julia
# Method 1: Struct annotation
@omit_null struct Person
    name::String
    email::Union{Nothing, String}
end

# Method 2: Apply to existing struct
struct User
    id::Int
    profile::Union{Nothing, String}
end
@omit_null User

# Method 3: Chain with @defaults
@omit_null @defaults struct Employee
    name::String = "Anonymous"
    manager::Union{Nothing, String} = nothing
end
```
"""
macro omit_null(expr)
    return _omit_macro_impl(expr, :omit_null, __module__)
end

"""
    JSON.omit_empty(::Type{T})::Bool
    JSON.omit_empty(::JSONStyle, ::Type{T})::Bool

Controls whether struct fields that are empty are included in the JSON output.
Returns `false` by default, meaning empty fields *are* included. To instead exclude empty fields,
set this to `true`. A field is considered empty if it is `nothing`, an empty collection
(empty array, dict, string, tuple, or named tuple), or `missing`.
This can also be controlled via the `omit_empty` keyword argument in [`JSON.json`](@ref).

```julia
# Override for a specific type
JSON.omit_empty(::Type{MyStruct}) = true

# Override for a custom style
struct MyStyle <: JSON.JSONStyle end
JSON.omit_empty(::MyStyle, ::Type{T}) where {T} = true
```
"""
omit_empty(::Type{T}) where {T} = false
omit_empty(::JSONStyle, ::Type{T}) where {T} = omit_empty(T)

is_empty(x) = false
is_empty(::Nothing) = true
is_empty(x::Union{AbstractDict, AbstractArray, AbstractString, Tuple, NamedTuple}) = Base.isempty(x)

"""
    @omit_empty struct T ...
    @omit_empty T

Convenience macro to set `omit_empty(::Type{T})` to `true` for the struct `T`.
Can be used in three ways:
1. In front of a struct definition: `@omit_empty struct T ... end`
2. Applied to an existing struct name: `@omit_empty T`
3. Chained with other macros: `@omit_empty @other_macro struct T ... end`
"""
macro omit_empty(expr)
    return _omit_macro_impl(expr, :omit_empty, __module__)
end

# Helper function to generate the appropriate type signature for omit functions
function _make_omit_type_sig(T, is_parametric)
    if is_parametric
        # For parametric types, use <: to match all instantiations
        return :(<:$T)
    else
        return T
    end
end

# Helper function for both @omit_null and @omit_empty macros
function _omit_macro_impl(expr, omit_func_name, module_context)
    original_expr = expr
    expr = macroexpand(module_context, expr)
    # Case 1: Just a type name (Symbol or more complex type expression)
    if isa(expr, Symbol) || (Meta.isexpr(expr, :curly) || Meta.isexpr(expr, :where))
        # Extract the base type name
        T, is_parametric = _extract_type_name(expr)
        type_sig = _make_omit_type_sig(T, is_parametric)
        return esc(quote
            JSON.$omit_func_name(::Type{$type_sig}) = true
        end)
    end
    # Case 2: Struct definition (possibly from macro expansion)
    if Meta.isexpr(expr, :struct)
        ismutable, T, fieldsblock = expr.args
        T, is_parametric = _extract_type_name(T)
        type_sig = _make_omit_type_sig(T, is_parametric)
        return esc(quote
            # insert original expr as-is
            $expr
            # omit function overload
            JSON.$omit_func_name(::Type{$type_sig}) = true
        end)
    end
    # Case 3: Block expression (from complex macros like @defaults)
    if Meta.isexpr(expr, :block)
        # Try to find a struct definition in the block
        struct_expr = _find_struct_in_block(expr)
        if struct_expr !== nothing
            ismutable, T, fieldsblock = struct_expr.args
            T, is_parametric = _extract_type_name(T)
            type_sig = _make_omit_type_sig(T, is_parametric)
            return esc(quote
                # insert original expr as-is
                $original_expr
                # omit function overload
                JSON.$omit_func_name(::Type{$type_sig}) = true
            end)
        end
    end
    # Case 4: Macro expression that we hope expands to a struct
    if Meta.isexpr(original_expr, :macrocall)
        # Try to see if the expanded form is a struct
        if Meta.isexpr(expr, :struct)
            ismutable, T, fieldsblock = expr.args
            T, is_parametric = _extract_type_name(T)
            type_sig = _make_omit_type_sig(T, is_parametric)
            return esc(quote
                # insert original expr as-is
                $original_expr
                # omit function overload
                JSON.$omit_func_name(::Type{$type_sig}) = true
            end)
        else
            throw(ArgumentError("Macro $(original_expr.args[1]) did not expand to a struct definition"))
        end
    end
    throw(ArgumentError("Invalid usage of @$omit_func_name macro. Expected: struct definition, type name, or macro that expands to struct definition"))
end

# Helper function to recursively find a struct definition in a block expression
function _find_struct_in_block(expr)
    if Meta.isexpr(expr, :struct)
        return expr
    elseif Meta.isexpr(expr, :block)
        for arg in expr.args
            result = _find_struct_in_block(arg)
            if result !== nothing
                return result
            end
        end
    end
    return nothing
end

# Helper function to extract the base type name from various type expressions
# Returns (base_type, is_parametric) tuple
function _extract_type_name(T)
    if isa(T, Symbol)
        return (T, false)
    elseif Meta.isexpr(T, :<:)
        # Handle subtyping: struct Foo <: Bar
        return _extract_type_name(T.args[1])
    elseif Meta.isexpr(T, :curly)
        # Handle parametric types: return just the base type name (e.g., Foo from Foo{T})
        # and indicate it's parametric
        return (T.args[1], true)
    elseif Meta.isexpr(T, :where)
        # Handle where clauses: struct Foo{T} where T
        return _extract_type_name(T.args[1])
    else
        return (T, false)
    end
end

StructUtils.lowerkey(::JSONStyle, s::AbstractString) = s
StructUtils.lowerkey(::JSONStyle, sym::Symbol) = String(sym)
StructUtils.lowerkey(::JSONStyle, n::Union{Integer, Union{Float16, Float32, Float64}}) = string(n)
StructUtils.lowerkey(::JSONStyle, x) = throw(ArgumentError("No key representation for $(typeof(x)). Define StructUtils.lowerkey(::JSON.JSONStyle, ::$(typeof(x)))"))

"""
    JSON.json(x) -> String
    JSON.json(io, x)
    JSON.json(file_name, x)

Serialize `x` to JSON format. The 1st method takes just the object and returns a `String`.
In the 2nd method, `io` is an `IO` object, and the JSON output will be written to it.
For the 3rd method, `file_name` is a `String`, a file will be opened and the JSON output will be written to it.

All methods accept the following keyword arguments:

- `omit_null::Union{Bool, Nothing}=nothing`: Controls whether struct fields that are undefined or are `nothing` are included in the JSON output.
  If `true`, only non-null fields are written. If `false`, all fields are included regardless of being undefined or `nothing`.
  If `nothing`, the behavior is determined by `JSON.omit_null(::Type{T})`, which is `false` by default.

- `omit_empty::Union{Bool, Nothing}=nothing`: Controls whether struct fields that are empty are included in the JSON output.
  If `true`, empty fields are excluded. If `false`, empty fields are included.
  If `nothing`, the behavior is determined by `JSON.omit_empty(::Type{T})`.

- `JSON.Null()` / `JSON.Omit()` sentinels: `JSON.Null()` always emits a JSON `null`
  literal even when `omit_null=true`, enabling per-field overrides (for example by
  declaring a field as `Union{Nothing, JSON.Null}`) or defining a custom `lower` function for a field that returns `JSON.Null`.
  `JSON.Omit()` removes the enclosing value from the output regardless of global omit settings, making it easy for field-level
  lowering code to drop optional data entirely. For example, by defining a custom `lower` function for a field that returns `JSON.Omit`.
    
- `allownan::Bool=false`: If `true`, allow `Inf`, `-Inf`, and `NaN` in the output.
  If `false`, throw an error if `Inf`, `-Inf`, or `NaN` is encountered.

- `jsonlines::Bool=false`: If `true`, input must be array-like and the output will be written in the JSON Lines format,
  where each element of the array is written on a separate line (i.e. separated by a single newline character `\n`).
  If `false`, the output will be written in the standard JSON format.

- `pretty::Union{Integer,Bool}=false`: Controls pretty printing of the JSON output.
  If `true`, the output will be pretty-printed with 2 spaces of indentation.
  If an integer, it will be used as the number of spaces of indentation.
  If `false` or `0`, the output will be compact.
  Note: Pretty printing is not supported when `jsonlines=true`.

- `inline_limit::Int=0`: For arrays shorter than this limit, pretty printing will be disabled (indentation set to 0).

- `ninf::String="-Infinity"`: Custom string representation for negative infinity.

- `inf::String="Infinity"`: Custom string representation for positive infinity.

- `nan::String="NaN"`: Custom string representation for NaN.

- `float_style::Symbol=:shortest`: Controls how floating-point numbers are formatted.
  Options are:
  - `:shortest`: Use the shortest representation that preserves the value
  - `:fixed`: Use fixed-point notation
  - `:exp`: Use exponential notation

- `float_precision::Int=1`: Number of decimal places to use when `float_style` is `:fixed` or `:exp`.

- `bufsize::Int=2^22`: Buffer size in bytes for IO operations. When writing to IO, the buffer will be flushed 
  to the IO stream once it reaches this size. This helps control memory usage during large write operations.
  Default is 4MB (2^22 bytes). This parameter is ignored when returning a String.

- `style::JSONStyle=JSONWriteStyle()`: Custom style object that controls serialization behavior. This allows customizing
    certain aspects of serialization, like defining a custom `lower` method for a non-owned type. Like `struct MyStyle <: JSONStyle end`,
    `JSON.lower(x::Rational) = (num=x.num, den=x.den)`, then calling `JSON.json(1//3; style=MyStyle())` will output
    `{"num": 1, "den": 3}`.

By default, `x` must be a JSON-serializable object. Supported types include:
  * `AbstractString` => JSON string: types must support the `AbstractString` interface, specifically with support for
    `ncodeunits` and `codeunit(x, i)`.
  * `Bool` => JSON boolean: must be `true` or `false`
  * `Nothing` => JSON null: must be the `nothing` singleton value
  * `Number` => JSON number: `Integer` subtypes or `Union{Float16, Float32, Float64}` have default implementations
    for other `Number` types, [`JSON.tostring`](@ref) is first called to convert
    the value to a `String` before being written directly to JSON output
  * `AbstractArray`/`Tuple`/`AbstractSet` => JSON array: objects for which `JSON.arraylike` returns `true`
     are output as JSON arrays. `arraylike` is defined by default for
    `AbstractArray`, `AbstractSet`, `Tuple`, and `Base.Generator`. For other types that define,
    they must also properly implement `StructUtils.applyeach` to iterate over the index => elements pairs.
    Note that arrays with dimensionality > 1 are written as nested arrays, with `N` nestings for `N` dimensions,
    and the 1st dimension is always the innermost nested JSON array (column-major order).
  * `AbstractDict`/`NamedTuple`/structs => JSON object: if a value doesn't fall into any of the above categories,
    it is output as a JSON object. `StructUtils.applyeach` is called, which has appropriate implementations
    for `AbstractDict`, `NamedTuple`, and structs, where field names => values are iterated over. Field names can
    be output with an alternative name via field tag overload, like `field::Type &(json=(name="alternative_name",),)`

If an object is not JSON-serializable, an override for `JSON.lower` can
be defined to convert it to a JSON-serializable object. Some default `lower` defintions
are defined in JSON itself, for example:
  * `StructUtils.lower(::Missing) = nothing`
  * `StructUtils.lower(x::Symbol) = String(x)`
  * `StructUtils.lower(x::Union{Enum, AbstractChar, VersionNumber, Cstring, Cwstring, UUID, Dates.TimeType}) = string(x)`
  * `StructUtils.lower(x::Regex) = x.pattern`

These allow common Base/stdlib types to be serialized in an expected format.

Circular references are tracked automatically and cycles are broken by writing `null` for any children references.

For pre-formatted JSON data as a String, use `JSONText(json)` to write the string out as-is.

For `AbstractDict` objects with non-string keys, `StructUtils.lowerkey` will be called before serializing. This allows aggregate
or other types of dict keys to be converted to an appropriate string representation. See `StructUtils.liftkey`
for the reverse operation, which is called when parsing JSON data back into a dict type.

*NOTE*: `JSON.json` should _not_ be overloaded directly by custom
types as this isn't robust for various output options (IO, String, etc.)
nor recursive situations. Types should define an appropriate
`JSON.lower` definition instead.

*NOTE*: `JSON.json(str, indent::Integer)` is special-cased for backwards compatibility with pre-1.0 JSON.jl,
as this typically would mean "write out the `indent` integer to file `str`". As writing out a single integer to
a file is extremely rare, it was decided to keep the pre-1.0 behavior for compatibility reasons.

Examples:
```julia
using Dates

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
    monster::AbstractMonster = Dracula(10) &(json=(lower=x -> x isa Dracula ? (monster_type="vampire", num_victims=x.num_victims) : (monster_type="werewolf", witching_hour=x.witching_hour),),)
    percent::Percent = Percent(0.5)
    birthdate::Date = Date(2025, 1, 1) &(json=(dateformat="yyyy/mm/dd",),)
    percentages::Dict{Percent, Int} = Dict{Percent, Int}(Percent(0.0) => 0, Percent(1.0) => 1)
    json_properties::JSONText = JSONText("{\"key\": \"value\"}")
    matrix::Matrix{Float64} = [1.0 2.0; 3.0 4.0]
    extra_field::Any = nothing &(json=(ignore=true,),)
end

franken = FrankenStruct()
franken.id = 1

json = JSON.json(franken; omit_null=false)
# "{\"id\":1,\"name\":null,\"address\":null,\"rate\":null,\"franken_type\":\"a\",\"notsure\":{\"key\":\"value\"},\"monster\":{\"monster_type\":\"vampire\",\"num_victims\":10},\"percent\":0.5,\"birthdate\":\"2025/01/01\",\"percentages\":{\"1.0\":1,\"0.0\":0},\"json_properties\":{\"key\": \"value\"},\"matrix\":[[1.0,3.0],[2.0,4.0]]}"
```

A few comments on the JSON produced in the example above:
  - The `name` field was `#undef`, and thus was serialized as `null`.
  - The `address` and `rate` fields were `nothing` and `missing`, respectively, and thus were serialized as `null`.
  - The `type` field has a `name` field tag, so the JSON key for this field is `franken_type` instead of `type`.
  - The `notsure` field is a `JSON.Object`, so it is serialized as a JSON object.
  - The `monster` field is a `AbstractMonster`, which is a custom type. It has a `lower` field tag that specifies how the value of this field specifically (not all AbstractMonster) should be serialized
  - The `percent` field is a `Percent`, which is a custom type. It has a `lower` method that specifies how `Percent` values should be serialized
  - The `birthdate` field has a `dateformat` field tag, so the value follows the format (`yyyy/mm/dd`) instead of the default date ISO format (`yyyy-mm-dd`)
  - The `percentages` field is a `Dict{Percent, Int}`, which is a custom type. It has a `lowerkey` method that specifies how `Percent` keys should be serialized as strings
  - The `json_properties` field is a `JSONText`, so the JSONText value is serialized as-is
  - The `matrix` field is a `Matrix{Float64}`, which is a custom type. It is serialized as a JSON array, with the first dimension being the innermost nested JSON array (column-major order)
  - The `extra_field` field has a `ignore` field tag, so it is skipped when serializing

"""
function json end

@kwdef struct WriteOptions{S}
    omit_null::Union{Bool, Nothing} = nothing
    omit_empty::Union{Bool, Nothing} = nothing
    allownan::Bool = false
    jsonlines::Bool = false
    pretty::Int = 0
    ninf::String = "-Infinity"
    inf::String = "Infinity"
    nan::String = "NaN"
    inline_limit::Int = 0
    float_style::Symbol = :shortest # :shortest, :fixed, :exp
    float_precision::Int = 1
    bufsize::Int = 2^22 # 4MB default buffer size for IO flushing
    style::S = JSONWriteStyle()
end

@noinline float_style_throw(fs) = throw(ArgumentError("Invalid float style: $fs"))
float_style_check(fs) = fs == :shortest || fs == :fixed || fs == :exp || float_style_throw(fs)

@noinline float_precision_throw(fs, fp) = throw(ArgumentError("float_precision must be positive when float_style is $fs; got $fp"))
float_precision_check(fs, fp) = (fs == :shortest || fp > 0) || float_precision_throw(fs, fp)

# if jsonlines and pretty is not 0 or false, throw an ArgumentError
@noinline _jsonlines_pretty_throw() = throw(ArgumentError("pretty printing is not supported when writing jsonlines"))
_jsonlines_pretty_check(jsonlines, pretty) = jsonlines && pretty !== false && !iszero(pretty) && _jsonlines_pretty_throw()
@noinline _root_omit_throw() = throw(ArgumentError("JSON.Omit() is only valid inside arrays or objects"))

# throw an error if opts is not a valid WriteOptions
function _write_options_check(opts::WriteOptions)
    _jsonlines_pretty_check(opts.jsonlines, opts.pretty)
    float_style_check(opts.float_style)
    float_precision_check(opts.float_style, opts.float_precision)
    nothing
end

function json(io::IO, x::T; pretty::Union{Integer,Bool}=false, kw...) where {T}
    opts = WriteOptions(; pretty=pretty === true ? 2 : Int(pretty), kw...)
    _write_options_check(opts)
    y = StructUtils.lower(opts.style, x)
    # Use smaller initial buffer size, limited by bufsize
    initial_size = min(sizeguess(y), opts.bufsize)
    buf = Vector{UInt8}(undef, initial_size)
    pos = json!(buf, 1, y, opts, Any[y], io)
    # Write any remaining buffer contents to IO
    if pos > 1
        write(io, view(buf, 1:pos-1))
    end
    return nothing
end

if isdefined(Base, :StringVector)
    stringvec(n) = Base.StringVector(n)
else
    stringvec(n) = Vector{UInt8}(undef, n)
end

function json(x; pretty::Union{Integer,Bool}=false, kw...)
    opts = WriteOptions(; pretty=pretty === true ? 2 : Int(pretty), kw...)
    _write_options_check(opts)
    y = StructUtils.lower(opts.style, x)
    buf = stringvec(sizeguess(y))
    pos = json!(buf, 1, y, opts, Any[y], nothing)
    return String(resize!(buf, pos - 1))
end

function json(fname, obj; kw...)
    if obj isa Integer
        # special-case for pre-1.0 JSON compat
        return json(fname; pretty=obj)
    else
        @assert fname isa AbstractString "filename must be a string"
    end
    open(fname, "w") do io
        json(io, obj; kw...)
    end
    return fname
end

# we use the same growth strategy as Base julia does for array growing
# which starts with small N at ~5x and approaches 1.125x as N grows
# ref: https://github.com/JuliaLang/julia/pull/40453
newlen(n₀) = ceil(Int, n₀ + 4*n₀^(7 / 8) + n₀ / 8)

macro checkn(n, force_resize=false)
    esc(quote
        if (pos + $n - 1) > length(buf)
            # If we have an IO object and buffer would exceed bufsize, flush to IO first
            # unless force_resize is true (used for comma writing to avoid flushing partial JSON)
            if io !== nothing && length(buf) >= bufsize && pos > 1 && !$force_resize
                write(io, view(buf, 1:pos-1))
                pos = 1
            end
            # Resize buffer if still needed
            if (pos + $n - 1) > length(buf)
                resize!(buf, newlen(pos + $n))
            end
        end
    end)
end

struct WriteClosure{JS, arraylike, T, I} # T is the type of the parent object/array being written
    buf::Vector{UInt8}
    pos::Ptr{Int}
    wroteany::Ptr{Bool} # to track if we wrote any data to the buffer
    indent::Int
    depth::Int
    opts::JS
    ancestor_stack::Vector{Any} # to track circular references
    io::I
    bufsize::Int
end

function indent(buf, pos, ind, depth, io, bufsize)
    if ind > 0
        n = ind * depth + 1
        @checkn n
        buf[pos] = UInt8('\n')
        for i = 1:(n - 1)
            buf[pos + i] = UInt8(' ')
        end
        pos += n
    end
    return pos
end

checkkey(s) = s isa AbstractString || throw(ArgumentError("Value returned from `StructUtils.lowerkey` must be a string: $(typeof(s))"))

function (f::WriteClosure{JS, arraylike, T, I})(key, val) where {JS, arraylike, T, I}
    track_ref = ismutabletype(typeof(val))
    is_circ_ref = track_ref && any(x -> x === val, f.ancestor_stack)
    val isa Omit && return
    if !arraylike
        # for objects, check omit_null/omit_empty
        # and skip if the value is null or empty
        if f.opts.omit_null === true || (f.opts.omit_null === nothing && omit_null(f.opts.style, T))
            (is_circ_ref || val === nothing) && return
        end
        if f.opts.omit_empty === true || (f.opts.omit_empty === nothing && omit_empty(f.opts.style, T))
            (is_circ_ref || is_empty(val)) && return
        end
    end
    pos = unsafe_load(f.pos)
    unsafe_store!(f.wroteany, true) # at this point, we know something will be written
    buf = f.buf
    ind = f.indent
    io = f.io
    bufsize = f.bufsize
    pos = indent(buf, pos, ind, f.depth, io, bufsize)
    # if not an array, we need to write the key + ':'
    if !arraylike
        # skey = StructUtils.lowerkey(f.opts, key)
        # check if the key is a string
        checkkey(key)
        pos = _string(buf, pos, key, io, bufsize)
        @checkn 1
        buf[pos] = UInt8(':')
        pos += 1
        if ind > 0
            @checkn 1
            buf[pos] = UInt8(' ')
            pos += 1
        end
    end
    # check if the lowered value is in our ancestor stack
    if is_circ_ref
        # if so, it's a circular reference! so we just write `null`
        pos = _null(buf, pos, io, bufsize)
    else
        track_ref && push!(f.ancestor_stack, val)
        # if jsonlines, we need to recursively set to false
        if f.opts.jsonlines
            opts = WriteOptions(; omit_null=f.opts.omit_null, omit_empty=f.opts.omit_empty, allownan=f.opts.allownan, jsonlines=false, pretty=f.opts.pretty, ninf=f.opts.ninf, inf=f.opts.inf, nan=f.opts.nan, inline_limit=f.opts.inline_limit, float_style=f.opts.float_style, float_precision=f.opts.float_precision)
        else
            opts = f.opts
        end
        pos = json!(buf, pos, val, opts, f.ancestor_stack, io, ind, f.depth, bufsize)
        track_ref && pop!(f.ancestor_stack)
    end
    @checkn 1 true
    @inbounds buf[pos] = f.opts.jsonlines ? UInt8('\n') : UInt8(',')
    pos += 1
    # store our updated pos
    unsafe_store!(f.pos, pos)
    return
end

@noinline throwjsonlines() = throw(ArgumentError("jsonlines only supported for arraylike"))

# assume x is lowered value
function json!(buf, pos, x, opts::WriteOptions, ancestor_stack::Union{Nothing, Vector{Any}}=nothing, io::Union{Nothing, IO}=nothing, ind::Int=opts.pretty, depth::Int=0, bufsize::Int=opts.bufsize)
    # string
    if x isa Omit
        _root_omit_throw()
    elseif x isa Null
        return _null(buf, pos, io, bufsize)
    elseif x isa AbstractString
        return _string(buf, pos, x, io, bufsize)
    # write JSONText out directly
    elseif x isa JSONText
        val = x.value
        @checkn sizeof(val)
        for i = 1:sizeof(val)
            @inbounds buf[pos + i - 1] = codeunit(val, i)
        end
        return pos + sizeof(val)
    # bool; check before Number since Bool <: Number
    elseif x isa Bool
        if x
            @checkn 4
            @inbounds buf[pos] = 't'
            @inbounds buf[pos + 1] = 'r'
            @inbounds buf[pos + 2] = 'u'
            @inbounds buf[pos + 3] = 'e'
            return pos + 4
        else
            @checkn 5
            @inbounds buf[pos] = 'f'
            @inbounds buf[pos + 1] = 'a'
            @inbounds buf[pos + 2] = 'l'
            @inbounds buf[pos + 3] = 's'
            @inbounds buf[pos + 4] = 'e'
            return pos + 5
        end
    # number
    elseif x isa Number
        return _number(buf, pos, x, opts, io, bufsize)
    # null
    elseif x === nothing
        return _null(buf, pos, io, bufsize)
    # object or array
    elseif StructUtils.dictlike(opts.style, x) || StructUtils.arraylike(opts.style, x) || StructUtils.structlike(opts.style, x)
        al = StructUtils.arraylike(opts.style, x)
        # override pretty indent to 0 for arrays shorter than inline_limit
        if al && opts.pretty > 0 && opts.inline_limit > 0 && length(x) < opts.inline_limit
            local_ind = 0
        else
            local_ind = ind
        end
        if !opts.jsonlines
            @checkn 1
            @inbounds buf[pos] = al ? UInt8('[') : UInt8('{')
            pos += 1
        else
            al || throwjsonlines()
        end
        ref = Ref(pos)
        wroteany = false
        wroteanyref = Ref(false)
        GC.@preserve ref wroteanyref begin
            c = WriteClosure{typeof(opts), al, typeof(x), typeof(io)}(buf, Base.unsafe_convert(Ptr{Int}, ref), Base.unsafe_convert(Ptr{Bool}, wroteanyref), local_ind, depth + 1, opts, ancestor_stack, io, bufsize)
            StructUtils.applyeach(opts.style, c, x)
            # get updated pos
            pos = unsafe_load(c.pos)
            wroteany = unsafe_load(c.wroteany)
        end
        # in WriteClosure, we eagerly write a comma after each element
        # so for non-empty object/arrays, we can just overwrite the last comma with the closechar
        if wroteany
            pos -= 1
            pos = indent(buf, pos, local_ind, depth, io, bufsize)
        end
        # even if the input is empty and we're jsonlines, the spec says it's ok to end w/ a newline
        @checkn 1
        @inbounds buf[pos] = opts.jsonlines ? UInt8('\n') : al ? UInt8(']') : UInt8('}')
        return pos + 1
    else
        return _string(buf, pos, x, io, bufsize)
    end
end

function _null(buf, pos, io, bufsize)
    @checkn 4
    @inbounds buf[pos] = 'n'
    @inbounds buf[pos + 1] = 'u'
    @inbounds buf[pos + 2] = 'l'
    @inbounds buf[pos + 3] = 'l'
    return pos + 4
end

_string(buf, pos, x, io, bufsize) = _string(buf, pos, string(x), io, bufsize)
_string(buf, pos, x::LazyValues, io, bufsize) = _string(buf, pos, getindex(x), io, bufsize)
_string(buf, pos, x::PtrString, io, bufsize) = _string(buf, pos, convert(String, x), io, bufsize)

function _string(buf, pos, x::AbstractString, io, bufsize)
    sz = ncodeunits(x)
    el = escapelength(x)
    @checkn (el + 2)
    @inbounds buf[pos] = UInt8('"')
    pos += 1
    if el > sz
        for i = 1:sz
            @inbounds escbytes = ESCAPECHARS[codeunit(x, i) + 1]
            for j = 1:length(escbytes)
                @inbounds buf[pos] = escbytes[j]
                pos += 1
            end
        end
    else
        @simd for i = 1:sz
            @inbounds buf[pos] = codeunit(x, i)
            pos += 1
        end
    end
    @inbounds buf[pos] = UInt8('"')
    return pos + 1
end

"""
    JSON.tostring(x)

Overloadable function that allows non-`Integer` `Number` types
to convert themselves to a `String` that is then used
when serializing `x` to JSON. Note that if the result of `tostring`
is not a valid JSON number, it will be serialized as a JSON string,
with double quotes around it.

An example overload would look something like:
```julia
JSON.tostring(x::MyDecimal) = string(x)
```
"""
tostring(x) = string(Float64(x))

split_sign(n::Integer) = unsigned(abs(n)), n < 0
split_sign(n::Unsigned) = n, false
split_sign(x::BigInt) = (abs(x), x < 0)

@noinline infcheck(x, allownan) = isfinite(x) || allownan || throw(ArgumentError("$x not allowed to be written in JSON spec; pass `allownan=true` to allow anyway"))

function _number(buf, pos, x::Number, opts::WriteOptions, io, bufsize)
    if x isa Integer
        y, neg = split_sign(x)
        n = i = ndigits(y, base=10, pad=1)
        @checkn (i + neg)
        if neg
            @inbounds buf[pos] = UInt8('-')
            pos += 1
        end
        while i > 0
            @inbounds buf[pos + i - 1] = 48 + rem(y, 10)
            y = oftype(y, div(y, 10))
            i -= 1
        end
        return pos + n
    elseif x isa Union{Float16, Float32, Float64}
        infcheck(x, opts.allownan)
        if isnan(x)
            nan = opts.nan
            @checkn sizeof(nan)
            for i = 1:sizeof(nan)
                @inbounds buf[pos + i - 1] = UInt8(codeunit(nan, i))
            end
            return pos + sizeof(nan)
        elseif isinf(x)
            if x < 0
                inf = opts.ninf
            else
                inf = opts.inf
            end
            @checkn sizeof(inf)
            for i = 1:sizeof(inf)
                @inbounds buf[pos + i - 1] = UInt8(codeunit(inf, i))
            end
            return pos + sizeof(inf)
        end
        if opts.float_style == :shortest
            @checkn Base.Ryu.neededdigits(typeof(x))
            return Base.Ryu.writeshortest(buf, pos, x)
        elseif opts.float_style == :fixed
            @checkn (opts.float_precision + Base.Ryu.neededdigits(typeof(x)))
            return Base.Ryu.writefixed(buf, pos, x, opts.float_precision, false, false, true)
        elseif opts.float_style == :exp
            @checkn (opts.float_precision + Base.Ryu.neededdigits(typeof(x)))
            return Base.Ryu.writeexp(buf, pos, x, opts.float_precision, false, false, true)
        else
            # unreachable as we validate float_style inputs
            @assert false
        end
    else
        str = tostring(x)
        if anyinvalidnumberchars(str)
            # serialize as string
            return _string(buf, pos, str, io, bufsize)
        end
        bytes = codeunits(str)
        sz = sizeof(bytes)
        @checkn sz
        for i = 1:sz
            @inbounds buf[pos + i - 1] = bytes[i]
        end
        return pos + sz
    end
end

function anyinvalidnumberchars(x)
    for i = 1:sizeof(x)
        b = codeunit(x, i)
        if !(b == UInt8('-') || b == UInt8('.') || b == UInt8('e') || b == UInt8('E') ||
            UInt8('0') <= b <= UInt8('9'))
            return true
        end
    end
    return false
end
