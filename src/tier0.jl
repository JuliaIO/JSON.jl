# Tier-0 typed parsing for JSON: a single lazy pass drives the StructUtils
# field-table interpreter's slots directly from applyobject — no intermediate
# tree, closures parameterized by style only (never the target type), so the
# whole engine compiles once and ships in this package's image via the
# workload. JIT-only: under StructUtils.TRIM_BUILD the route is compile-time
# disabled and typed parsing goes through the specialized hot descent.
#
# Also here: the :hot precompile hook JSON registers with StructUtils (each
# :hot-annotated struct's typed parse/write compiles into its defining
# package's image), plus the field-table-driven sample synthesizer it uses.

# memoized routing verdict per (target type, style type): the eligibility +
# tree-safety walk is table recursion we don't want on every parse
# copy-on-write: reads are one atomic load + hash lookup (the memo sits on
# every typed parse, including sub-microsecond ones where a lock would
# dominate); writers clone and swap under the lock
mutable struct _RouteMemo
    @atomic table::Dict{Tuple{DataType,DataType},Bool}
end
const _INTERP_ROUTE = _RouteMemo(Dict{Tuple{DataType,DataType},Bool}())
const _INTERP_ROUTE_LOCK = ReentrantLock()

function _interproute(style::StructStyle, @nospecialize(T))::Bool
    T isa DataType || return false
    key = (T, typeof(style))
    tbl = @atomic _INTERP_ROUTE.table
    r = get(tbl, key, nothing)
    r === nothing || return r
    verdict = StructUtils.interpready(style, T) && StructUtils.interptreesafe(style, T)
    lock(_INTERP_ROUTE_LOCK)
    try
        old = @atomic _INTERP_ROUTE.table
        if !haskey(old, key)
            new = copy(old)
            new[key] = verdict
            @atomic _INTERP_ROUTE.table = new
        end
    finally
        unlock(_INTERP_ROUTE_LOCK)
    end
    return verdict
end

# documents above this size take the classic specialized descent instead of
# the tier-0 engine: per-element interpretation loses to a compiled descent
# on bulk documents (measured crossover sits in the low kilobytes), and a
# type that parses bulk documents is worth its one-time compile — the same
# cost every type paid before tier-0 existed. `:hot` skips the size check
# entirely by never reaching this route.
const _FUSED_MAX_BYTES = 4096

const _DEFAULT_READSTYLE = JSONReadStyle{DEFAULT_OBJECT_TYPE,Nothing,StructUtils.DefaultStyle}

# ---------------- fused tier-0 lazy interpretation ----------------
# JIT-only (the route is gated off under trim builds): drives the
# StructUtils field-table interpreter's slots directly from applyobject —
# one pass, no intermediate tree. Closures are parameterized by style only,
# never by the target type, so the whole engine compiles once and lives in
# this package's image via the workload.

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
        # unknown key: honor the style hook (unknown_fields=:error throws);
        # returning non-Int makes applyobject skip the value unmaterialized
        StructUtils.unknownfield(f.style, f.tbl.T, k, v)
        return nothing
    end
    sp = @inbounds specs[i]
    vs = sp.spec
    if gettype(v) == JSONTypes.NULL
        if vs.nullable
            f.slots[i] = nothing
        elseif vs.missingable
            f.slots[i] = missing
        elseif vs.kind == StructUtils.KIND_ANY
            f.slots[i] = nothing
        elseif vs.kind == StructUtils.KIND_CUSTOM
            val, _ = StructUtils.make(f.style, vs.declft::Type, nothing, sp.tags)
            f.slots[i] = val
        else
            x, _ = StructUtils.lift(f.style, vs.ft::Type, nothing)
            f.slots[i] = x
        end
        return getpos(v) + 4
    end
    val, pos = _fused_field(f.style, sp, v)
    f.slots[i] = val
    return pos
end

# field-level: CUSTOM carries the field's tags; everything else goes through
# the spec tree
function _fused_field(style::StructStyle, sp::StructUtils.FieldSpec, v::LazyValue)
    vs = sp.spec
    if vs.kind == StructUtils.KIND_CUSTOM
        out = ValueClosure()
        pos = applyvalue(out, v, nothing)
        val, _ = StructUtils.make(style, vs.declft::Type, out.value, sp.tags)
        return val, pos
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
        if el.nullable
            val, pos = nothing, getpos(v) + 4
        elseif el.missingable
            val, pos = missing, getpos(v) + 4
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
# Kinds the lazy drive doesn't specialize for (dicts, union arms decided by
# source shape, generic customs) materialize the subtree and reuse the
# interpreter's boxed arms — correctness first, still no per-type compile.
function _fused_spec(style::StructStyle, vs::StructUtils.ValueSpec, v::LazyValue, name::String)
    k = vs.kind
    if k == StructUtils.KIND_STRUCT && gettype(v) == JSONTypes.OBJECT
        return _fused_make(style, vs.ft, v)
    elseif k == StructUtils.KIND_VECTOR && gettype(v) == JSONTypes.ARRAY
        el = vs.child::StructUtils.ValueSpec
        arr = StructUtils._alloc_vector(el.declft, 0)
        f = FusedArrClosure{typeof(style)}(style, el, arr, name)
        pos = applyarray(f, v)
        pos isa Int || (pos = skip(v))
        return arr, pos
    elseif k == StructUtils.KIND_UNION2
        arm = gettype(v) == JSONTypes.ARRAY ? (vs.child::StructUtils.ValueSpec) :
                                              (vs.child2::StructUtils.ValueSpec)
        return _fused_spec(style, arm, v, name)
    elseif k == StructUtils.KIND_ANY
        out = ValueClosure()
        pos = applyvalue(out, v, nothing)
        return out.value, pos
    elseif k == StructUtils.KIND_DICT || k == StructUtils.KIND_CUSTOM
        out = ValueClosure()
        pos = applyvalue(out, v, nothing)
        return StructUtils._spec_value(style, vs, out.value, name), pos
    else
        return _fused_scalar(style, k, vs.ft, v, name)
    end
end

# scalar leaves: parse the base JSON scalar lazily, then produce the
# exact-typed value through the interpreter's kind ladder (ISO dates, int
# widths, symbols, chars, and the JIT lift fallback for odd pairings)
function _fused_scalar(style::StructStyle, kind::Int8, @nospecialize(ft), v::LazyValue, name::String)
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
        # aggregate into a scalar-kind field: materialize and let the
        # interpreter's leaf ladder (and its lift fallback) decide
        out = ValueClosure()
        pos = applyvalue(out, v, nothing)
        return StructUtils._liftleaf(style, kind, ft, out.value, name), pos
    end
end

# @noinline: this is the boundary between per-type entry glue and the
# compile-once engine — inlined, the JIT re-infers the engine per target type
@noinline function _fused_make(style::StructStyle, @nospecialize(T), v::LazyValue)
    tbl = StructUtils.fieldtable(T, style)
    if !tbl.eligible
        # nested type the interpreter can't build: materialize the subtree
        # and let the generic machinery decide (classic semantics)
        out = ValueClosure()
        pos = applyvalue(out, v, nothing)
        val, _ = StructUtils.make(style, T::Type, out.value)
        return val, pos
    end
    slots = Vector{Any}(undef, length(tbl.specs))
    f = FusedObjClosure{typeof(style)}(style, tbl, slots)
    pos = applyobject(f, v)
    pos isa Int || (pos = skip(v))
    return StructUtils._construct_interp(style, tbl, slots, v), pos
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
