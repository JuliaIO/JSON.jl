# Tier-0 typed parsing for JSON: a single lazy pass drives the StructUtils
# field-table interpreter's slots directly from applyobject — no intermediate
# tree, closures parameterized by style only (never the target type), so the
# whole engine compiles once and ships in this package's image via the
# workload. Fully capable: every target type routes here under the default
# read configuration — struct objects and element vectors drive the lazy
# tokens directly, custom kinds hand the RAW lazy value to the generic
# machinery (user hooks keep their semantics), and every other (kind, shape)
# pairing materializes its subtree into the interpreter's boxed arms.
# JIT-only: under StructUtils.TRIM_BUILD typed parsing goes through the
# specialized hot descent (the trim verifier needs its static call graph).
#
# Also here: the :hot precompile hook JSON registers with StructUtils (each
# :hot-annotated struct's typed parse/write compiles into its defining
# package's image), plus the field-table-driven sample synthesizer it uses.

# the tier-0 route: the default read configuration only. Custom dicttype/
# null change materialization semantics, and custom inner styles can carry
# per-style `lift(::MyStyle, ::Type{T}, ::LazyValue)` overloads or trait
# overrides (dictlike/arraylike) that the engine's materializing scalar
# ladder and structural spec tree would silently bypass — those take the
# fully-specialized descent, where every hook sees exactly what classic
# handed it.
const _FUSED_STYLE = JSONReadStyle{DEFAULT_OBJECT_TYPE,Nothing,StructUtils.DefaultStyle}

# ---------------- fused tier-0 lazy interpretation ----------------

struct FusedObjClosure{S<:StructStyle}
    style::S
    tbl::StructUtils.FieldTable
    slots::Vector{Any}
end

function (f::FusedObjClosure{S})(k::PtrString, v::LazyValue) where {S}
    specs = f.tbl.specs
    i = 0
    for j = 1:length(specs)
        if k == @inbounds(specs[j]).name # PtrString == String: no allocation
            i = j
            break
        end
    end
    if i == 0
        # miss on declared names: alias tuples and raw name tags register
        # extra candidates (only consulted when the table declares any)
        for j = 1:length(specs)
            if @inbounds(specs[j]).aliases !== nothing
                i = StructUtils._findspec(specs, convert(String, k))
                break
            end
        end
    end
    if i == 0
        # unknown key: honor the style hook (unknown_fields=:error throws);
        # returning non-Int makes applyobject skip the value unmaterialized
        StructUtils.unknownfield(f.style, f.tbl.T, k, v)
        return nothing
    end
    return _fused_fillslot!(f.style, f.slots, i, @inbounds(specs[i]), v)
end

# fill slot i for a matched spec (by key or position); returns the next
# lazy position (or nothing to let the applier skip unmaterialized)
function _fused_fillslot!(style::StructStyle, slots::Vector{Any}, i::Int,
                          sp::StructUtils.FieldSpec, v::LazyValue)
    vs = sp.spec
    if gettype(v) == JSONTypes.NULL
        # classic @_peel order: when a field admits both, an explicit null
        # takes the Missing arm first
        if vs.missingable
            slots[i] = missing
        elseif vs.nullable
            slots[i] = nothing
        elseif vs.kind == StructUtils.KIND_ANY
            slots[i] = nothing
        elseif vs.kind == StructUtils.KIND_CUSTOM
            val, _ = StructUtils.make(style, vs.declft::Type, nothing, sp.tags)
            slots[i] = val
        else
            x, _ = StructUtils.lift(style, vs.ft::Type, nothing)
            slots[i] = x
        end
        return getpos(v) + 4
    end
    val, pos = _fused_field(style, sp, v)
    slots[i] = val
    return pos
end

# positional struct fill from a JSON array source: classic's lazy applyeach
# handed the struct closures Int keys for arrays, so field order is the
# match (surplus elements go to the style's unknownfield hook)
struct FusedPosClosure{S<:StructStyle}
    style::S
    tbl::StructUtils.FieldTable
    slots::Vector{Any}
end

function (f::FusedPosClosure{S})(i::Int, v::LazyValue) where {S}
    specs = f.tbl.specs
    if i > length(specs)
        StructUtils.unknownfield(f.style, f.tbl.T, i, v)
        return nothing
    end
    return _fused_fillslot!(f.style, f.slots, i, @inbounds(specs[i]), v)
end

# field-level: CUSTOM carries the field's tags; everything else goes through
# the spec tree
function _fused_field(style::StructStyle, sp::StructUtils.FieldSpec, v::LazyValue)
    vs = sp.spec
    if vs.kind == StructUtils.KIND_CUSTOM
        # custom-kind fields (user lift/make targets, choosetype tags,
        # abstract declared types) receive the RAW lazy value — user hooks
        # see exactly what the specialized descent hands them
        val, st = StructUtils.make(style, vs.declft::Type, v, sp.tags)
        return val, st isa Int ? st : skip(v)
    end
    return _fused_spec(style, vs, v, sp.name)
end

struct FusedArrClosure{S<:StructStyle}
    style::S
    el::StructUtils.ValueSpec
    arr::Any
    name::String
end

function (f::FusedArrClosure{S})(_, v::LazyValue) where {S}
    el = f.el
    local val, pos
    if gettype(v) == JSONTypes.NULL
        # classic @_peel order: Missing arm first
        if el.missingable
            val, pos = missing, getpos(v) + 4
        elseif el.nullable
            val, pos = nothing, getpos(v) + 4
        else
            x, _ = StructUtils.lift(f.style, el.ft::Type, nothing)
            val, pos = x, getpos(v) + 4
        end
    else
        val, pos = _fused_spec(f.style, el, v, f.name)
    end
    push!(f.arr::Vector, val)
    return pos
end

# position-level recursion mirroring StructUtils._spec_value, driven lazily.
# Struct objects and element vectors — the overwhelmingly common shapes —
# drive the lazy tokens directly; custom kinds hand the RAW lazy value to
# the generic machinery; every other (kind, shape) pairing materializes its
# subtree and reuses the interpreter's boxed arms — full capability, still
# no per-type compile.
function _fused_spec(style::StructStyle, vs::StructUtils.ValueSpec, v::LazyValue, name::String)
    k = vs.kind
    if k == StructUtils.KIND_STRUCT
        t = gettype(v)
        if t == JSONTypes.OBJECT || t == JSONTypes.ARRAY
            tbl = StructUtils.fieldtable(vs.ft::DataType, style)
            if tbl.eligible
                t == JSONTypes.OBJECT && return _fused_struct(style, tbl, v)
                return _fused_struct_positional(style, tbl, v)
            end
        end
    elseif k == StructUtils.KIND_VECTOR
        if gettype(v) == JSONTypes.ARRAY
            el = vs.child::StructUtils.ValueSpec
            arr = StructUtils._alloc_vector(el.declft, 0)
            f = FusedArrClosure{typeof(style)}(style, el, arr, name)
            pos = applyarray(f, v)
            pos isa Int || (pos = skip(v))
            return arr, pos
        end
    elseif k == StructUtils.KIND_UNION2
        arm = gettype(v) == JSONTypes.ARRAY ? (vs.child::StructUtils.ValueSpec) :
                                              (vs.child2::StructUtils.ValueSpec)
        return _fused_spec(style, arm, v, name)
    elseif k == StructUtils.KIND_ANY
        out = ValueClosure()
        pos = applyvalue(out, v, nothing)
        return out.value, pos
    elseif k == StructUtils.KIND_CUSTOM
        # raw lazy value to the generic machinery — user lift/make/choosetype
        # hooks see exactly what the specialized descent hands them
        val, st = StructUtils.make(style, vs.declft::Type, v)
        return val, st isa Int ? st : skip(v)
    elseif !(k == StructUtils.KIND_DICT || k == StructUtils.KIND_TUPLE ||
             k == StructUtils.KIND_FIXEDARRAY || k == StructUtils.KIND_SETLIKE ||
             k == StructUtils.KIND_UNSUPPORTED)
        # scalar leaf kinds parse straight off the lazy token
        return _fused_scalar(style, vs, v, name)
    end
    # dict/tuple/set/fixed-array kinds, unsupported leaves, and shape
    # mismatches (struct-from-array, vector-from-object): materialize the
    # subtree; the interpreter's boxed arms handle any shape
    out = ValueClosure()
    pos = applyvalue(out, v, nothing)
    return StructUtils._spec_value(style, vs, out.value, name), pos
end

# scalar leaves: parse the base JSON scalar lazily, then produce the
# exact-typed value through the interpreter's kind ladder (ISO dates, int
# widths, symbols, chars, and the JIT lift fallback for odd pairings)
function _fused_scalar(style::StructStyle, vs::StructUtils.ValueSpec, v::LazyValue, name::String)
    kind = vs.kind
    ft = vs.ft
    t = gettype(v)
    if t == JSONTypes.STRING
        buf = getbuf(v)
        local s, pos
        GC.@preserve buf begin
            str, pos = parsestring(v)
            s = convert(String, str)
        end
        return StructUtils._liftleaf(style, kind, ft, s, name), pos
    elseif t == JSONTypes.NUMBER
        num, pos = parsenumber(v)
        raw = isint(num) ? num.int :
              isfloat(num) ? num.float :
              isbigint(num) ? num.bigint : num.bigfloat
        return StructUtils._liftleaf(style, kind, ft, raw, name), pos
    elseif t == JSONTypes.TRUE
        return StructUtils._liftleaf(style, kind, ft, true, name), getpos(v) + 4
    elseif t == JSONTypes.FALSE
        return StructUtils._liftleaf(style, kind, ft, false, name), getpos(v) + 5
    else
        # aggregate token into a scalar-kind field: materialize the subtree;
        # the interpreter's boxed arms (lift fallback included) decide
        out = ValueClosure()
        pos = applyvalue(out, v, nothing)
        return StructUtils._spec_value(style, vs, out.value, name), pos
    end
end

# the object↔struct fast path: one lazy pass drives the field-table slots.
# @noinline: the boundary between per-type entry glue and the compile-once
# engine — inlined, the JIT re-infers the engine per target type
@noinline function _fused_struct(style::StructStyle, tbl::StructUtils.FieldTable, v::LazyValue)
    slots = Vector{Any}(undef, length(tbl.specs))
    f = FusedObjClosure{typeof(style)}(style, tbl, slots)
    pos = applyobject(f, v)
    pos isa Int || (pos = skip(v))
    return StructUtils._construct_interp(style, tbl, slots, v), pos
end

function _fused_struct_positional(style::StructStyle, tbl::StructUtils.FieldTable, v::LazyValue)
    slots = Vector{Any}(undef, length(tbl.specs))
    f = FusedPosClosure{typeof(style)}(style, tbl, slots)
    pos = applyarray(f, v)
    pos isa Int || (pos = skip(v))
    return StructUtils._construct_interp(style, tbl, slots, v), pos
end

# root entry for ANY target type: the spec tree describes T (built once per
# (target, style type)); custom/unsupported roots hand the raw lazy value to
# the generic machinery — the never-error backstop
@noinline function _fused_make(style::StructStyle, @nospecialize(T), v::LazyValue)
    vs = StructUtils.rootspec(T, style)
    if vs.kind == StructUtils.KIND_CUSTOM || vs.kind == StructUtils.KIND_UNSUPPORTED ||
       vs.kind == StructUtils.KIND_FIXEDARRAY
        # custom/unsupported shapes and fixed-size arrays (0-dim included:
        # dimension discovery needs the raw lazy value) take the generic route
        val, st = StructUtils.make(style, T::Type, v)
        return val, st isa Int ? st : skip(v)
    end
    if gettype(v) == JSONTypes.NULL
        return StructUtils._spec_nullwrap(style, vs, nothing, "root"), getpos(v) + 4
    end
    return _fused_spec(style, vs, v, "root")
end

# ---------------- :hot precompile hook + sample synthesis ----------------

# registered with StructUtils from __init__: called for each :hot-annotated
# struct during the *defining package's* precompilation, inside a newly-
# inferred-tagging block — everything parsed here (the typed lazy descent,
# the write path) lands in that package's image
function _hot_json_hook(@nospecialize(T), samples::Tuple)
    T isa Type || return nothing
    for s in samples
        s isa AbstractString || continue
        try
            x = parse(String(s), T)
            json(x)
        catch
        end
    end
    s = try
        _synthesize_sample(T)
    catch
        nothing
    end
    if s !== nothing
        try
            x = parse(s, T)
            json(x)
        catch
        end
    end
    try
        parse("{}", T)
    catch
    end
    return nothing
end

# build a minimal valid JSON sample for T from its field table: dummy leaf
# per kind, recursion for nested structs/vectors; CUSTOM-kind fields are
# omitted (defaults/nullability cover them, and "{}" is the fallback)
function _synthesize_sample(@nospecialize(T))
    style = JSONReadStyle{DEFAULT_OBJECT_TYPE}(nothing)
    tbl = StructUtils.fieldtable(T, style)
    tbl.eligible || return nothing
    io = IOBuffer()
    Base.print(io, '{')
    isfirst = true
    for sp in tbl.specs
        frag = _synth_value(sp.spec)
        frag === nothing && continue
        isfirst || Base.print(io, ',')
        isfirst = false
        Base.print(io, '"', sp.name, "\":", frag)
    end
    Base.print(io, '}')
    return String(take!(io))
end

function _synth_value(vs::StructUtils.ValueSpec)
    SU = StructUtils
    kind = vs.kind
    if kind == SU.KIND_STRING || kind == SU.KIND_SYMBOL
        return "\"s\""
    elseif kind == SU.KIND_CHAR
        return "\"c\""
    elseif SU.KIND_INT64 <= kind <= SU.KIND_UINT128
        return "1"
    elseif SU.KIND_FLOAT64 <= kind <= SU.KIND_FLOAT16
        return "1.5"
    elseif kind == SU.KIND_BOOL
        return "true"
    elseif kind == SU.KIND_DATE
        return "\"2020-01-02\""
    elseif kind == SU.KIND_DATETIME
        return "\"2020-01-02T03:04:05\""
    elseif kind == SU.KIND_TIME
        return "\"03:04:05\""
    elseif kind == SU.KIND_UUID
        return "\"c8b1cf79-de6a-54ab-a142-682c06a0de6a\""
    elseif kind == SU.KIND_ANY
        return "1"
    elseif kind == SU.KIND_STRUCT
        return _synthesize_sample(vs.ft)
    elseif kind == SU.KIND_VECTOR
        el = _synth_value(vs.child::StructUtils.ValueSpec)
        return el === nothing ? nothing : string('[', el, ']')
    elseif kind == SU.KIND_DICT
        el = _synth_value(vs.child::StructUtils.ValueSpec)
        return el === nothing ? nothing : string("{\"k\":", el, '}')
    elseif kind == SU.KIND_UNION2
        return _synth_value(vs.child2::StructUtils.ValueSpec) # the scalar arm
    end
    return nothing
end
