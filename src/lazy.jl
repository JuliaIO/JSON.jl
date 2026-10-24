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
  - `allownan::Bool = false`: whether "special" float values should be allowed while parsing (`NaN`, `Inf`, `-Inf`); these values are specifically _not allowed_ in the JSON spec, but many JSON libraries allow reading/writing. When `true`, untyped numbers are parsed as `Float64`. A requested fixed-width integer type of up to 128 bits is parsed exactly from the number token
  - `ninf::String = "-Infinity"`: the string that will be used to parse `-Inf` if `allownan=true`
  - `inf::String = "Infinity"`: the string that will be used to parse `Inf` if `allownan=true`
  - `nan::String = "NaN"`: the string that will be used to parse `NaN` if `allownan=true`
  - `jsonlines::Bool = false`: whether the JSON input should be treated as an implicit array, with newlines separating individual JSON elements with no leading `'['` or trailing `']'` characters. Common in logging or streaming workflows. Defaults to `true` when used with `JSON.parsefile` and the filename extension is `.jsonl` or `.ndjson`. Note this ensures that parsing will _always_ return an array at the root-level.
  - `duplicate_keys::Symbol = :overwrite`: how repeated object keys are handled. `:overwrite` preserves the default last-value-wins behavior. `:error` throws [`JSON.DuplicateKeyError`](@ref).
  - `maxdepth::Integer = 512`: the deepest nesting of objects and arrays that will be parsed; deeper input throws an `ArgumentError` instead of overflowing the stack. `jsonlines` input counts its implicit outer array as one level
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
    # Int32 fills padding after `jsonlines`, so LazyValues stay the same size
    maxdepth::Int32 = 512
    duplicate_keys::Symbol = :overwrite
end

lazy(io::Union{IO, Base.AbstractCmd}; kw...) = lazy(Base.read(io); kw...)

lazyfile(file; jsonlines::Union{Bool, Nothing}=nothing, kw...) = open(io -> lazy(io; jsonlines=(jsonlines === nothing ? isjsonl(file) : jsonlines), kw...), file)

"See [`lazy`](@ref)."
lazyfile

function lazy(buf::Union{AbstractVector{UInt8}, AbstractString}; isroot::Bool=true, maxdepth::Integer=512, kw...)
    # the limit is stored as an Int32; clamp so `maxdepth=typemax(Int)` means "no limit"
    opts = LazyOptions(; maxdepth=min(maxdepth, typemax(Int32)), kw...)
    opts.duplicate_keys in (:overwrite, :error) || throw(ArgumentError("`duplicate_keys` must be `:overwrite` or `:error`, got `$(repr(opts.duplicate_keys))`"))
    # the parser reads `buf[pos]` for `pos in 1:len` and takes `pointer(buf, pos)`;
    # inputs without that layout are copied first
    if buf isa AbstractString
        # positions count UTF-8 bytes, so strings of wider code units are converted too
        (applicable(pointer, buf, 1) && codeunit(buf) === UInt8) || (buf = String(buf))
    elseif !(buf isa StridedVector{UInt8} && stride(buf, 1) == 1 && !Base.has_offset_axes(buf))
        buf = copyto!(Vector{UInt8}(undef, length(buf)), buf)
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
    return _lazy(buf, pos, len, b, opts, isroot, Int32(0))

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
    depth::Int32 # number of objects/arrays enclosing this value; fills padding after `isroot`
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
    depth::Int32
    LazyObject(x::LazyValue{T}) where {T} = new{T}(getbuf(x), getpos(x), getopts(x), getisroot(x), getdepth(x))
end

struct LazyArray{T} <: AbstractVector{LazyValue}
    buf::T
    pos::Int
    opts::LazyOptions
    isroot::Bool
    depth::Int32
    # each element's start position and type, found in one pass: indexing by scanning from
    # the first element made displaying an n-element array O(n^2). `getindex` rebuilds the
    # element's much larger LazyValue from them.
    positions::Vector{Int}
    types::Vector{JSONTypes.T}
    function LazyArray(x::LazyValue{T}) where {T}
        positions = Int[]
        types = JSONTypes.T[]
        applyarray((_, v) -> (push!(positions, getpos(v)); push!(types, gettype(v))), x)
        return new{T}(getbuf(x), getpos(x), getopts(x), getisroot(x), getdepth(x), positions, types)
    end
end

# helper accessors so we can overload getproperty for convenience
getbuf(x) = getfield(x, :buf)
getpos(x) = getfield(x, :pos)
gettype(x) = getfield(x, :type)
getopts(x) = getfield(x, :opts)
getisroot(x) = getfield(x, :isroot)
getdepth(x) = getfield(x, :depth)

const LazyValues{T} = Union{LazyValue{T}, LazyObject{T}, LazyArray{T}}

# default materialization that calls parse
Base.getindex(x::LazyValues) = parse(x)

# some overloads/usage of StructUtils + LazyValues
# this defines all the right getproperty, getindex methods
Selectors.@selectors LazyValues

Base.lastindex(x::LazyValues) = length(x)

# this ensures LazyValues can be "sources" in StructUtils.make
function StructUtils.applyeach(st::StructUtils.StructStyle, f, x::LazyValues)
    type = gettype(x)
    if type == JSONTypes.OBJECT
        return applyobject(_contextcallback(st, f), x)
    elseif type == JSONTypes.ARRAY
        return applyarray(_contextcallback(st, f), x)
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
        # return `nothing`: an `Int` returned from the callback would be read as the next parse position
        applyobject((k, v) -> (f(String(k) => v); nothing), x)
    elseif type == JSONTypes.ARRAY
        applyarray((i, v) -> (f(v); nothing), x)
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
function _lazy(buf, pos::Int, len, b, opts, isroot, depth)
    if opts.jsonlines
        return LazyValue(buf, pos, JSONTypes.ARRAY, opts, isroot, depth)
    elseif b == UInt8('{')
        return LazyValue(buf, pos, JSONTypes.OBJECT, opts, isroot, depth)
    elseif b == UInt8('[')
        return LazyValue(buf, pos, JSONTypes.ARRAY, opts, isroot, depth)
    elseif b == UInt8('"')
        return LazyValue(buf, pos, JSONTypes.STRING, opts, isroot, depth)
    elseif b == UInt8('n') && pos + 3 <= len &&
        getbyte(buf, pos + 1) == UInt8('u') &&
        getbyte(buf, pos + 2) == UInt8('l') &&
        getbyte(buf, pos + 3) == UInt8('l')
        return LazyValue(buf, pos, JSONTypes.NULL, opts, isroot, depth)
    elseif b == UInt8('t') && pos + 3 <= len &&
        getbyte(buf, pos + 1) == UInt8('r') &&
        getbyte(buf, pos + 2) == UInt8('u') &&
        getbyte(buf, pos + 3) == UInt8('e')
        return LazyValue(buf, pos, JSONTypes.TRUE, opts, isroot, depth)
    elseif b == UInt8('f') && pos + 4 <= len &&
        getbyte(buf, pos + 1) == UInt8('a') &&
        getbyte(buf, pos + 2) == UInt8('l') &&
        getbyte(buf, pos + 3) == UInt8('s') &&
        getbyte(buf, pos + 4) == UInt8('e')
        return LazyValue(buf, pos, JSONTypes.FALSE, opts, isroot, depth)
    elseif b == UInt8('-') || (UInt8('0') <= b <= UInt8('9')) || (opts.allownan && (b == UInt8('+') || firstbyteeq(opts.nan, b) || firstbyteeq(opts.ninf, b) || firstbyteeq(opts.inf, b)))
        return LazyValue(buf, pos, JSONTypes.NUMBER, opts, isroot, depth)
    else
        error = InvalidJSON
        @goto invalid
    end
@label invalid
    if !opts.allownan
        # quick check if the value here is inf/nan/+1 and we can provide
        # a more helpful error message about how to parse
        b in (UInt8('N'), UInt8('I'), UInt8('+')) && nanhint(pos)
    end
    invalid(error, buf, pos, Any)
end

@noinline nanhint(pos) = throw(ArgumentError(string("JSON parsing error at byte position ", pos,
    ": possible `NaN`, `Inf`, or `-Inf` which are not valid JSON values. Use the `allownan=true` option and `ninf`, `inf`, and/or `nan` keyword arguments to parse.")))

# core JSON object parsing function
# takes a `keyvalfunc` that is applied to each key/value pair
# `keyvalfunc` receives a PtrString => LazyValue pair
# `keyvalfunc` can return `StructUtils.EarlyReturn` to short-circuit parsing
# otherwise, it should return a `pos::Int` value that notes the next position to continue parsing
# to materialize the key, call `String(key)`
# PtrString can be compared to String via `==` or `isequal` to help avoid allocating the full String in some cases
# returns a `pos` value that notes the next position where parsing should continue
# this is essentially the `StructUtils.applyeach` implementation for LazyValues w/ type OBJECT
function applyobject(keyvalfunc, x::LazyValues)
    pos::Int = getpos(x)
    buf = getbuf(x)
    len = getlength(buf)
    opts = getopts(x)
    depth = getdepth(x) + Int32(1)
    depth > opts.maxdepth && toodeep(pos, opts.maxdepth)
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
            key, pos = @inline parsestring(LazyValue(buf, pos, JSONTypes.STRING, opts, false, depth))
            if seen !== nothing
                decoded = String(key)
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
            val = _lazy(buf, pos, len, b, opts, false, depth)
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

# options for the lines of a jsonlines array: each line is an ordinary JSON value, not
# another jsonlines array
lineopts(opts::LazyOptions) = LazyOptions(; allownan=opts.allownan, ninf=opts.ninf, inf=opts.inf, nan=opts.nan, jsonlines=false, duplicate_keys=opts.duplicate_keys, maxdepth=opts.maxdepth)

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
    depth = getdepth(x) + Int32(1)
    depth > opts.maxdepth && toodeep(pos, opts.maxdepth)
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
        opts = lineopts(opts)
    end
    i = 1
    while true
        # we're now positioned at the start of the value
        val = _lazy(buf, pos, len, b, opts, false, depth)
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

# `String(x)` materializes a PtrString, for example a key passed to an `applyobject` callback.
# PtrString deliberately has no `Base.convert` methods: `convert(::Type{String}, ::PtrString)`
# or `convert(::Type{Symbol}, ::PtrString)` would invalidate every compiled
# `convert(String, ::Any)` or `convert(Symbol, ::Any)` call when JSON loads.
function Base.String(x::PtrString)
    if x.escaped
        m = mem(x.len)
        slen = GC.@preserve m unsafe_unescape_to_buffer(x.ptr, x.len, pointer(m))
        return _tostr(m, slen)
    end
    return unsafe_string(x.ptr, x.len)
end

# StructUtils' selectors (`propertynames`, `hasproperty`) turn keys into Symbols with this helper.
Selectors._symbol(x::PtrString) = x.escaped ?
    Symbol(String(x)) :
    ccall(:jl_symbol_n, Ref{Symbol}, (Ptr{UInt8}, Int), x.ptr, x.len)

# only String and SubString{String} are compared byte for byte: other strings may have no
# `pointer` or may not store UTF-8
Base.:(==)(x::PtrString, y::AbstractString) = x.escaped || !(y isa Union{String, SubString{String}}) ?
    String(x) == y :
    x.len == sizeof(y) && ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), x.ptr, pointer(y), x.len) == 0
Base.:(==)(x::AbstractString, y::PtrString) = y == x
Base.:(==)(x::PtrString, y::PtrString) = x.escaped || y.escaped ?
    String(x) == String(y) :
    x.len == y.len && ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), x.ptr, y.ptr, x.len) == 0
Base.hash(x::PtrString, h::UInt) = x.escaped ?
    hash(String(x), h) :
    hash(unsafe_string(x.ptr, x.len), h)
StructUtils.keyeq(x::PtrString, y::AbstractString) = x == y
StructUtils.keyeq(x::PtrString, y::String) = x == y
# compare with the Symbol's name instead of making a Symbol from the key: a key
# with an escaped NUL is not a valid Symbol name, and can never equal one
function StructUtils.keyeq(x::PtrString, y::Symbol)
    x.escaped && return String(x) == String(y)
    name = Base.unsafe_convert(Ptr{UInt8}, y)
    return x.len == ccall(:strlen, Csize_t, (Ptr{UInt8},), name) &&
        ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), x.ptr, name, x.len) == 0
end

# Selector predicates (`x[~, (k, v) -> ...]`, `x[:, (k, v) -> ...]`) are user code, so they get
# `String` keys: a PtrString points into the input and is only valid during the callback.
struct StringKeys{F} <: Function
    f::F
end
(g::StringKeys)(k, v) = g.f(k isa PtrString ? String(k) : k, v)
stringkeys(f) = StringKeys(f)
stringkeys(f::StringKeys) = f # nested values are searched with the same wrapper

Selectors._getindex(x::LazyValues, S::Union{typeof(~), Colon}, f::Base.Callable, values=Selectors.List()) =
    @invoke Selectors._getindex(x::Any, S::Union{typeof(~), Colon}, stringkeys(f)::Base.Callable, values::Any)
# `:` is also a `Function`; `x[~, :]` keeps meaning "every nested value"
Selectors._getindex(x::LazyValues, S::typeof(~), key::Colon) =
    invoke(Selectors._getindex, Tuple{Any, typeof(~), Union{Selectors.KeyInd, Colon}}, x, S, key)

# JSON owns PtrString and its comparison semantics, so it can use the ordered
# field cursor without changing StructUtils' behavior for arbitrary key types.
@inline StructUtils.orderedfieldmatch(x::PtrString, field::String) = x == field

# bit `c` is set for each byte `c` that may follow `\` other than `u`
const SIMPLEESCAPES = mapreduce(c -> UInt128(1) << UInt8(c), |, "\"\\/bfnrt")
@inline ishexbyte(b) = UInt8('0') <= b <= UInt8('9') || UInt8('a') <= (b | 0x20) <= UInt8('f')

# the position of the closing quote of a string whose first `\` is at `pos`. Validates each
# escape (`\` and one of `"\/bfnrt`, or `\u` and four hex digits) and rejects raw control
# characters. Kept out of `parsestring` so its loop stays small for strings without escapes;
# one call scans the whole escaped remainder.
@noinline function escapedend(buf, pos::Int, len::Int)
    while true
        pos > len && invalid(UnexpectedEOF, buf, pos, "string")
        b = getbyte(buf, pos)
        b == UInt8('"') && return pos
        b <= UInt8(0x1F) && invalid(InvalidChar, buf, pos, "string")
        if b == UInt8('\\')
            # the escaped character and the closing quote
            pos + 2 > len && invalid(UnexpectedEOF, buf, pos, "string")
            b = getbyte(buf, pos + 1)
            if b == UInt8('u')
                if pos + 6 > len
                    # no room for four hex digits and the closing quote: report the first bad byte
                    for i = (pos + 2):(pos + 5)
                        i > len && invalid(UnexpectedEOF, buf, i, "string")
                        ishexbyte(getbyte(buf, i)) || invalid(InvalidEscape, buf, i, "string")
                    end
                    invalid(UnexpectedEOF, buf, len + 1, "string")
                end
                for i = (pos + 2):(pos + 5)
                    ishexbyte(getbyte(buf, i)) || invalid(InvalidEscape, buf, i, "string")
                end
                pos += 6
            else
                (b < 0x80 && isodd(SIMPLEESCAPES >> b)) || invalid(InvalidEscape, buf, pos + 1, "string")
                pos += 2
            end
        else
            pos += 1
        end
    end
end

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
    @nextbyte(false)
    while b != UInt8('"')
        # disallow raw control characters within a JSON string
        b <= UInt8(0x1F) && invalid(InvalidChar, buf, pos, "string")
        if b == UInt8('\\')
            # escapes are validated here, not only when unescaping, so skipped values are too
            pos = escapedend(buf, pos, len)
            return PtrString(pointer(buf, spos), pos - spos, true), pos + 1
        end
        pos += 1
        @nextbyte(false)
    end
    str = PtrString(pointer(buf, spos), pos - spos, false)
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
# the number of leading ASCII digits among the 8 bytes of `w`, first byte in the low bits:
# `x` maps '0'-'9' to 0-9, and adding 0x76 sets a byte's high bit exactly when it is 10 or
# more (masking the high bit first keeps carries inside each byte)
@inline function leadingdigits(w::UInt64)
    x = w ⊻ 0x3030303030303030
    nondigit = (((x & 0x7f7f7f7f7f7f7f7f) + 0x7676767676767676) | x) & 0x8080808080808080
    return trailing_zeros(nondigit) >> 3
end

# the position of the first non-digit byte at or after `pos`, 8 bytes at a time while 8 remain
@inline function skipdigits(buf, pos, len)
    if ENDIAN_BOM == 0x04030201
        GC.@preserve buf while pos + 7 <= len
            n = leadingdigits(unsafe_load(Ptr{UInt64}(pointer(buf, pos))))
            pos += n
            n == 8 || return pos
        end
    end
    while pos <= len && UInt8('0') <= getbyte(buf, pos) <= UInt8('9')
        pos += 1
    end
    return pos
end

# scan a JSON number token starting at `startpos`; returns the position after
# the token, whether it has a fraction or exponent, the integer value, and whether
# that value overflowed Int64; nextpos == startpos means the bytes at startpos are
# not a valid JSON number
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
        pos = skipdigits(buf, pos + 1, len)
    end
    # exponent: optional sign, at least one digit
    if pos <= len && (getbyte(buf, pos) == UInt8('e') || getbyte(buf, pos) == UInt8('E'))
        isfloat = true
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

struct NumberResult
    tag::UInt8
    int::Int64
    float::Float64
    bigint::Union{Nothing,BigInt}
    bigfloat::Union{Nothing,BigFloat}
    NumberResult(int::Int64) = new(INT, int, 0.0, nothing, nothing)
    NumberResult(float::Float64) = new(FLOAT, Int64(0), float, nothing, nothing)
    NumberResult(bigint::BigInt) = new(BIGINT, Int64(0), 0.0, bigint, nothing)
    NumberResult(bigfloat::BigFloat) = new(BIGFLOAT, Int64(0), 0.0, nothing, bigfloat)
end

isint(x::NumberResult) = x.tag == INT
isfloat(x::NumberResult) = x.tag == FLOAT
isbigint(x::NumberResult) = x.tag == BIGINT
isbigfloat(x::NumberResult) = x.tag == BIGFLOAT

# Parsers converts the validated token span; Parsers 2 and 3 have different APIs
@inline numberbytes(buf::AbstractString) = codeunits(buf)
@inline numberbytes(buf) = buf

# Parsers converts BigInt digits in time quadratic in their number (3 million digits take
# seconds); GMP's conversion is subquadratic and faster past this many digits
const LONGINTEGER = 2000
# copy the digits with getindex: `String(view(...))` of a String's code units hashes
# the whole String in its aliasing check, which costs O(document) per integer
@noinline parselongint(buf, first, last) =
    NumberResult(Base.parse(BigInt, String(numberbytes(buf)[first:last])))

@static if isdefined(Parsers, :xparse2)
    # MPFR fallbacks for Parsers 2, which ignores `precision(BigFloat)` and rejects some long
    # in-range tokens; the token is already validated
    @noinline parsebigfloat(buf, first, last) = BigFloat(String(numberbytes(buf)[first:last]))
    @noinline parsebigfloat(buf, first, last, r::RoundingMode) =
        BigFloat(String(numberbytes(buf)[first:last]), r; precision=256)
    # `x` as an exact rational; unlike `Rational{BigInt}(::BigFloat)`, `decompose` doesn't
    # depend on the current BigFloat precision
    function exactrational(x)
        n, p, d = Base.decompose(x)
        r = BigInt(n) // BigInt(d)
        return p >= 0 ? r * big(2)^p : r // big(2)^(-p)
    end
    # the token correctly rounded to `T`. Rounding it down and up to 256 bits brackets its exact
    # value; if the two ends round to different `T`s, the midpoint between those `T`s is one of
    # the ends (it is a 256-bit value), and the exact value lies on the other side of it
    @noinline function parsecorrectlyrounded(::Type{T}, buf, first, last) where {T}
        # rounding to nearest is symmetric, so a negative token rounds its magnitude; only
        # the positive overflow midpoint (above `floatmax(T)`) needs handling below
        getbyte(buf, first) == UInt8('-') && return -parsecorrectlyrounded(T, buf, first + 1, last)
        lo = parsebigfloat(buf, first, last, RoundDown)
        hi = parsebigfloat(buf, first, last, RoundUp)
        a, b = T(lo), T(hi)
        a == b && return a
        a, b = T(lo, RoundDown), T(lo, RoundUp)
        ra = exactrational(a)
        m = isfinite(b) ? (ra + exactrational(b)) // 2 : ra + (ra - exactrational(prevfloat(a))) // 2
        return exactrational(lo) == m ? b : a
    end

    # Parsers 2: `xparse2` converts the longest number prefix of buf[first:last]; the
    # validated token must be all of it (Parsers 2 also takes Julia forms like `1.5f3`)
    @inline function parsefloat64(buf, first, nextpos, len, allownan)
        res = Parsers.xparse2(Float64, buf, first, nextpos - 1)
        if Parsers.invalid(res.code) || first + Int(res.tlen) != nextpos
            x = parsecorrectlyrounded(Float64, buf, first, nextpos - 1)
            isfinite(x) || allownan || return NumberResult(parsebigfloat(buf, first, nextpos - 1)), nextpos
            return NumberResult(x), nextpos
        end
        # overflowed to Inf; promote to BigFloat
        !allownan && Parsers.specialvalue(res.code) && return NumberResult(parsebigfloat(buf, first, nextpos - 1)), nextpos
        return NumberResult(res.val), nextpos
    end
    @inline parsebigint(buf, first, last) = last - first >= LONGINTEGER ?
        parselongint(buf, first, last) : NumberResult(Parsers.xparse2(BigInt, buf, first, last).val)
    @inline function parsefloatas(::Type{T}, buf, first, nextpos, len) where {T}
        T === BigFloat && return NumberResult(parsebigfloat(buf, first, nextpos - 1)), nextpos
        res = Parsers.xparse2(T, buf, first, nextpos - 1)
        if Parsers.invalid(res.code) || first + Int(res.tlen) != nextpos
            return NumberResult(Float64(parsecorrectlyrounded(T, buf, first, nextpos - 1))), nextpos
        end
        return NumberResult(Float64(res.val)), nextpos
    end
    # native `[+-]NaN`, `[+-]Inf`, `[+-]Infinity` spellings (case-insensitive)
    @inline function parsenativespecial(buf, pos, len)
        res = Parsers.xparse2(Float64, buf, pos, len)
        (Parsers.invalid(res.code) || isfinite(res.val)) && return nothing
        return NumberResult(res.val), pos + Int(res.tlen)
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
    @inline parsebigint(buf, first, last) = last - first >= LONGINTEGER ?
        parselongint(buf, first, last) : NumberResult(Parsers.parsebigint(numberbytes(buf), first, last)[1])
    @inline parsefloatas(::Type{T}, buf, first, nextpos, len) where {T<:Union{Float16,Float32}} =
        NumberResult(Float64(Parsers.parsefloat(T, numberbytes(buf), first, nextpos - 1)[1])), nextpos
    @inline parsefloatas(::Type{BigFloat}, buf, first, nextpos, len) =
        NumberResult(Parsers.parse(BigFloat, numberbytes(buf), first, nextpos - 1)), nextpos
    # native `[+-]NaN`, `[+-]Inf`, `[+-]Infinity` spellings (case-insensitive)
    @inline function parsenativespecial(buf, pos, len)
        val, nextpos, code = Parsers.parsenext(Float64, numberbytes(buf), pos, len)
        (code != Parsers.RC_OK || isfinite(val)) && return nothing
        return NumberResult(val), nextpos
    end
end

@inline function parseboundedexponent(buf, pos, nextpos, limit)
    exponent = 0
    tens, ones = divrem(limit, 10)
    while pos < nextpos
        digit = Int(getbyte(buf, pos) - UInt8('0'))
        if exponent > tens || (exponent == tens && digit > ones)
            return limit
        end
        exponent = exponent * 10 + digit
        pos += 1
    end
    return exponent
end

@inline function exactintegerresult(coefficient::UInt128, isneg, ::Type{T}, nextpos) where {T}
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

# Bounded fallback for tokens whose coefficient does not fit in UInt128. Count
# the decimal scale first, then retain at most the 39 significant digits that
# can contribute to a fixed-width result. This keeps work linear in token size.
function parseexactintegerlong(buf, first, nextpos, ::Type{T}) where {T}
    pos = first
    b = getbyte(buf, pos)
    isneg = b == UInt8('-')
    if isneg || b == UInt8('+')
        pos += 1
    end

    digitcount = 0
    firstnonzero = 0
    fractiondigits = 0
    infraction = false
    while pos < nextpos
        b = getbyte(buf, pos)
        if UInt8('0') <= b <= UInt8('9')
            digitcount += 1
            b != UInt8('0') && firstnonzero == 0 && (firstnonzero = digitcount)
            infraction && (fractiondigits += 1)
        elseif b == UInt8('.')
            infraction = true
        else
            break
        end
        pos += 1
    end

    firstnonzero == 0 && return NumberResult(Int64(0)), nextpos
    significantdigits = digitcount - firstnonzero + 1
    exponent = 0
    if pos < nextpos
        pos += 1 # skip 'e' or 'E'
        b = getbyte(buf, pos)
        expneg = b == UInt8('-')
        if expneg || b == UInt8('+')
            pos += 1
        end
        # Once the scale removes all significant digits, the nonzero value is
        # fractional. Positive exponents at least as large as fractiondigits
        # cannot reduce an oversized coefficient.
        explimit = expneg ? max(significantdigits - fractiondigits, 0) : fractiondigits
        exponent = parseboundedexponent(buf, pos, nextpos, explimit)
        expneg && (exponent = -exponent)
    end

    scale = exponent - fractiondigits
    scale < 0 || throw(InexactError(:parse, T, "out-of-range JSON number"))
    removed = -scale
    removed < significantdigits ||
        throw(InexactError(:parse, T, "non-integral JSON number"))
    significantdigits - removed <= 39 ||
        throw(InexactError(:parse, T, "out-of-range JSON number"))

    cutoff = digitcount - removed
    coefficient = UInt128(0)
    digitindex = 0
    pos = first + (isneg || getbyte(buf, first) == UInt8('+'))
    while pos < nextpos
        b = getbyte(buf, pos)
        if UInt8('0') <= b <= UInt8('9')
            digitindex += 1
            digit = UInt128(b - UInt8('0'))
            if digitindex <= cutoff
                coefficient <= div(typemax(UInt128) - digit, 10) ||
                    throw(InexactError(:parse, T, coefficient))
                coefficient = coefficient * 10 + digit
            elseif !iszero(digit)
                throw(InexactError(:parse, T, coefficient))
            end
        elseif b != UInt8('.')
            break
        end
        pos += 1
    end
    return exactintegerresult(coefficient, isneg, T, nextpos)
end

const UINT128_MAXDIV10 = div(typemax(UInt128), 10)
const UINT128_MAXLAST = rem(typemax(UInt128), 10)

# Convert a validated decimal or exponent token to an exact fixed-width integer.
# UInt128 keeps the common path allocation-free. The fallback for longer
# coefficients also retains only a bounded UInt128 result.
function parseexactinteger(buf, first, nextpos, len, ::Type{T}) where {T}
    pos = first
    b = getbyte(buf, pos)
    isneg = b == UInt8('-')
    if isneg || b == UInt8('+')
        pos += 1
    end

    coefficient = UInt128(0)
    fractiondigits = 0
    # fraction zeros are appended only once a nonzero digit follows them, so trailing
    # zeros (`12.0`, `1.50e1`) need no division by a power of 10 afterwards
    zeros = 0
    infraction = false
    while pos < nextpos
        b = getbyte(buf, pos)
        if UInt8('0') <= b <= UInt8('9')
            if infraction && b == UInt8('0')
                zeros += 1
            else
                for _ = 1:zeros
                    coefficient < UINT128_MAXDIV10 || return parseexactintegerlong(buf, first, nextpos, T)
                    coefficient *= 10
                end
                infraction && (fractiondigits += zeros + 1)
                zeros = 0
                digit = UInt128(b - UInt8('0'))
                # same as `coefficient * 10 + digit <= typemax(UInt128)`, without a 128-bit division
                (coefficient < UINT128_MAXDIV10 || (coefficient == UINT128_MAXDIV10 && digit <= UINT128_MAXLAST)) ||
                    return parseexactintegerlong(buf, first, nextpos, T)
                coefficient = coefficient * 10 + digit
            end
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
        exponent = parseboundedexponent(buf, pos, nextpos, explimit)
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

    return exactintegerresult(coefficient, isneg, T, nextpos)
end

# The digits of a fraction or exponent token times 10^scale, as an exact `BigInt`. The
# exponent may add at most LONGINTEGER digits, so a short token like `1e1000000000`
# can't build an integer far larger than the input.
function parseexactbigint(buf, first, nextpos, len)
    nextpos = exactintegerend(buf, first, nextpos, len)
    digits = UInt8[]
    fractiondigits = 0
    infraction = false
    pos = first
    while pos < nextpos
        b = getbyte(buf, pos)
        (b == UInt8('e') || b == UInt8('E')) && break
        if b == UInt8('.')
            infraction = true
        else
            push!(digits, b)
            infraction && (fractiondigits += 1)
        end
        pos += 1
    end
    ndigits = length(digits) # `String(digits)` takes the vector's bytes, leaving it empty
    coefficient = Base.parse(BigInt, String(digits))
    iszero(coefficient) && return NumberResult(coefficient), nextpos
    exponent = 0
    if pos < nextpos
        pos += 1 # skip 'e' or 'E'
        b = getbyte(buf, pos)
        expneg = b == UInt8('-')
        (expneg || b == UInt8('+')) && (pos += 1)
        if expneg
            # dividing by 10^ndigits or more leaves a nonzero remainder
            exponent = -parseboundedexponent(buf, pos, nextpos, ndigits)
        else
            limit = fractiondigits + LONGINTEGER + 1
            exponent = parseboundedexponent(buf, pos, nextpos, limit)
            exponent == limit && throw(InexactError(:parse, BigInt, "out-of-range JSON number"))
        end
    end
    scale = exponent - fractiondigits
    scale >= 0 && return NumberResult(coefficient * big(10)^scale), nextpos
    quotient, remainder = divrem(coefficient, big(10)^(-scale))
    iszero(remainder) || throw(InexactError(:parse, BigInt, "non-integral JSON number"))
    return NumberResult(quotient), nextpos
end

# `T` is the type requested for this value (`Number` when materializing untyped);
# with `allownan=true`, untyped numbers materialize as `Float64`. A fraction or exponent
# token requested as a fixed-width integer type up to 128 bits, or as a `BigInt`, is
# converted exactly from the token (`1.0e2` is 100; `1.5` throws `InexactError`)
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
    if isfloat && exactint
        # with Parsers 2 the scanner stops inside the fraction, so `nextpos` isn't the end
        if SCANFLOATTAIL && !overflow
            # `12.0`, `-3.00`: a zero fraction and no exponent; `val` is the value
            p = nextpos - 1
            while getbyte(buf, p) == UInt8('0')
                p -= 1
            end
            getbyte(buf, p) == UInt8('.') && return NumberResult(val), nextpos
        end
        return parseexactinteger(buf, startpos, nextpos, len, T)
    elseif isfloat && T === BigInt
        return parseexactbigint(buf, startpos, nextpos, len)
    elseif isfloat || (opts.allownan && !(T <: Integer))
        # in the target's own precision: through Float64, Float32 and Float16 would be
        # rounded twice and BigFloat would lose digits (a Float32 or Float16 is exact as a Float64)
        (T === Float32 || T === Float16 || T === BigFloat) && return parsefloatas(T, buf, startpos, nextpos, len)
        return parsefloat64(buf, startpos, nextpos, len, opts.allownan)
    end
    overflow || return NumberResult(val), nextpos
    # promote to BigInt
    return parsebigint(buf, startpos, nextpos - 1), nextpos
end

# Skipping a number only needs its end. This full conversion is the fallback for
# `allownan` input and for invalid tokens, which it reports.
@noinline skipnumber(x::LazyValues) = parsenumber(x)[2]

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
        getopts(x).allownan && return skipnumber(x)
        buf = getbuf(x)
        pos, _, _, _ = scannumber(buf, getpos(x), getlength(buf))
        return pos == getpos(x) ? skipnumber(x) : pos
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
    push!(f.kvs, String(k) => v)
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

Base.size(x::LazyArray) = size(getfield(x, :positions))

Base.isassigned(x::LazyArray, i::Int) = true

function Base.getindex(x::LazyArray, i::Int)
    opts = getopts(x)
    opts.jsonlines && (opts = lineopts(opts))
    return LazyValue(getbuf(x), getfield(x, :positions)[i], getfield(x, :types)[i], opts, false, getdepth(x) + Int32(1))
end

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
            Base.print(io, "JSON.LazyValue(", repr(String(str)), ")")
        end
    elseif T == JSONTypes.NULL
        Base.print(io, "JSON.LazyValue(nothing)")
    else # bool/number
        Base.print(io, "JSON.LazyValue(", parse(x), ")")
    end
end
