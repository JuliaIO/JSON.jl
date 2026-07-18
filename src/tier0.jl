# The default typed-parse engine: one pass over the lazy JSON drives the
# StructUtils field-table interpreter directly — no intermediate tree. The
# closures below are parameterized by style only, never by the target type,
# so this whole file compiles once (during JSON's own precompilation, via
# the workload) and a user's first typed parse of any struct costs a table
# build instead of a compile.
#
# It handles every target type: struct objects and element vectors stream
# straight off the lazy tokens; a field whose type has its own lift/make/
# choosetype hooks receives the raw lazy value, so user hooks see exactly
# what they'd see on the per-type path; everything else (dict/tuple/set/
# multidim-array fields, mismatched shapes) reads its subtree into plain
# Julia values and lets the interpreter's generic handlers finish.
#
# Trimmed binaries skip this file's route entirely (its dispatch decisions
# happen at runtime, which a trimmed binary can't compile for) and use the
# per-type path, whose call targets are all static.
#
# Also here: the precompile hook JSON registers with StructUtils — when a
# downstream package defines a `:hot` struct, this hook parses synthesized
# samples during THAT package's precompilation so the type's specialized
# parse/write code lands in its image.

# Only the default read configuration uses the engine. A custom dicttype or
# null changes what values materialize as, and a custom style can carry
# per-style lazy `lift` methods or trait overrides that the engine would
# silently skip (it reads scalars into plain values before lifting, and
# classifies types structurally) — so those all take the per-type path,
# where every user hook is dispatched normally.
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
                i = StructUtils.findspec(specs, convert(String, k))
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
        # an explicit null fills a field that admits both Missing and
        # Nothing with `missing` (matching how make resolves such unions)
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

# structs can also fill from a JSON array: elements map to fields in
# declaration order, and surplus elements go to the style's unknownfield
# hook (ignored by default)
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

# applyarray closure appending each parsed element to the field vector
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
        # null element: Missing arm first, as in the object closure above
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

# position-level recursion mirroring StructUtils.makevalue, driven lazily.
# Struct objects and element vectors — the overwhelmingly common shapes —
# drive the lazy tokens directly; custom kinds hand the RAW lazy value to
# the generic machinery; every other (kind, shape) pairing materializes its
# subtree into plain Julia values and hands them to the interpreter's
# generic handlers — every shape covered, still no per-type compile.
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
            arr = StructUtils.allocvector(el.declft, 0)
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
    # subtree into plain values; the interpreter's generic handlers cover
    # any shape
    out = ValueClosure()
    pos = applyvalue(out, v, nothing)
    return StructUtils.makevalue(style, vs, out.value, name), pos
end

# scalar leaves: parse the base JSON scalar lazily, then produce the
# exact-typed value through the interpreter's per-kind conversions (ISO
# dates, integer widths, symbols, chars, with a generic lift fallback for
# odd pairings)
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
        return StructUtils.liftleaf(style, kind, ft, s, name), pos
    elseif t == JSONTypes.NUMBER
        num, pos = parsenumber(v)
        raw = isint(num) ? num.int :
              isfloat(num) ? num.float :
              isbigint(num) ? num.bigint : num.bigfloat
        return StructUtils.liftleaf(style, kind, ft, raw, name), pos
    elseif t == JSONTypes.TRUE
        return StructUtils.liftleaf(style, kind, ft, true, name), getpos(v) + 4
    elseif t == JSONTypes.FALSE
        return StructUtils.liftleaf(style, kind, ft, false, name), getpos(v) + 5
    else
        # aggregate token into a scalar-kind field: materialize the subtree;
        # the interpreter's generic handlers (lift fallback included) decide
        out = ValueClosure()
        pos = applyvalue(out, v, nothing)
        return StructUtils.makevalue(style, vs, out.value, name), pos
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
    return StructUtils.construct(style, tbl, slots, v), pos
end

# struct-from-array: fill the slot buffer positionally
function _fused_struct_positional(style::StructStyle, tbl::StructUtils.FieldTable, v::LazyValue)
    slots = Vector{Any}(undef, length(tbl.specs))
    f = FusedPosClosure{typeof(style)}(style, tbl, slots)
    pos = applyarray(f, v)
    pos isa Int || (pos = skip(v))
    return StructUtils.construct(style, tbl, slots, v), pos
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
        return StructUtils.makevalue(style, vs, nothing, "root"), getpos(v) + 4
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

# a minimal JSON fragment satisfying one field spec, or nothing to omit it
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
