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
  * `dicttype`: a custom `AbstractDict` type to use instead of `$DEFAULT_OBJECT_TYPE` as the default type for JSON object materialization
  * `null`: a custom value to use for JSON null values (default: `nothing`)
  * `style`: a custom `StructUtils.StructStyle` subtype instance to be used in calls to `StructUtils.make` and `StructUtils.lift`. This allows overriding
    default behaviors for non-owned types.

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
  * JSON keys that don't match field names in `T` will be ignored (skipped over)
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

# defining a custom style allows us to pass a non-default dicttype `O` through JSON.parse
struct JSONReadStyle{O,T} <: JSONStyle
    null::T
end

JSONReadStyle{O}(null::T) where {O,T} = JSONReadStyle{O,T}(null)

objecttype(::StructStyle) = DEFAULT_OBJECT_TYPE
objecttype(::JSONReadStyle{OT}) where {OT} = OT
nullvalue(::StructStyle) = nothing
nullvalue(st::JSONReadStyle) = st.null

# this allows struct fields to specify tags under the json key specifically to override JSON behavior
StructUtils.fieldtagkey(::JSONStyle) = :json

function parsefile end
@doc (@doc parse) parsefile

function parsefile! end
@doc (@doc parse) parsefile!

parsefile(file; jsonlines::Union{Bool,Nothing}=nothing, kw...) = open(io -> parse(io; jsonlines=(jsonlines === nothing ? isjsonl(file) : jsonlines), kw...), file)
parsefile(file, ::Type{T}; jsonlines::Union{Bool,Nothing}=nothing, kw...) where {T} = open(io -> parse(io, T; jsonlines=(jsonlines === nothing ? isjsonl(file) : jsonlines), kw...), file)
parsefile!(file, x::T; jsonlines::Union{Bool,Nothing}=nothing, kw...) where {T} = open(io -> parse!(io, x; jsonlines=(jsonlines === nothing ? isjsonl(file) : jsonlines), kw...), file)

parse(io::Union{IO,Base.AbstractCmd}, ::Type{T}=Any; kw...) where {T} = parse(Base.read(io), T; kw...)

parse!(io::Union{IO,Base.AbstractCmd}, x::T; kw...) where {T} = parse!(Base.read(io), x; kw...)

parse(buf::Union{AbstractVector{UInt8},AbstractString}, ::Type{T}=Any;
    dicttype::Type{O}=DEFAULT_OBJECT_TYPE, null=nothing,
    style::StructStyle=JSONReadStyle{dicttype}(null), kw...) where {T,O} =
    @inline parse(lazy(buf; kw...), T; dicttype, null, style)

parse!(buf::Union{AbstractVector{UInt8},AbstractString}, x::T; dicttype::Type{O}=DEFAULT_OBJECT_TYPE, null=nothing, style::StructStyle=JSONReadStyle{dicttype}(null), kw...) where {T,O} =
    @inline parse!(lazy(buf; kw...), x; dicttype, null, style)

parse(x::LazyValue, ::Type{T}=Any; dicttype::Type{O}=DEFAULT_OBJECT_TYPE, null=nothing, style::StructStyle=JSONReadStyle{dicttype}(null)) where {T,O} =
    @inline _parse(x, T, dicttype, null, style)

function _parse(x::LazyValue, ::Type{T}, dicttype::Type{O}, null, style::StructStyle) where {T,O}
    y, pos = StructUtils.make(style, T, x)
    getisroot(x) && checkendpos(x, T, pos)
    return y
end

mutable struct ValueClosure
    value::Any
    ValueClosure() = new()
end

(f::ValueClosure)(v) = setfield!(f, :value, v)

function _parse(x::LazyValue, ::Type{Any}, ::Type{DEFAULT_OBJECT_TYPE}, null, ::StructStyle)
    out = ValueClosure()
    pos = applyvalue(out, x, null)
    getisroot(x) && checkendpos(x, Any, pos)
    return out.value
end

parse!(x::LazyValue, obj::T; dicttype::Type{O}=DEFAULT_OBJECT_TYPE, null=nothing, style::StructStyle=JSONReadStyle{dicttype}(null)) where {T,O} = StructUtils.make!(style, obj, x)

# for LazyValue, if x started at the beginning of the JSON input,
# then we want to ensure that the entire input was consumed
# and error if there are any trailing invalid JSON characters
function checkendpos(x::LazyValue, ::Type{T}, pos) where {T}
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
        str, pos = parsestring(x)
        f(convert(String, str))
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

# we overload make! for Any for LazyValues because we can dispatch to more specific
# types base on the LazyValue type
function StructUtils.make(st::StructStyle, ::Type{Any}, x::LazyValues)
    type = gettype(x)
    if type == JSONTypes.OBJECT
        return StructUtils.make(st, objecttype(st), x)
    elseif type == JSONTypes.ARRAY
        return StructUtils.make(st, Vector{Any}, x)
    elseif type == JSONTypes.STRING
        return StructUtils.lift(st, String, x)
    elseif type == JSONTypes.NUMBER
        return StructUtils.lift(st, Number, x)
    elseif type == JSONTypes.NULL
        return StructUtils.lift(st, Nothing, x)
    elseif type == JSONTypes.TRUE || type == JSONTypes.FALSE
        return StructUtils.lift(st, Bool, x)
    else
        throw(ArgumentError("cannot parse $x"))
    end
end

# catch PtrString via lift or make! so we can ensure it never "escapes" to user-level
StructUtils.liftkey(st::StructStyle, ::Type{T}, x::PtrString) where {T} =
    StructUtils.liftkey(st, T, convert(String, x))
StructUtils.lift(st::StructStyle, ::Type{T}, x::PtrString, tags) where {T} =
    StructUtils.lift(st, T, convert(String, x), tags)
StructUtils.lift(st::StructStyle, ::Type{T}, x::PtrString) where {T} =
    StructUtils.lift(st, T, convert(String, x))

function StructUtils.lift(style::StructStyle, ::Type{T}, x::LazyValues) where {T<:AbstractArray{E,0}} where {E}
    m = T(undef)
    m[1], pos = StructUtils.lift(style, E, x)
    return m, pos
end

function StructUtils.lift(style::StructStyle, ::Type{T}, x::LazyValues, tags=(;)) where {T}
    type = gettype(x)
    if type == JSONTypes.STRING
        ptrstr, pos = parsestring(x)
        str, _ = StructUtils.lift(style, T, ptrstr, tags)
        return str, pos
    elseif type == JSONTypes.NUMBER
        num, pos = parsenumber(x)
        if isint(num)
            T === Int64 && return num.int, pos
            int, _ = StructUtils.lift(style, T, num.int, tags)
            return int, pos
        elseif isfloat(num)
            T === Float64 && return num.float, pos
            float, _ = StructUtils.lift(style, T, num.float, tags)
            return float, pos
        elseif isbigint(num)
            T === BigInt && return num.bigint, pos
            bigint, _ = StructUtils.lift(style, T, num.bigint, tags)
            return bigint, pos
        else
            T === BigFloat && return num.bigfloat, pos
            bigfloat, _ = StructUtils.lift(style, T, num.bigfloat, tags)
            return bigfloat, pos
        end
    elseif type == JSONTypes.NULL
        null, _ = StructUtils.lift(style, T, nullvalue(style), tags)
        return null, getpos(x) + 4
    elseif type == JSONTypes.TRUE
        tr, _ = StructUtils.lift(style, T, true, tags)
        return tr, getpos(x) + 4
    elseif type == JSONTypes.FALSE
        fl, _ = StructUtils.lift(style, T, false, tags)
        return fl, getpos(x) + 5
    elseif Base.issingletontype(T)
        sglt, _ = StructUtils.lift(style, T, T(), tags)
        return sglt, skip(x)
    else
        out = ValueClosure()
        pos = applyvalue(out, x, nothing)
        val1 = out.value
        # big switch here for --trim verify-ability
        if val1 isa Object{String,Any}
            val, _ = StructUtils.lift(style, T, val1)
            return val, pos
        elseif val1 isa Vector{Any}
            val, _ = StructUtils.lift(style, T, val1)
            return val, pos
        elseif val1 isa String
            val, _ = StructUtils.lift(style, T, val1)
            return val, pos
        elseif val1 isa Int64
            val, _ = StructUtils.lift(style, T, val1)
            return val, pos
        elseif val1 isa Float64
            val, _ = StructUtils.lift(style, T, val1)
            return val, pos
        elseif val1 isa BigInt
            val, _ = StructUtils.lift(style, T, val1)
            return val, pos
        elseif val1 isa BigFloat
            val, _ = StructUtils.lift(style, T, val1)
            return val, pos
        elseif val1 isa Bool
            val, _ = StructUtils.lift(style, T, val1)
            return val, pos
        elseif val1 isa Nothing
            val, _ = StructUtils.lift(style, T, val1)
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
        pos = getpos(x)
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
                _, pos = @inline parsestring(LazyValue(buf, pos, JSONTypes.STRING, opts, false))
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
                _, pos = @inline parsestring(LazyValue(buf, pos, JSONTypes.STRING, opts, false))
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