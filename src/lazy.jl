"""
    JSON.lazy(json; kw...)
    JSON.lazyfile(file; kw...)

Detect the initial JSON value in `json`, returning a `JSON.LazyValue` instance. `json` input can be:
  * `AbstractString`
  * `AbstractVector{UInt8}`
  * `IO`, `IOStream`, `Cmd` (bytes are fully read into a `Vector{UInt8}` for parsing, i.e. `read(json)` is called)

`lazyfile` is a convenience method that takes a filename and opens the file before calling `lazy`.

The `JSON.LazyValue` supports the "selection" syntax
for lazily navigating the JSON value. For example (`x = JSON.lazy(json)`):
  * `x.key`, `x[:key]` or `x["key"]` for JSON objects
  * `x[1]`, `x[2:3]`, `x[end]` for JSON arrays
  * `propertynames(x)` to see all keys in the JSON object
  * `x.a.b.c` for selecting deeply nested values
  * `x[~, (k, v) -> k == "foo"]` for recursively searching for key "foo" and return matching values

NOTE: Selecting values from a `LazyValue` will always return a `LazyValue`.
Selecting a specific key of an object or index of an array will only parse
what is necessary before returning. This leads to a few conclusions about
how to effectively utilize `LazyValue`:
  * `JSON.lazy` is great for one-time access of a value in JSON
  * It's also great for finding a required deeply nested value
  * It's not great for any case where repeated access to values is required;
    this results in the same JSON being parsed on each access (i.e. naively iterating a lazy JSON array will be O(n^2))
  * Best practice is to use `JSON.lazy` sparingly unless there's a specific case where it will benefit;
    or use `JSON.lazy` as a means to access a value that is then fully materialized

Another option for processing `JSON.LazyValue` is calling `foreach(f, x)` which is defined on
`JSON.LazyValue` for JSON objects and arrays. For objects, `f` should be of the form
`f(kv::Pair{String, LazyValue})` where `kv` is a key-value pair, and for arrays,
`f(v::LazyValue)` where `v` is the value at the index. This allows for iterating over all key-value pairs in an object
or all values in an array without materializing the entire structure.

Lazy values can be materialized via `JSON.parse` in a few different forms:
  * `JSON.parse(json)`: Default materialization into `JSON.Object` (a Dict-like type), `Vector{Any}`, etc.
  * `JSON.parse(json, T)`: Materialize into a user-provided type `T` (following rules/programmatic construction from StructUtils.jl)
  * `JSON.parse!(json, x)`: Materialize into an existing object `x` (following rules/programmatic construction from StructUtils.jl)

Thus for completeness sake, here's an example of ideal usage of `JSON.lazy`:

```julia
x = JSON.lazy(very_large_json_object)
# find a deeply nested value
y = x.a.b.c.d.e.f.g
# materialize the value
z = JSON.parse(y)
# now mutate/repeatedly access values in z
```

In this example, we only parsed as much of the `very_large_json_object` as was required to find the value `y`.
Then we fully materialized `y` into `z`, which is now a normal Julia object. We can now mutate or access values in `z`.

Currently supported keyword arguments include:
  - `allownan::Bool = false`: whether "special" float values shoudl be allowed while parsing (`NaN`, `Inf`, `-Inf`); these values are specifically _not allowed_ in the JSON spec, but many JSON libraries allow reading/writing. When `true`, untyped numbers are parsed as `Float64`. A requested fixed-width integer type of up to 128 bits is parsed exactly from the number token
  - `ninf::String = "-Infinity"`: the string that will be used to parse `-Inf` if `allownan=true`
  - `inf::String = "Infinity"`: the string that will be used to parse `Inf` if `allownan=true`
  - `nan::String = "NaN"`: the string that will be sued to parse `NaN` if `allownan=true`
  - `jsonlines::Bool = false`: whether the JSON input should be treated as an implicit array, with newlines separating individual JSON elements with no leading `'['` or trailing `']'` characters. Common in logging or streaming workflows. Defaults to `true` when used with `JSON.parsefile` and the filename extension is `.jsonl` or `ndjson`. Note this ensures that parsing will _always_ return an array at the root-level.
  - `duplicate_keys::Symbol = :overwrite`: how repeated object keys are handled. `:overwrite` preserves the default last-value-wins behavior. `:error` throws [`JSON.DuplicateKeyError`](@ref).
  - `isroot::Bool = true`: whether this is the root LazyValue encompassing the entire json buffer. If `false` parses only the first JSON value and ignores trailing characters.

Note that validation is only fully done on `null`, `true`, and `false`,
while other values are only lazily inferred from the first non-whitespace character:
  * `'{'`: JSON object
  * `'['`: JSON array
  * `'"'`: JSON string
  * `'0'`-`'9'` or `'-'`: JSON number

Further validation for these values is done later when materialized, like `JSON.parse`,
or via selection syntax calls on a `LazyValue`.
"""
function lazy end

# helper struct we pack lazy-parsing keyword args into
# held by LazyValues for access
@kwdef struct LazyOptions
    allownan::Bool = false
    ninf::String = "-Infinity"
    inf::String = "Infinity"
    nan::String = "NaN"
    jsonlines::Bool = false
    duplicate_keys::Symbol = :overwrite
end

lazy(io::Union{IO, Base.AbstractCmd}; kw...) = lazy(Base.read(io); kw...)

lazyfile(file; jsonlines::Union{Bool, Nothing}=nothing, kw...) = open(io -> lazy(io; jsonlines=(jsonlines === nothing ? isjsonl(file) : jsonlines), kw...), file)

"See [`lazy`](@ref)."
lazyfile

function lazy(buf::Union{AbstractVector{UInt8}, AbstractString}; isroot::Bool=true, kw...)
    opts = LazyOptions(; kw...)
    opts.duplicate_keys in (:overwrite, :error) || throw(ArgumentError("`duplicate_keys` must be `:overwrite` or `:error`, got `$(repr(opts.duplicate_keys))`"))
    if !applicable(pointer, buf, 1) || (buf isa AbstractVector{UInt8} && !isone(only(strides(buf))))
        if buf isa AbstractString
            buf = String(buf)
        else
            buf = Vector{UInt8}(buf)
        end
    end
    len = getlength(buf)
    if len == 0
        error = UnexpectedEOF
        pos = 0
        @goto invalid
    end
    pos = 1
    # detect and error on UTF-16LE BOM
    if len >= 2 && getbyte(buf, pos) == 0xff && getbyte(buf, pos + 1) == 0xfe
        error = InvalidUTF16
        @goto invalid
    end
    # detect and error on UTF-16BE BOM
    if len >= 2 && getbyte(buf, pos) == 0xfe && getbyte(buf, pos + 1) == 0xff
        error = InvalidUTF16
        @goto invalid
    end
    # detect and ignore UTF-8 BOM
    pos = (len >= 3 && getbyte(buf, pos) == 0xef && getbyte(buf, pos + 1) == 0xbb && getbyte(buf, pos + 2) == 0xbf) ? pos + 3 : pos
    @nextbyte
    return _lazy(buf, pos, len, b, opts, isroot)

@label invalid
    invalid(error, buf, pos, Any)
end

"""
    JSON.LazyValue

A lazy representation of a JSON value. The `LazyValue` type
supports the "selection" syntax for lazily navigating the JSON value.
Lazy values can be materialized via `JSON.parse(x)`, `JSON.parse(x, T)`, or `JSON.parse!(x, y)`.
"""
struct LazyValue{T}
    buf::T # wrapped json source, AbstractVector{UInt8} or AbstractString
    pos::Int # byte position in buf where this value starts
    type::JSONTypes.T # scoped enum for type of value: OBJECT, ARRAY, etc.
    opts::LazyOptions
    isroot::Bool # true if this is the root LazyValue
end

# convenience types only used for defining `show` on LazyValue
# this allows, for example, a LazyValue w/ type OBJECT to be
# displayed like a Dict using Base AbstractDict machinery
# while a LazyValue w/ type ARRAY is displayed like an Array
struct LazyObject{T} <: AbstractDict{String, LazyValue}
    buf::T
    pos::Int
    opts::LazyOptions
    isroot::Bool
    LazyObject(x::LazyValue{T}) where {T} = new{T}(getbuf(x), getpos(x), getopts(x), getisroot(x))
end

struct LazyArray{T} <: AbstractVector{LazyValue}
    buf::T
    pos::Int
    opts::LazyOptions
    isroot::Bool
    LazyArray(x::LazyValue{T}) where {T} = new{T}(getbuf(x), getpos(x), getopts(x), getisroot(x))
end

# helper accessors so we can overload getproperty for convenience
getbuf(x) = getfield(x, :buf)
getpos(x) = getfield(x, :pos)
gettype(x) = getfield(x, :type)
getopts(x) = getfield(x, :opts)
getisroot(x) = getfield(x, :isroot)

const LazyValues{T} = Union{LazyValue{T}, LazyObject{T}, LazyArray{T}}

# default materialization that calls parse
Base.getindex(x::LazyValues) = parse(x)

# some overloads/usage of StructUtils + LazyValues
# this defines all the right getproperty, getindex methods
Selectors.@selectors LazyValues

Base.lastindex(x::LazyValues) = length(x)

# this ensures LazyValues can be "sources" in StructUtils.make
function StructUtils.applyeach(::StructUtils.StructStyle, f, x::LazyValues)
    type = gettype(x)
    if type == JSONTypes.OBJECT
        return applyobject(f, x)
    elseif type == JSONTypes.ARRAY
        return applyarray(f, x)
    end
    typename = get(JSONTypes.names, type, "UNKNOWN")
    throw(ArgumentError(string(
        "applyeach not applicable for `",
        _typename(typeof(x)),
        "` with JSON type = `JSONTypes.",
        typename,
        '`',
    )))
end

@inline function Base.foreach(f, x::LazyValues)
    type = gettype(x)
    if type == JSONTypes.OBJECT
        applyobject((k, v) -> f(convert(String, k) => v), x)
    elseif type == JSONTypes.ARRAY
        applyarray((i, v) -> f(v), x)
    else
        throw(ArgumentError("foreach not applicable for `$(typeof(x))` with JSON type = `$type`"))
    end
    return
end

StructUtils.structlike(::StructUtils.StructStyle, x::LazyValues) = gettype(x) == JSONTypes.OBJECT
StructUtils.arraylike(::StructUtils.StructStyle, x::LazyValues) = gettype(x) == JSONTypes.ARRAY
StructUtils.nulllike(::StructUtils.StructStyle, x::LazyValues) = gettype(x) == JSONTypes.NULL

# core method that detects what JSON value is at the current position
# and immediately returns an appropriate LazyValue instance
function _lazy(buf, pos::Int, len, b, opts, isroot=false)
    if opts.jsonlines
        return LazyValue(buf, pos, JSONTypes.ARRAY, opts, isroot)
    elseif b == UInt8('{')
        return LazyValue(buf, pos, JSONTypes.OBJECT, opts, isroot)
    elseif b == UInt8('[')
        return LazyValue(buf, pos, JSONTypes.ARRAY, opts, isroot)
    elseif b == UInt8('"')
        return LazyValue(buf, pos, JSONTypes.STRING, opts, isroot)
    elseif b == UInt8('n') && pos + 3 <= len &&
        getbyte(buf, pos + 1) == UInt8('u') &&
        getbyte(buf, pos + 2) == UInt8('l') &&
        getbyte(buf, pos + 3) == UInt8('l')
        return LazyValue(buf, pos, JSONTypes.NULL, opts, isroot)
    elseif b == UInt8('t') && pos + 3 <= len &&
        getbyte(buf, pos + 1) == UInt8('r') &&
        getbyte(buf, pos + 2) == UInt8('u') &&
        getbyte(buf, pos + 3) == UInt8('e')
        return LazyValue(buf, pos, JSONTypes.TRUE, opts, isroot)
    elseif b == UInt8('f') && pos + 4 <= len &&
        getbyte(buf, pos + 1) == UInt8('a') &&
        getbyte(buf, pos + 2) == UInt8('l') &&
        getbyte(buf, pos + 3) == UInt8('s') &&
        getbyte(buf, pos + 4) == UInt8('e')
        return LazyValue(buf, pos, JSONTypes.FALSE, opts, isroot)
    elseif b == UInt8('-') || (UInt8('0') <= b <= UInt8('9')) || (opts.allownan && (b == UInt8('+') || firstbyteeq(opts.nan, b) || firstbyteeq(opts.ninf, b) || firstbyteeq(opts.inf, b)))
        return LazyValue(buf, pos, JSONTypes.NUMBER, opts, isroot)
    else
        error = InvalidJSON
        @goto invalid
    end
@label invalid
    if !opts.allownan
        # quick check if the value here is inf/nan/+1 and we can provide
        # a more helpful error message about how to parse
        if b in (UInt8('N'), UInt8('n'), UInt8('I'), UInt8('i'), UInt8('+'))
            throw(ArgumentError("JSON parsing error: possible `NaN`, `Inf`, or `-Inf` which are not valid JSON values. Use the `allownan=true` option and `ninf`, `inf`, and/or `nan` keyword arguments to parse."))
        end
    end
    invalid(error, buf, pos, Any)
end

# core JSON object parsing function
# takes a `keyvalfunc` that is applied to each key/value pair
# `keyvalfunc` receives a PtrString => LazyValue pair
# `keyvalfunc` can return `StructUtils.EarlyReturn` to short-circuit parsing
# otherwise, it should return a `pos::Int` value that notes the next position to continue parsing
# to materialize the key, call `convert(String, key)`
# PtrString can be compared to String via `==` or `isequal` to help avoid allocating the full String in some cases
# returns a `pos` value that notes the next position where parsing should continue
# this is essentially the `StructUtils.applyeach` implementation for LazyValues w/ type OBJECT
function applyobject(keyvalfunc, x::LazyValues)
    pos::Int = getpos(x)
    buf = getbuf(x)
    len = getlength(buf)
    opts = getopts(x)
    seen = opts.duplicate_keys === :error ? Set{String}() : nothing
    b = getbyte(buf, pos)
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @nextbyte
    b == UInt8('}') && return pos + 1
    while true
        # parsestring returns key as a PtrString
        keypos = pos
        GC.@preserve buf begin
            key, pos = @inline parsestring(LazyValue(buf, pos, JSONTypes.STRING, opts, false))
            if seen !== nothing
                decoded = convert(String, key)
                decoded in seen && throw(DuplicateKeyError(decoded, keypos))
                push!(seen, decoded)
            end
            @nextbyte
            if b != UInt8(':')
                error = ExpectedColon
                @goto invalid
            end
            pos += 1
            @nextbyte
            # we're now positioned at the start of the value
            val = _lazy(buf, pos, len, b, opts)
            ret = keyvalfunc(key, val)
        end
        # if ret is an EarlyReturn, then we're short-circuiting
        # parsing via e.g. selection syntax, so return immediately
        ret isa StructUtils.EarlyReturn && return ret
        # if keyvalfunc didn't materialize `val` and return an
        # updated `pos`, then we need to skip val ourselves
        # WARNING: parsing can get corrupted if random Int values are returned from keyvalfunc
        pos = (ret isa Int && ret > pos) ? ret : skip(val)
        @nextbyte
        # check for terminating conditions
        if b == UInt8('}')
            return pos + 1
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        pos += 1 # move past ','
        @nextbyte
    end
@label invalid
    invalid(error, buf, pos, "object")
end

# jsonlines is unique because it's an *implicit* array
# so newlines are valid delimiters (not ignored whitespace)
# and EOFs are valid terminators (not errors)
# these checks are injected after we've processed the "line"
# so we need to check for EOFs and newlines
macro jsonlines_checks()
    esc(quote
        # if we're at EOF, then we're done
        pos > len && return pos
        # now we want to ignore whitespace, but *not* newlines
        b = getbyte(buf, pos)
        while b == UInt8(' ') || b == UInt8('\t')
            pos += 1
            pos > len && return pos
            b = getbyte(buf, pos)
        end
        # any combo of '\r', '\n', or '\r\n' is a valid delimiter
        foundr = false
        if b == UInt8('\r')
            foundr = true
            pos += 1
            pos > len && return pos
            b = getbyte(buf, pos)
        end
        if b == UInt8('\n')
            pos += 1
            pos > len && return pos
            b = getbyte(buf, pos)
        elseif !foundr
            # if we didn't find a newline and we're not EOF
            # then that's an error; only whitespace, newlines,
            # and EOFs are valid in between lines
            error = ExpectedNewline
            @goto invalid
        end
        # since we found a newline, we now ignore all whitespace, including newlines (empty lines)
        # until we find EOF or non-whitespace
        while b == UInt8(' ') || b == UInt8('\t') || b == UInt8('\n') || b == UInt8('\r')
            pos += 1
            pos > len && return pos
            b = getbyte(buf, pos)
        end
    end)
end

# core JSON array parsing function
# takes a `keyvalfunc` that is applied to each index => value element
# `keyvalfunc` is provided a Int => LazyValue pair
# applyeach always requires a key-value pair function
# so we use the index as the key
# returns a `pos` value that notes the next position where parsing should continue
# this is essentially the `StructUtils.applyeach` implementation for LazyValues w/ type ARRAY
function applyarray(keyvalfunc, x::LazyValues)
    pos::Int = getpos(x)
    buf = getbuf(x)
    len = getlength(buf)
    opts = getopts(x)
    jsonlines = opts.jsonlines
    b = getbyte(buf, pos)
    if !jsonlines
        if b != UInt8('[')
            error = ExpectedOpeningArrayChar
            @goto invalid
        end
        pos += 1
        @nextbyte
        b == UInt8(']') && return pos + 1
    else
        # for jsonlines, we need to make sure that recursive
        # lazy values *don't* consider individual lines *also*
        # to be jsonlines
        opts = LazyOptions(; allownan=opts.allownan, ninf=opts.ninf, inf=opts.inf, nan=opts.nan, jsonlines=false, duplicate_keys=opts.duplicate_keys)
    end
    i = 1
    while true
        # we're now positioned at the start of the value
        val = _lazy(buf, pos, len, b, opts)
        ret = keyvalfunc(i, val)
        ret isa StructUtils.EarlyReturn && return ret
        # if keyvalfunc didn't materialize `val` and return an
        # updated `pos`, then we need to skip val ourselves
        # WARNING: parsing can get corrupted if random Int values are returned from keyvalfunc
        pos = (ret isa Int && ret > pos) ? ret : skip(val)
        if jsonlines
            @jsonlines_checks
        else
            @nextbyte
            if b == UInt8(']')
                return pos + 1
            elseif b != UInt8(',')
                error = ExpectedComma
                @goto invalid
            end
            pos += 1 # move past ','
            @nextbyte
        end
        i += 1
    end

@label invalid
    invalid(error, buf, pos, "array")
end

# temporary string type to enable deferrment of string allocation in certain cases (like navigating a lazy structure)
struct PtrString
    ptr::Ptr{UInt8}
    len::Int
    escaped::Bool
end

if VERSION < v"1.11"
    mem(n) = Vector{UInt8}(undef, n)
    _tostr(m::Vector{UInt8}, slen) = ccall(:jl_array_to_string, Ref{String}, (Any,), resize!(m, slen))
else
    mem(n) = Memory{UInt8}(undef, n)
    _tostr(m::Memory{UInt8}, slen) = ccall(:jl_genericmemory_to_string, Ref{String}, (Any, Int), m, slen)
end

function Base.convert(::Type{String}, x::PtrString)
    if x.escaped
        m = mem(x.len)
        slen = GC.@preserve m unsafe_unescape_to_buffer(x.ptr, x.len, pointer(m))
        return _tostr(m, slen)
    end
    return unsafe_string(x.ptr, x.len)
end

Base.convert(::Type{Symbol}, x::PtrString) = x.escaped ?
    Symbol(convert(String, x)) :
    ccall(:jl_symbol_n, Ref{Symbol}, (Ptr{UInt8}, Int), x.ptr, x.len)

function Base.convert(::Type{T}, x::PtrString) where {T <: Enum}
    sym = convert(Symbol, x)
    for (k, v) in Base.Enums.namemap(T)
        v === sym && return T(k)
    end
    throw(ArgumentError("invalid `$T` string value: \"$sym\""))
end

Base.:(==)(x::PtrString, y::AbstractString) = x.escaped ?
    convert(String, x) == y :
    x.len == sizeof(y) && ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), x.ptr, pointer(y), x.len) == 0
Base.:(==)(x::AbstractString, y::PtrString) = y == x
Base.:(==)(x::PtrString, y::PtrString) = x.escaped || y.escaped ?
    convert(String, x) == convert(String, y) :
    x.len == y.len && ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), x.ptr, y.ptr, x.len) == 0
Base.isequal(x::PtrString, y::AbstractString) = x == y
Base.isequal(x::AbstractString, y::PtrString) = y == x
Base.isequal(x::PtrString, y::PtrString) = x == y
Base.hash(x::PtrString, h::UInt) = x.escaped ?
    hash(convert(String, x), h) :
    hash(unsafe_string(x.ptr, x.len), h)
StructUtils.keyeq(x::PtrString, y::AbstractString) = x == y
StructUtils.keyeq(x::PtrString, y::String) = x == y
StructUtils.keyeq(x::PtrString, y::Symbol) = convert(Symbol, x) == y

# JSON owns PtrString and its comparison semantics, so it can use the ordered
# field cursor without changing StructUtils' behavior for arbitrary key types.
@inline StructUtils.orderedfieldmatch(x::PtrString, field::String) = x == field

# core JSON string parsing function
# returns a PtrString and the next position to parse
# a PtrString is a semi-lazy, internal-only representation
# that notes whether escape characters were encountered while parsing
# or not. It allows materialize, _binary, etc. to deal
# with the string data appropriately without forcing a String allocation
# PtrString should NEVER be visible to users though!
function parsestring(x::LazyValue)
    buf, pos = getbuf(x), getpos(x)
    len, b = getlength(buf), getbyte(buf, pos)
    if b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    spos = pos
    escaped = false
    @nextbyte(false)
    while b != UInt8('"')
        # disallow raw control characters within a JSON string
        b <= UInt8(0x1F) && unescaped_control(b)
        if b == UInt8('\\')
            # skip next character
            escaped = true
            if pos + 2 > len
                error = UnexpectedEOF
                @goto invalid
            end
            pos += 2
        else
            pos += 1
        end
        @nextbyte(false)
    end
    str = PtrString(pointer(buf, spos), pos - spos, escaped)
    return str, pos + 1

@label invalid
    invalid(error, buf, pos, "string")
end

# core JSON number parsing function
# JSON validates the number token against the JSON grammar itself, then hands
# the exact byte span to the Parsers kernels for conversion; valid return
# types include: Int64, BigInt, Float64 or BigFloat

# match `special` at `pos`; returns the position after the match, or 0 if no match
@inline function matchspecial(buf, pos, len, special::String)
    bytes = codeunits(special)
    n = length(bytes)
    (n == 0 || pos + n - 1 > len) && return 0
    for i = 1:n
        getbyte(buf, pos + i - 1) == @inbounds(bytes[i]) || return 0
    end
    return pos + n
end

# integer digits are accumulated as a negative number so typemin(Int64) fits
const INT64_MIN_DIV10 = div(typemin(Int64), 10)
const INT64_MIN_LASTDIGIT = -rem(typemin(Int64), 10)
# Parsers 2's xparse2 finds the end of a float itself, so the scanner stops at
# the first '.'/'e'; the Parsers 3 kernels need the exact span, so it scans to the end
const SCANFLOATTAIL = !isdefined(Parsers, :xparse2)

# scan a JSON number token starting at `startpos`; returns the position after
# the token (or after the integer part if !SCANFLOATTAIL), whether it has a
# fraction or exponent, the integer value, and whether that value overflowed Int64;
# nextpos == startpos means the bytes at startpos are not a valid JSON number
@inline function scannumber(buf, startpos, len)
    pos = startpos
    b = getbyte(buf, pos)
    isneg = b == UInt8('-')
    # leading '+' only reaches here with allownan=true (see `_lazy`)
    if isneg || b == UInt8('+')
        pos += 1
        pos > len && return startpos, false, Int64(0), false
        b = getbyte(buf, pos)
    end
    val = Int64(0)
    overflow = false
    # integer part; leading zeros are invalid JSON
    if b == UInt8('0')
        pos += 1
        pos <= len && UInt8('0') <= getbyte(buf, pos) <= UInt8('9') && return startpos, false, val, false
    elseif UInt8('1') <= b <= UInt8('9')
        while true
            digit = Int64(b - UInt8('0'))
            if val < INT64_MIN_DIV10 || (val == INT64_MIN_DIV10 && digit > INT64_MIN_LASTDIGIT)
                overflow = true
            else
                val = Int64(10) * val - digit
            end
            pos += 1
            pos > len && break
            b = getbyte(buf, pos)
            UInt8('0') <= b <= UInt8('9') || break
        end
    else
        return startpos, false, val, false
    end
    isfloat = false
    # fraction: at least one digit required after '.'
    if pos <= len && getbyte(buf, pos) == UInt8('.')
        isfloat = true
        pos += 1
        (pos > len || !(UInt8('0') <= getbyte(buf, pos) <= UInt8('9'))) && return startpos, false, val, false
        SCANFLOATTAIL || return pos, true, val, overflow
        while pos <= len && UInt8('0') <= getbyte(buf, pos) <= UInt8('9')
            pos += 1
        end
    end
    # exponent: optional sign, at least one digit
    if pos <= len && (getbyte(buf, pos) == UInt8('e') || getbyte(buf, pos) == UInt8('E'))
        isfloat = true
        SCANFLOATTAIL || return pos, true, val, overflow
        pos += 1
        if pos <= len && (getbyte(buf, pos) == UInt8('+') || getbyte(buf, pos) == UInt8('-'))
            pos += 1
        end
        (pos > len || !(UInt8('0') <= getbyte(buf, pos) <= UInt8('9'))) && return startpos, false, val, false
        while pos <= len && UInt8('0') <= getbyte(buf, pos) <= UInt8('9')
            pos += 1
        end
    end
    if !isneg
        val == typemin(Int64) ? (overflow = true) : (val = -val)
    end
    return pos, isfloat, val, overflow
end

const INT = 0x00
const FLOAT = 0x01
const BIGINT = 0x02
const BIGFLOAT = 0x03
const BIG_ZERO = BigInt(0)

struct NumberResult
    tag::UInt8
    int::Int64
    float::Float64
    bigint::BigInt
    bigfloat::BigFloat
    NumberResult(int::Int64) = new(INT, int)
    NumberResult(float::Float64) = new(FLOAT, Int64(0), float)
    NumberResult(bigint::BigInt) = new(BIGINT, Int64(0), 0.0, bigint)
    NumberResult(bigfloat::BigFloat) = new(BIGFLOAT, Int64(0), 0.0, BIG_ZERO, bigfloat)
end

isint(x::NumberResult) = x.tag == INT
isfloat(x::NumberResult) = x.tag == FLOAT
isbigint(x::NumberResult) = x.tag == BIGINT
isbigfloat(x::NumberResult) = x.tag == BIGFLOAT

# Parsers converts the validated token span; Parsers 2 and 3 have different APIs
@inline numberbytes(buf::AbstractString) = codeunits(buf)
@inline numberbytes(buf) = buf

@static if isdefined(Parsers, :xparse2)
    # Parsers 2: `xparse2` parses the longest number prefix of buf[first:len]
    @inline function parsefloat64(buf, first, nextpos, len, allownan)
        res = Parsers.xparse2(Float64, buf, first, len)
        nextpos = first + Int(res.tlen)
        if !allownan && Parsers.specialvalue(res.code)
            # overflowed to Inf; promote to BigFloat
            bres = Parsers.xparse2(BigFloat, buf, first, len)
            Parsers.invalid(bres.code) || return NumberResult(bres.val), nextpos
        end
        Parsers.invalid(res.code) && invalid(InvalidNumber, buf, first, "number")
        return NumberResult(res.val), nextpos
    end
    @inline parsebigint(buf, first, last) = NumberResult(Parsers.xparse2(BigInt, buf, first, last).val)
    # native `[+-]NaN`, `[+-]Inf`, `[+-]Infinity` spellings (case-insensitive)
    @inline function parsenativespecial(buf, pos, len)
        res = Parsers.xparse2(Float64, buf, pos, len)
        (Parsers.invalid(res.code) || isfinite(res.val)) && return nothing
        return NumberResult(res.val), pos + Int(res.tlen)
    end
    @inline function exactintegerend(buf, first, nextpos, len)
        res = Parsers.xparse2(Float64, buf, first, len)
        Parsers.invalid(res.code) && invalid(InvalidNumber, buf, first, "number")
        return first + Int(res.tlen)
    end
else
    # Parsers 3: the kernels convert exactly buf[first:nextpos-1]
    @inline function parsefloat64(buf, first, nextpos, len, allownan)
        bytes = numberbytes(buf)
        val, code = Parsers.parsefloat(Float64, bytes, first, nextpos - 1)
        if !allownan && code == Parsers.RC_OVERFLOW
            # promote to BigFloat
            return NumberResult(Parsers.parse(BigFloat, bytes, first, nextpos - 1)), nextpos
        end
        return NumberResult(val), nextpos
    end
    @inline parsebigint(buf, first, last) = NumberResult(Parsers.parsebigint(numberbytes(buf), first, last)[1])
    # native `[+-]NaN`, `[+-]Inf`, `[+-]Infinity` spellings (case-insensitive)
    @inline function parsenativespecial(buf, pos, len)
        val, nextpos, code = Parsers.parsenext(Float64, numberbytes(buf), pos, len)
        (code != Parsers.RC_OK || isfinite(val)) && return nothing
        return NumberResult(val), nextpos
    end
    @inline exactintegerend(buf, first, nextpos, len) = nextpos
end

# BigInt fallback for tokens whose coefficient does not fit in UInt128. This is
# only needed when a large coefficient is reduced by a negative decimal scale.
function parseexactintegerbig(buf, first, nextpos, ::Type{T}) where {T}
    pos = first
    b = getbyte(buf, pos)
    isneg = b == UInt8('-')
    if isneg || b == UInt8('+')
        pos += 1
    end

    coefficient = BigInt(0)
    fractiondigits = 0
    infraction = false
    while pos < nextpos
        b = getbyte(buf, pos)
        if UInt8('0') <= b <= UInt8('9')
            coefficient = coefficient * 10 + (b - UInt8('0'))
            infraction && (fractiondigits += 1)
        elseif b == UInt8('.')
            infraction = true
        else
            break
        end
        pos += 1
    end

    exponent = BigInt(0)
    if pos < nextpos
        pos += 1 # skip 'e' or 'E'
        b = getbyte(buf, pos)
        expneg = b == UInt8('-')
        if expneg || b == UInt8('+')
            pos += 1
        end
        while pos < nextpos
            exponent = exponent * 10 + (getbyte(buf, pos) - UInt8('0'))
            pos += 1
        end
        expneg && (exponent = -exponent)
    end

    iszero(coefficient) && return NumberResult(coefficient), nextpos
    scale = exponent - fractiondigits
    if scale >= 0
        maxmagnitude = max(abs(BigInt(typemin(T))), abs(BigInt(typemax(T))))
        ndigits(coefficient) + scale <= ndigits(maxmagnitude) ||
            throw(InexactError(:parse, T, coefficient))
        scale <= typemax(Int) || throw(OverflowError("JSON integer exponent is too large"))
        coefficient *= big(10)^Int(scale)
    else
        -scale < ndigits(coefficient) || throw(InexactError(:parse, T, coefficient))
        -scale <= typemax(Int) || throw(InexactError(:parse, T, coefficient))
        quotient, remainder = divrem(coefficient, big(10)^Int(-scale))
        iszero(remainder) || throw(InexactError(:parse, T, coefficient))
        coefficient = quotient
    end
    isneg && (coefficient = -coefficient)
    return NumberResult(coefficient), nextpos
end

# Convert a validated decimal or exponent token to an exact fixed-width integer.
# UInt128 keeps the common path allocation-free; unusually long coefficients
# fall back to BigInt only when a negative scale can reduce them to fit.
function parseexactinteger(buf, first, nextpos, len, ::Type{T}) where {T}
    nextpos = exactintegerend(buf, first, nextpos, len)
    pos = first
    b = getbyte(buf, pos)
    isneg = b == UInt8('-')
    if isneg || b == UInt8('+')
        pos += 1
    end

    coefficient = UInt128(0)
    fractiondigits = 0
    infraction = false
    while pos < nextpos
        b = getbyte(buf, pos)
        if UInt8('0') <= b <= UInt8('9')
            digit = UInt128(b - UInt8('0'))
            coefficient <= div(typemax(UInt128) - digit, 10) ||
                return parseexactintegerbig(buf, first, nextpos, T)
            coefficient = coefficient * 10 + digit
            infraction && (fractiondigits += 1)
        elseif b == UInt8('.')
            infraction = true
        else
            break
        end
        pos += 1
    end

    iszero(coefficient) && return NumberResult(Int64(0)), nextpos
    exponent = 0
    if pos < nextpos
        pos += 1 # skip 'e' or 'E'
        b = getbyte(buf, pos)
        expneg = b == UInt8('-')
        if expneg || b == UInt8('+')
            pos += 1
        end
        # A UInt128 coefficient cannot survive an absolute decimal scale of 39.
        # Saturating here prevents exponent text from overflowing Int.
        explimit = expneg ? 39 : min(fractiondigits, typemax(Int) - 39) + 39
        while pos < nextpos
            digit = Int(getbyte(buf, pos) - UInt8('0'))
            if exponent > div(explimit - digit, 10)
                exponent = explimit
                break
            end
            exponent = exponent * 10 + digit
            pos += 1
        end
        expneg && (exponent = -exponent)
    end

    scale = exponent - fractiondigits
    if scale >= 0
        scale < 39 || throw(InexactError(:parse, T, coefficient))
        for _ = 1:scale
            coefficient <= div(typemax(UInt128), 10) ||
                throw(InexactError(:parse, T, coefficient))
            coefficient *= 10
        end
    else
        -scale < 39 || throw(InexactError(:parse, T, coefficient))
        divisor = UInt128(1)
        for _ = 1:-scale
            divisor *= 10
        end
        quotient, remainder = divrem(coefficient, divisor)
        iszero(remainder) || throw(InexactError(:parse, T, coefficient))
        coefficient = quotient
    end

    limit = if isneg
        T <: Signed ? UInt128(typemax(T)) + 1 : UInt128(0)
    else
        UInt128(typemax(T))
    end
    coefficient <= limit || throw(InexactError(:parse, T, coefficient))
    if coefficient <= UInt128(typemax(Int64))
        val = Int64(coefficient)
        return NumberResult(isneg ? -val : val), nextpos
    elseif isneg && coefficient == UInt128(typemax(Int64)) + 1
        return NumberResult(typemin(Int64)), nextpos
    end
    return NumberResult(isneg ? -BigInt(coefficient) : BigInt(coefficient)), nextpos
end

# `T` is the type requested for this value (`Number` when materializing untyped);
# with `allownan=true`, untyped numbers materialize as `Float64`, while a
# requested fixed-width integer type up to 128 bits is converted exactly from
# the number token
@inline function parsenumber(x::LazyValue, ::Type{T}=Any) where {T}
    buf = getbuf(x)
    startpos::Int = getpos(x)
    len = getlength(buf)
    opts = getopts(x)
    if opts.allownan
        # check for configured NaN, Inf, -Inf spellings
        pos = matchspecial(buf, startpos, len, opts.nan)
        pos != 0 && return NumberResult(NaN), pos
        pos = matchspecial(buf, startpos, len, opts.inf)
        pos != 0 && return NumberResult(Inf), pos
        pos = matchspecial(buf, startpos, len, opts.ninf)
        pos != 0 && return NumberResult(-Inf), pos
    end
    nextpos, isfloat, val, overflow = scannumber(buf, startpos, len)
    if nextpos == startpos
        if opts.allownan
            res = parsenativespecial(buf, startpos, len)
            res === nothing || return res
        end
        invalid(InvalidNumber, buf, startpos, "number")
    end
    exactint = isbitstype(T) && sizeof(T) <= sizeof(UInt128) &&
        (T === Bool || T <: Signed || T <: Unsigned)
    if isfloat && opts.allownan && exactint
        return parseexactinteger(buf, startpos, nextpos, len, T)
    elseif isfloat || (opts.allownan && (T === Any || T === Number))
        return parsefloat64(buf, startpos, nextpos, len, opts.allownan)
    end
    overflow || return NumberResult(val), nextpos
    # promote to BigInt
    return parsebigint(buf, startpos, nextpos - 1), nextpos
end

# efficiently skip over a JSON value
# for object/array/string/number, we pass no-op functions
# and for bool/null, we just skip the appropriate number of bytes
function skip(x::LazyValues)
    T = gettype(x)
    if T == JSONTypes.OBJECT
        return applyobject((k, v) -> 0, x)
    elseif T == JSONTypes.ARRAY
        return applyarray((i, v) -> 0, x)
    elseif T == JSONTypes.STRING
        _, pos = parsestring(x)
        return pos
    elseif T == JSONTypes.NUMBER
        _, pos = parsenumber(x)
        return pos
    elseif T == JSONTypes.TRUE
        return getpos(x) + 4
    elseif T == JSONTypes.FALSE
        return getpos(x) + 5
    elseif T == JSONTypes.NULL
        return getpos(x) + 4
    else
        error("invalid JSON value type: $T")
    end
end

# helper definitions for LazyObject/LazyArray to they display as such
gettype(::LazyObject) = JSONTypes.OBJECT

Base.length(x::LazyObject) = StructUtils.applylength(x)

struct IterateObjectClosure
    kvs::Vector{Pair{String, LazyValue}}
end

function (f::IterateObjectClosure)(k, v)
    push!(f.kvs, convert(String, k) => v)
    return
end

function Base.iterate(x::LazyObject, st=nothing)
    if st === nothing
        # first iteration
        kvs = Pair{String, LazyValue}[]
        applyobject(IterateObjectClosure(kvs), x)
        i = 1
    else
        kvs = st[1]
        i = st[2]
    end
    i > length(kvs) && return nothing
    return kvs[i], (kvs, i + 1)
end

gettype(::LazyArray) = JSONTypes.ARRAY

Base.IndexStyle(::Type{<:LazyArray}) = Base.IndexLinear()

Base.size(x::LazyArray) = (StructUtils.applylength(x),)

Base.isassigned(x::LazyArray, i::Int) = true
Base.getindex(x::LazyArray, i::Int) = Selectors._getindex(x, i)

# show implementation for LazyValue
function Base.show(io::IO, x::LazyValue)
    T = gettype(x)
    if T == JSONTypes.OBJECT
        compact = get(io, :compact, false)::Bool
        lo = LazyObject(x)
        if compact
            show(io, lo)
        else
            io = IOContext(io, :compact => true)
            show(io, MIME"text/plain"(), lo)
        end
    elseif T == JSONTypes.ARRAY
        compact = get(io, :compact, false)::Bool
        la = LazyArray(x)
        if compact
            show(io, la)
        else
            io = IOContext(io, :compact => true)
            show(io, MIME"text/plain"(), la)
        end
    elseif T == JSONTypes.STRING
        buf = getbuf(x)
        GC.@preserve buf begin
            str, _ = parsestring(x)
            Base.print(io, "JSON.LazyValue(", repr(convert(String, str)), ")")
        end
    elseif T == JSONTypes.NULL
        Base.print(io, "JSON.LazyValue(nothing)")
    else # bool/number
        Base.print(io, "JSON.LazyValue(", parse(x), ")")
    end
end
