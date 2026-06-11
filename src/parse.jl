"""
    JSON.parse(json)
    JSON.parse(json, T)
    JSON.parse!(json, x)
    JSON.parsefile(filename)
    JSON.parsefile(filename, T)
    JSON.parsefile!(filename, x)

Parse a JSON input (string, vector, stream, LazyValue, etc.) into a Julia value. The `parsefile` variants
take a filename, open the file, and pass the `IOStream` to `parse`.

Currently supported keyword arguments include:
  * `allownan`: allows parsing `NaN`, `Inf`, and `-Inf` since they are otherwise invalid JSON
  * `ninf`: string to use for `-Inf` (default: `"-Infinity"`)
  * `inf`: string to use for `Inf` (default: `"Infinity"`)
  * `nan`: string to use for `NaN` (default: `"NaN"`)
  * `jsonlines`: treat the `json` input as an implicit JSON array, delimited by newlines, each element being parsed from each row/line in the input
  * `isroot`: whether this is the root LazyValue encompassing the entire json buffer. If `false` parses only the first JSON value and ignores trailing characters. (default: `true`)
  * `dicttype`: a custom `AbstractDict` type to use instead of `$DEFAULT_OBJECT_TYPE` as the default type for JSON object materialization
  * `null`: a custom value to use for JSON null values (default: `nothing`)
  * `unknown_fields`: controls how unmatched JSON object keys or positional values are handled when parsing into a target type or existing object; supported values are `:ignore` (default) and `:error`
  * `style`: a custom style instance (ideally subtyping `JSON.JSONStyle`, like `struct MyStyle <: JSON.JSONStyle end`) that is passed as-is to all
    StructUtils.jl interface methods (`StructUtils.make`, `StructUtils.lift`, trait queries like `StructUtils.dictlike`, etc.). This allows overriding
    default behaviors for non-owned types. Subtyping `JSON.JSONStyle` (rather than `StructUtils.StructStyle` directly) ensures JSON-specific defaults,
    like the `json` fieldtag namespace and numeric dict-key lifting, still apply when parsing with the custom style.

The methods without a type specified (`JSON.parse(json)`, `JSON.parsefile(filename)`), do a generic materialization into
predefined default types, including:
  * JSON object => `$DEFAULT_OBJECT_TYPE` (**see note below**)
  * JSON array => `Vector{Any}`
  * JSON string => `String`
  * JSON number => `Int64`, `BigInt`, `Float64`, or `BigFloat`
  * JSON true => `true`
  * JSON false => `false`
  * JSON null => `nothing`

When a type `T` is specified (`JSON.parse(json, T)`, `JSON.parsefile(filename, T)`), materialization to a value
of type `T` will be attempted utilizing machinery and interfaces provided by the StructUtils.jl package, including:
  * For JSON objects, JSON keys will be matched against field names of `T` with a value being constructed via `T(args...)`
  * If `T` was defined with the `@noarg` macro, an empty instance will be constructed, and field values set as JSON keys match field names
  * If `T` had default field values defined using the `@defaults` or `@kwarg` macros (from StructUtils.jl package), those will be set in the value of `T` unless different values are parsed from the JSON
  * If `T` was defined with the `@nonstruct` macro, the struct will be treated as a primitive type and constructed using the `lift` function rather than from field values
  * JSON keys that don't match field names in `T` will be ignored (skipped over) by default; pass `unknown_fields=:error` to reject them
  * If a field in `T` has a `name` fieldtag, the `name` value will be used to match JSON keys instead
  * If `T` or any recursive field type of `T` is abstract, an appropriate `JSON.@choosetype T x -> ...` definition should exist for "choosing" a concrete type at runtime; default type choosing exists for `Union{T, Missing}` and `Union{T, Nothing}` where the JSON value is checked if `null`. If the `Any` type is encountered, the default materialization types will be used (`JSON.Object`, `Vector{Any}`, etc.)
  * For any non-JSON-standard non-aggregate (i.e. non-object, non-array) field type of `T`, a `JSON.lift(::Type{T}, x) = ...` definition can be defined for how to "lift" the default JSON value (String, Number, Bool, `nothing`) to the type `T`; a default lift definition exists, for example, for `JSON.lift(::Type{Missing}, x) = missing` where the standard JSON value for `null` is `nothing` and it can be "lifted" to `missing`
  * For any `T` or recursive field type of `T` that is `AbstractDict`, non-string/symbol/integer keys will need to have a `StructUtils.liftkey(::Type{T}, x))` definition for how to "lift" the JSON string key to the key type of `T`

For any `T` or recursive field type of `T` that is `JSON.JSONText`, the next full raw JSON value will be preserved in the `JSONText` wrapper as-is.

For the unique case of nested JSON arrays and prior knowledge of the expected dimensionality,
a target type `T` can be given as an `AbstractArray{T, N}` subtype. In this case, the JSON array data is materialized as an
n-dimensional array, where: the number of JSON array nestings must match the Julia array dimensionality (`N`),
nested JSON arrays at matching depths are assumed to have equal lengths, and the length of
the innermost JSON array is the 1st dimension length and so on. For example, the JSON array `[[[1.0,2.0]]]`
would be materialized as a 3-dimensional array of `Float64` with sizes `(2, 1, 1)`, when called
like `JSON.parse("[[[1.0,2.0]]]", Array{Float64, 3})`. Note that n-dimensional Julia
arrays are written to json as nested JSON arrays by default, to enable lossless re-parsing,
though the dimensionality must still be provided explicitly to the call to `parse` (i.e. default parsing via `JSON.parse(json)`
will result in plain nested `Vector{Any}`s returned).

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

JSON.@choosetype AbstractMonster x -> x.monster_type[] == "vampire" ? Dracula : Werewolf

struct Percent <: Number
    value::Float64
end

JSON.lift(::Type{Percent}, x) = Percent(Float64(x))
StructUtils.liftkey(::Type{Percent}, x::String) = Percent(parse(Float64, x))

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

json = \"\"\"
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
\"\"\"
JSON.parse(json, FrankenStruct)
# FrankenStruct(1, "Jim", "123 Main St", missing, :b, JSON.Object{String, Any}("key" => "value"), Dracula(10), Percent(0.1), Date("2023-10-01"), Dict{Percent, Int64}(Percent(0.2) => 2, Percent(0.1) => 1), JSONText("{\"key\": \"value\"}"), [1.0 3.0; 2.0 4.0])
```

Let's walk through some notable features of the example above:
  * The `name` field isn't present in the JSON input, so the default value of `"Jim"` is used.
  * The `address` field uses a default `@choosetype` to determine that the JSON value is not `null`, so a `String` should be parsed for the field value.
  * The `rate` field has a `null` JSON value, so the default `@choosetype` recognizes it should be "lifted" to `Missing`, which then uses a predefined `lift` definition for `Missing`.
  * The `type` field is a `Symbol`, and has a fieldtag `json=(name="franken_type",)` which means the JSON key `franken_type` will be used to set the field value instead of the default `type` field name. A default `lift` definition for `Symbol` is used to convert the JSON string value to a `Symbol`.
  * The `notsure` field is of type `Any`, so the default object type `JSON.Object{String, Any}` is used to materialize the JSON value.
  * The `monster` field is a polymorphic type, and the JSON value has a `monster_type` key that determines which concrete type to use. The `@choosetype` macro is used to define the logic for choosing the concrete type based on the JSON input. Note that teh `x` in `@choosetype` is a `LazyValue`, so we materialize via `x.monster_type[]` in order to compare with the string `"vampire"`.
  * The `percent` field is a custom type `Percent` and the `JSON.lift` defines how to construct a `Percent` from the JSON value, which is a `Float64` in this case.
  * The `birthdate` field uses a custom date format for parsing, specified in the JSON input.
  * The `percentages` field is a dictionary with keys of type `Percent`, which is a custom type. The `liftkey` function is defined to convert the JSON string keys to `Percent` types (parses the Float64 manually)
  * The `json_properties` field has a type of `JSONText`, which means the raw JSON will be preserved as a String of the `JSONText` type.
  * The `matrix` field is a `Matrix{Float64}`, so the JSON input array-of-arrays are materialized as such.
  * The `extra_key` field is not defined in the `FrankenStruct` type, so it is ignored and skipped over.

NOTE:
Why use `JSON.Object{String, Any}` as the default object type? It provides several benefits:
  * Behaves as a drop-in replacement for `Dict{String, Any}`, so no loss of functionality
  * Performance! It's internal representation means memory savings and faster construction for small objects typical in JSON (vs `Dict`)
  * Insertion order is preserved, so the order of keys in the JSON input is preserved in `JSON.Object`
  * Convenient `getproperty` (i.e. `obj.key`) syntax is supported, even for `Object{String,Any}` key types (again ideal/specialized for JSON usage)

`JSON.Object` internal representation uses a linked list, thus key lookups are linear time (O(n)). For *large* JSON objects,
(hundreds or thousands of keys), consider using a `Dict{String, Any}` instead, like `JSON.parse(json; dicttype=Dict{String, Any})`.
"""
function parse end

import StructUtils: StructStyle

abstract type JSONStyle <: StructStyle end

# Default style used by JSON.parse when no custom style is provided. It carries
# no state: all per-call parse configuration (dicttype, null, unknown_fields)
# travels with the LazyValue source options (see LazyOptions), never in the
# style. The style passed to JSON.parse — user-provided or this default — is
# handed to all StructUtils interface methods as-is, so user method overloads
# of any breadth (::StructStyle, ::JSON.JSONStyle, ::MyStyle) dispatch
# naturally, without wrapper-forwarding ambiguities (see issue #464).
struct JSONReadStyle <: JSONStyle end

StructUtils.initialize(::StructStyle, ::Type{Object}, source) = DEFAULT_OBJECT_TYPE()

# this allows struct fields to specify tags under the json key specifically to override JSON behavior
StructUtils.fieldtagkey(::JSONStyle) = :json

@noinline _unknown_fields_arg_error(uf) =
    throw(ArgumentError("`unknown_fields` must be `:ignore` or `:error`, got `$(repr(uf))`"))
@noinline _unknown_fields_any_error() =
    throw(ArgumentError("`unknown_fields` is only supported when parsing into a target type or existing object"))

function _ignore_unknown(::Type{T}, unknown_fields::Symbol) where {T}
    ignore = unknown_fields === :ignore ? true :
             unknown_fields === :error ? false : _unknown_fields_arg_error(unknown_fields)
    T === Any && !ignore && _unknown_fields_any_error()
    return ignore
end

# rebuild a LazyValue with the parse-level configuration stored in its options;
# sub-values created during traversal inherit these options automatically
function withopts(x::LazyValue, ::Type{O}, null, ignore_unknown::Bool) where {O}
    opts = getopts(x)
    newopts = LazyOptions(; allownan=opts.allownan, ninf=opts.ninf, inf=opts.inf, nan=opts.nan,
        jsonlines=opts.jsonlines, null=null, dicttype=O, ignore_unknown=ignore_unknown)
    return LazyValue(getbuf(x), getpos(x), gettype(x), newopts, getisroot(x))
end

@noinline unknownfielderror(::Type{T}, key) where {T} =
    ArgumentError("encountered unknown JSON member $(repr(key)) while parsing `$T`")

function StructUtils.unknownfield(st::StructStyle, ::Type{T}, key, value::LazyValues) where {T}
    getopts(value).ignore_unknown ||
        throw(unknownfielderror(T, key isa PtrString ? convert(String, key) : key))
    return StructUtils.defaultstate(st)
end

"See [`parse`](@ref)."
function parsefile end

"See [`parse`](@ref)."
function parsefile! end

parsefile(file; jsonlines::Union{Bool,Nothing}=nothing, kw...) = open(io -> parse(io; jsonlines=(jsonlines === nothing ? isjsonl(file) : jsonlines), kw...), file)
parsefile(file, ::Type{T}; jsonlines::Union{Bool,Nothing}=nothing, kw...) where {T} = open(io -> parse(io, T; jsonlines=(jsonlines === nothing ? isjsonl(file) : jsonlines), kw...), file)
parsefile!(file, x::T; jsonlines::Union{Bool,Nothing}=nothing, kw...) where {T} = open(io -> parse!(io, x; jsonlines=(jsonlines === nothing ? isjsonl(file) : jsonlines), kw...), file)

parse(io::Union{IO,Base.AbstractCmd}, ::Type{T}=Any; kw...) where {T} = parse(Base.read(io), T; kw...)

parse!(io::Union{IO,Base.AbstractCmd}, x::T; kw...) where {T} = parse!(Base.read(io), x; kw...)

parse(buf::Union{AbstractVector{UInt8},AbstractString}, ::Type{T}=Any;
    dicttype::Type{O}=DEFAULT_OBJECT_TYPE, null=nothing, style::StructStyle=JSONReadStyle(),
    unknown_fields::Symbol=:ignore, kw...) where {T,O} =
    @inline parse(lazy(buf; kw...), T; dicttype, null, style, unknown_fields)

parse!(buf::Union{AbstractVector{UInt8},AbstractString}, x::T;
    dicttype::Type{O}=DEFAULT_OBJECT_TYPE, null=nothing, style::StructStyle=JSONReadStyle(),
    unknown_fields::Symbol=:ignore, kw...) where {T,O} =
    @inline parse!(lazy(buf; kw...), x; dicttype, null, style, unknown_fields)

parse(x::LazyValue, ::Type{T}=Any;
    dicttype::Type{O}=DEFAULT_OBJECT_TYPE, null=nothing, style::StructStyle=JSONReadStyle(),
    unknown_fields::Symbol=:ignore) where {T,O} =
    @inline _parse(withopts(x, O, null, _ignore_unknown(T, unknown_fields)), T, style)

function _parse(x::LazyValue, ::Type{T}, style::StructStyle) where {T}
    y, pos = StructUtils.make(style, T, x)
    getisroot(x) && checkendpos(x, T, pos)
    return y
end

mutable struct ValueClosure
    value::Any
    ValueClosure() = new()
end

(f::ValueClosure)(v) = setfield!(f, :value, v)

function _parse(x::LazyValue, ::Type{Any}, style::StructStyle)
    opts = getopts(x)
    # fast path for default materialization; custom styles go through
    # StructUtils.make so user lift/trait overloads apply under `Any` targets
    if opts.dicttype === DEFAULT_OBJECT_TYPE &&
            (style isa JSONReadStyle || style isa StructUtils.DefaultStyle)
        out = ValueClosure()
        pos = applyvalue(out, x, opts.null)
        getisroot(x) && checkendpos(x, Any, pos)
        return out.value
    end
    y, pos = StructUtils.make(style, Any, x)
    getisroot(x) && checkendpos(x, Any, pos)
    return y
end

parse!(x::LazyValue, obj::T;
    dicttype::Type{O}=DEFAULT_OBJECT_TYPE, null=nothing, style::StructStyle=JSONReadStyle(),
    unknown_fields::Symbol=:ignore) where {T,O} =
    StructUtils.make!(style, obj, withopts(x, O, null, _ignore_unknown(T, unknown_fields)))

# for LazyValue, if x started at the beginning of the JSON input,
# then we want to ensure that the entire input was consumed
# and error if there are any trailing invalid JSON characters
function checkendpos(x::LazyValue, ::Type{T}, pos::Int) where {T}
    buf = getbuf(x)
    len = getlength(buf)
    if pos <= len
        b = getbyte(buf, pos)
        while b == UInt8('\t') || b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r')
            pos += 1
            pos > len && break
            b = getbyte(buf, pos)
        end
    end
    if (pos - 1) != len
        invalid(InvalidChar, buf, pos, T)
    end
    return nothing
end

# specialized closure to optimize Object{String, Any} insertions
# to avoid doing a linear scan on each insertion, we use a Set
# to track keys seen so far. In the common case of non-duplicated key,
# we can insert the new key-val pair directly after the latest leaf node
mutable struct ObjectClosure{T}
    root::Object{String,Any}
    obj::Object{String,Any}
    keys::Set{String}
    null::T
end

ObjectClosure(obj, null) = ObjectClosure(obj, obj, sizehint!(Set{String}(), 16), null)

@inline function insert_or_overwrite!(oc::ObjectClosure, key, val)
    # in! does both a hash lookup and also sets the key if not present
    if _in!(key, oc.keys)
        # slow path for dups; does a linear scan from our root object
        setindex!(oc.root, val, key)
        return
    end
    # this uses an "unsafe" constructor that returns the new leaf node
    # and sets the child of the previous node to the new node
    oc.obj = Object{String,Any}(oc.obj, key, val) # fast append path
end

(oc::ObjectClosure)(k, v) = applyvalue(val -> insert_or_overwrite!(oc, convert(String, k), val), v, oc.null)

# generic apply `f` to LazyValue, using default types to materialize, depending on type
function applyvalue(f, x::LazyValues, null)
    type = gettype(x)
    if type == JSONTypes.OBJECT
        obj = Object{String,Any}()
        pos = applyobject(ObjectClosure(obj, null), x)
        f(obj)
        return pos
    elseif type == JSONTypes.ARRAY
        # basically free to allocate 16 instead of Julia-default 8 and avoids
        # a reallocation in many cases
        arr = Vector{Any}(undef, 16)
        resize!(arr, 0)
        pos = applyarray(x) do _, v
            applyvalue(val -> push!(arr, val), v, null)
        end
        f(arr)
        return pos
    elseif type == JSONTypes.STRING
        buf = getbuf(x)
        GC.@preserve buf begin
            str, pos = parsestring(x)
            f(convert(String, str))
        end
        return pos
    elseif type == JSONTypes.NUMBER
        num, pos = parsenumber(x)
        if isint(num)
            f(num.int)
        elseif isfloat(num)
            f(num.float)
        elseif isbigint(num)
            f(num.bigint)
        else
            f(num.bigfloat)
        end
        return pos
    elseif type == JSONTypes.NULL
        f(null)
        return getpos(x) + 4
    elseif type == JSONTypes.TRUE
        f(true)
        return getpos(x) + 4
    elseif type == JSONTypes.FALSE
        f(false)
        return getpos(x) + 5
    else
        throw(ArgumentError("cannot parse json"))
    end
end

# we overload make for Any for LazyValues because we can dispatch to more specific
# types based on the LazyValue type
function StructUtils.make(st::StructStyle, ::Type{Any}, x::LazyValues)
    type = gettype(x)
    if type == JSONTypes.OBJECT
        dt = getopts(x).dicttype
        if dt === DEFAULT_OBJECT_TYPE
            return StructUtils.make(st, DEFAULT_OBJECT_TYPE, x)
        else
            return StructUtils.make(st, dt, x)
        end
    elseif type == JSONTypes.ARRAY
        return StructUtils.make(st, Vector{Any}, x)
    elseif type == JSONTypes.STRING
        return StructUtils.extract(st, String, x, (;))
    elseif type == JSONTypes.NUMBER
        return StructUtils.extract(st, Number, x, (;))
    elseif type == JSONTypes.NULL
        return StructUtils.extract(st, Nothing, x, (;))
    elseif type == JSONTypes.TRUE || type == JSONTypes.FALSE
        return StructUtils.extract(st, Bool, x, (;))
    else
        throw(ArgumentError("cannot parse $x"))
    end
end

# liftkey for numeric dict key types to enable round-tripping Dict{Int,V}, Dict{Float64,V}, etc.
# these correspond to the lowerkey definitions in write.jl that convert numeric keys to strings
StructUtils.liftkey(::JSONStyle, ::Type{T}, x::AbstractString) where {T<:Integer} = Base.parse(T, x)
StructUtils.liftkey(::JSONStyle, ::Type{T}, x::AbstractString) where {T<:AbstractFloat} = Base.parse(T, x)

# Legacy (1.x) support for user lift methods that take the raw LazyValue for
# JSON objects/arrays, e.g. `JSON.lift(::MyStyle, ::Type{Date}, x::JSON.LazyValue)`.
# These sentinel fallbacks let the extract driver below detect whether such a
# method exists; if not, the aggregate is materialized (JSON.Object/Vector{Any})
# before the user-level lift is called. Prefer lifting from the materialized
# value, or overload `StructUtils.extract(::MyStyle, ::Type{T}, x::JSON.LazyValues, tags)`
# for fully-lazy custom handling.
struct _NoCustomLazyLift end
const _NO_CUSTOM_LAZY_LIFT = _NoCustomLazyLift()

StructUtils.lift(::JSONStyle, ::Type{T}, ::LazyValues, tags) where {T} = _NO_CUSTOM_LAZY_LIFT
StructUtils.lift(::JSONStyle, ::Type{T}, ::LazyValues) where {T} = _NO_CUSTOM_LAZY_LIFT
# disambiguate vs StructUtils' 0-dimensional array lift; 0-dim targets are handled by the
# extract method below after the sentinel reports no custom lazy lift exists
StructUtils.lift(::JSONStyle, ::Type{T}, ::LazyValues) where {T<:AbstractArray{E,0}} where {E} = _NO_CUSTOM_LAZY_LIFT

function customlazylift(style::JSONStyle, ::Type{T}, x::LazyValues, tags) where {T}
    ret = StructUtils.lift(style, T, x, tags)
    ret === _NO_CUSTOM_LAZY_LIFT || return StructUtils._normalizelift(ret, skip(x))
    ret = StructUtils.lift(style, T, x)
    ret === _NO_CUSTOM_LAZY_LIFT || return StructUtils._normalizelift(ret, skip(x))
    return nothing
end
customlazylift(::StructStyle, ::Type{T}, x::LazyValues, tags) where {T} = nothing

function StructUtils.extract(style::StructStyle, ::Type{T}, x::LazyValues, tags) where {T<:AbstractArray{E,0}} where {E}
    m = T(undef)
    m[1], pos = StructUtils.extract(style, E, x, (;))
    return m, pos
end

# The driver connecting StructUtils.make's leaf conversion to lazy JSON values:
# parses the scalar at the current position, calls user-level lift hooks with
# the *materialized* value and the *user's own* style, and threads the byte
# position back through make as the state. PtrString never escapes this
# function; aggregates reaching here (i.e. targets that aren't dictlike/
# arraylike/structlike) are materialized to default types before lifting.
function StructUtils.extract(style::StructStyle, ::Type{T}, x::LazyValues, tags) where {T}
    type = gettype(x)
    buf = getbuf(x)
    if type == JSONTypes.OBJECT || type == JSONTypes.ARRAY
        custom = customlazylift(style, T, x, tags)
        custom === nothing || return custom
    end
    if type == JSONTypes.STRING
        GC.@preserve buf begin
            ptrstr, pos = parsestring(x)
            str, _ = StructUtils.extract(style, T, convert(String, ptrstr), tags)
        end
        return str, pos
    elseif type == JSONTypes.NUMBER
        num, pos = parsenumber(x)
        if isint(num)
            T === Int64 && return num.int, pos
            int, _ = StructUtils.extract(style, T, num.int, tags)
            return int, pos
        elseif isfloat(num)
            T === Float64 && return num.float, pos
            float, _ = StructUtils.extract(style, T, num.float, tags)
            return float, pos
        elseif isbigint(num)
            T === BigInt && return num.bigint, pos
            bigint, _ = StructUtils.extract(style, T, num.bigint, tags)
            return bigint, pos
        else
            T === BigFloat && return num.bigfloat, pos
            bigfloat, _ = StructUtils.extract(style, T, num.bigfloat, tags)
            return bigfloat, pos
        end
    elseif type == JSONTypes.NULL
        # union-split on the configured null value (an Any-typed option field)
        # so the common nothing/missing cases dispatch statically
        nv = getopts(x).null
        if nv === nothing
            null, _ = StructUtils.extract(style, T, nothing, tags)
        elseif nv === missing
            null, _ = StructUtils.extract(style, T, missing, tags)
        else
            # cold path: `nv` is dynamically typed, so assert the lifted result
            # to keep it from widening this function's return type (and boxing
            # every other branch's value with it)
            null = (StructUtils.extract(style, T, nv, tags)[1])::T
        end
        return null, getpos(x) + 4
    elseif type == JSONTypes.TRUE
        tr, _ = StructUtils.extract(style, T, true, tags)
        return tr, getpos(x) + 4
    elseif type == JSONTypes.FALSE
        fl, _ = StructUtils.extract(style, T, false, tags)
        return fl, getpos(x) + 5
    elseif Base.issingletontype(T)
        sglt, _ = StructUtils.extract(style, T, T(), tags)
        return sglt, skip(x)
    else
        out = ValueClosure()
        pos = applyvalue(out, x, getopts(x).null)
        val1 = out.value
        # big switch here for --trim verify-ability
        if val1 isa Object{String,Any}
            val, _ = StructUtils.extract(style, T, val1, tags)
            return val, pos
        elseif val1 isa Vector{Any}
            val, _ = StructUtils.extract(style, T, val1, tags)
            return val, pos
        elseif val1 isa String
            val, _ = StructUtils.extract(style, T, val1, (;))
            return val, pos
        elseif val1 isa Int64
            val, _ = StructUtils.extract(style, T, val1, (;))
            return val, pos
        elseif val1 isa Float64
            val, _ = StructUtils.extract(style, T, val1, (;))
            return val, pos
        elseif val1 isa BigInt
            val, _ = StructUtils.extract(style, T, val1, (;))
            return val, pos
        elseif val1 isa BigFloat
            val, _ = StructUtils.extract(style, T, val1, (;))
            return val, pos
        elseif val1 isa Bool
            val, _ = StructUtils.extract(style, T, val1, (;))
            return val, pos
        elseif val1 isa Nothing
            val, _ = StructUtils.extract(style, T, val1, (;))
            return val, pos
        else
            throw(ArgumentError("cannot parse json"))
        end
    end
end

function StructUtils.make(::StructStyle, ::Type{JSONText}, x::LazyValues)
    buf = getbuf(x)
    pos = getpos(x)
    endpos = skip(x)
    val = GC.@preserve buf JSONText(unsafe_string(pointer(buf, pos), endpos - pos))
    return val, endpos
end

@generated function StructUtils.maketuple(st::StructStyle, ::Type{T}, x::LazyValues) where {T<:Tuple}
    N = fieldcount(T)
    ex = quote
        pos::Int = getpos(x)
        buf = getbuf(x)
        len = getlength(buf)
        opts = getopts(x)
        b = getbyte(buf, pos)
        typ = gettype(x)
        if typ == JSONTypes.OBJECT && b != UInt8('{')
            error = ExpectedOpeningObjectChar
            @goto invalid
        elseif typ == JSONTypes.ARRAY && b != UInt8('[')
            error = ExpectedOpeningArrayChar
            @goto invalid
        elseif typ != JSONTypes.OBJECT && typ != JSONTypes.ARRAY
            error = InvalidJSON
            @goto invalid
        end
        pos += 1
        @nextbyte
        Base.@nexprs $N i -> begin
            if typ == JSONTypes.OBJECT
                # consume key
                GC.@preserve buf begin
                    _, pos = @inline parsestring(LazyValue(buf, pos, JSONTypes.STRING, opts, false))
                end
                @nextbyte
                if b != UInt8(':')
                    error = ExpectedColon
                    @goto invalid
                end
                pos += 1
                @nextbyte
            end
            x = _lazy(buf, pos, len, b, opts)
            j_{i}, pos = StructUtils.make(st, fieldtype(T, i), x)
            @nextbyte
            if typ == JSONTypes.OBJECT && b == UInt8('}')
                if Base.@nany($N, k->!@isdefined(j_{k}))
                    error = InvalidJSON
                    @goto invalid
                end
                return Base.@ntuple($N, j), pos + 1
            elseif typ == JSONTypes.ARRAY && b == UInt8(']')
                if Base.@nany($N, k->!@isdefined(j_{k}))
                    error = InvalidJSON
                    @goto invalid
                end
                return Base.@ntuple($N, j), pos + 1
            elseif b != UInt8(',')
                error = ExpectedComma
                @goto invalid
            end
            pos += 1
            @nextbyte
        end
        # skip extra fields not used by tuple
        while true
            if typ == JSONTypes.OBJECT
                # consume key
                GC.@preserve buf begin
                    _, pos = @inline parsestring(LazyValue(buf, pos, JSONTypes.STRING, opts, false))
                end
                @nextbyte
                if b != UInt8(':')
                    error = ExpectedColon
                    @goto invalid
                end
                pos += 1
                @nextbyte
            end
            pos = skip(_lazy(buf, pos, len, b, opts))
            @nextbyte
            if typ == JSONTypes.OBJECT && b == UInt8('}')
                return Base.@ntuple($N, j), pos + 1
            elseif typ == JSONTypes.ARRAY && b == UInt8(']')
                return Base.@ntuple($N, j), pos + 1
            elseif b != UInt8(',')
                error = ExpectedComma
                @goto invalid
            end
            pos += 1
            @nextbyte
        end
        @label invalid
        invalid(error, buf, pos, "tuple")
    end
    return ex
end
