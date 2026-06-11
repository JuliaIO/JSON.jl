# Style architecture redesign: bare styles, config-on-source

Status: draft for discussion (2026-06)
Scope: StructUtils.jl + JSON.jl read path (write path mostly unaffected — it already follows this design)

## 1. The problem, stated once

The recurring bug class (#434 → #458, #454/#462 → #463, #464 → #465, and the cases #465
still misses) is not a series of independent bugs. It is one structural flaw:

> **JSON.parse smuggles per-call *configuration* through the *dispatch identity* (the
> style) by wrapping the user's style in `JSONReadStyle{O,N,S}`. A wrapper type cannot
> transparently impersonate the wrapped value in Julia's multiple dispatch.**

Every fix so far adds forwarding methods (`dictlike(::JSONReadStyle, ::Type{T})` →
`dictlike(st.style, T)`) or conditional unwrapping. Forwarding methods are *specific on
the style axis and generic on the type axis*. User extension methods are encouraged to be
*generic on the style axis and specific on the type axis* (`dictlike(::StructStyle,
::Type{A})`, and `@nonstruct`/`@kwarg` literally generate such methods). Any pair of
methods specialized on opposite axes of the same generic function is ambiguous at their
intersection. This is a property of multiple dispatch, not a missing method. Each fix
relocates the crossing; it cannot remove it.

### Evidence: #465 does not close the hole

Verified against the `pr465` branch (2026-06-11), using the #464 reproducer type `A` with
`dictlike(::StructUtils.StructStyle, ::Type{A}) = true` and a `CustomJSONStyle <:
JSON.JSONStyle`:

| case | call | result on #465 |
|---|---|---|
| 1 | `parse(json, A; style)` | fixed (unwrap condition met) |
| 2 | `parse(json, A; style, null=missing)` | **ambiguous `dictlike` MethodError** |
| 3 | `parse(json, A; style, dicttype=Dict{String,Any})` | **ambiguous** |
| 4 | `parse(json, A; style, unknown_fields=:error)` | **ambiguous** |
| 5 | `parse(json, Outer; style)` where `Outer` has a field `a::A` | **ambiguous** |

Case 5 is the damning one: the unwrap check runs once, at the root, against the *root*
target type. Any dictlike/arraylike type reached through recursion is still seen under the
wrapper. The fix only works when the trait-bearing type happens to be the root target and
all kwargs are default. Worse, #465 makes *whether your methods dispatch at all* depend on
runtime kwarg values — `null=missing` silently changes which methods are considered.
That is strictly harder to debug than a consistent failure.

Conclusion: the wrapper has no fix. It has to go.

## 2. Why the write path doesn't have this disease

`JSON.json` already implements the correct architecture, which is strong evidence it
works in practice:

- **JSON owns the write recursion** (`json!`), so per-call config (`omit_null`,
  `sort_keys`, `pretty`, …) is threaded as a plain `WriteOptions` struct — config never
  enters dispatch.
- **The user's style is passed bare** to every hook: `lower(opts.style, x)`,
  `dictlike(opts.style, x)`, `applyeach(opts.style, f, x)`. There is no write wrapper, no
  forwarding, and there has never been a write-side ambiguity issue.
- JSON's own defaults live on the *abstract supertype* (`lower(::JSONStyle, ::Missing)`,
  `omit_null(::JSONStyle, T)`), so `MyStyle <: JSONStyle` inherits them and can override
  them by normal method specificity. This is the intended use of the style hierarchy.

The read path differs only because `StructUtils.make` owns the recursion and its only
threading channel is the style argument. So configuration got crammed into the style.
Everything else (forwarding, sentinels, heuristics) is fallout.

## 3. The three conflated axes

Today `JSONReadStyle` carries three different things that need three different mechanisms:

| axis | examples | correct mechanism | wrong mechanism (today) |
|---|---|---|---|
| **Identity / customization** | `MyStyle <: JSONStyle <: StructStyle`; which `lift`/`lower`/trait overrides apply | dispatch on the bare style | wrapped inside `JSONReadStyle.style` |
| **Per-call configuration** | `dicttype`, `null`, `unknown_fields` (read); `omit_null`, `sort_keys` (write) | plain data threaded with the recursion | type params + fields of `JSONReadStyle` |
| **Mechanism / source state** | `LazyValue` traversal, byte positions, `PtrString` | dispatch on the *source* type; state stays in plumbing | mixed into style methods (`lift(::JSONReadStyle, T, ::LazyValues)`), tuple-return protocol leaking into user hooks |

The read path already has a perfect channel for axis 2: **`LazyValue.opts`**. Every
sub-`LazyValue` created during traversal inherits `opts` (`applyobject`/`applyarray`
already do this), so anything placed there is available at every recursion point, with
zero dispatch involvement and zero StructUtils API change.

And axis 3 already half-uses the correct mechanism: `applyeach(::StructStyle, f,
x::LazyValues)`, `structlike(::StructStyle, x::LazyValues)`, `make(::StructStyle,
::Type{Any}, x::LazyValues)` are all *generic on style, specific on source* — none of
those have ever caused an ambiguity report, because users don't specialize on someone
else's source type.

## 4. Design rules going forward

These four rules are the whole design. Every extension point either follows them or is a
known, documented residual risk.

- **R1 — Bare styles.** The style argument any user-overloadable hook receives is exactly
  the style instance the user passed to `parse`/`json` (or the package's default
  singleton). No wrapper type ever participates in dispatch.
- **R2 — Config never in the style.** Per-call options ride a non-dispatch channel: the
  source's options for reading (`LazyValue.opts`), `WriteOptions` for writing.
- **R3 — One specialization audience per generic function.**
  - *User hooks* are specialized on **(style × target type)** and receive only
    materialized Julia values: `lift`, `liftkey`, `lower`, `lowerkey`, `dictlike`,
    `arraylike`, `structlike`, `nulllike`, `noarg`, `kwarg`, `initialize`,
    `fieldtags`, `fielddefaults`, `choosetype`.
  - *Format plumbing* is specialized on **source type** with a generic style:
    `applyeach`, value-form traits, and the new `extract` boundary (below). Format
    packages own these; users don't touch them (except power users opting into raw-source
    handling, who specialize on *both* style and source — which is safe).
  - No function accumulates methods on opposite axes.
- **R4 — State is plumbing-only.** Byte positions / iteration state appear only in
  plumbing signatures. User hooks take values and return values — never `(value, state)`
  tuples. (This retires the `_liftresult` "is it a 2-tuple?" heuristic, which today
  misfires if a user's lifted *value* is itself a 2-tuple.)

## 5. The one new mechanism: `StructUtils.extract`

The single point where the make-recursion crosses from "traversing a source" to
"producing a leaf value" is currently `lift(style, T, source, tags)` — which is also the
user hook. That double duty is why JSON had to interpose the wrapper (and the
`_NO_CUSTOM_LAZY_LIFT` sentinel, and `customlazylift`). Split it:

```julia
# NEW in StructUtils (minor release) — the plumbing boundary.
# Called by make's non-aggregate fallback instead of lift directly.
# Format packages overload this for their source types and own the state.
"""
    StructUtils.extract(style, ::Type{T}, source, tags) -> (value, state)

Convert the raw `source` representation into a value of type `T`, calling user-level
hooks (`lift`, `liftkey`) with materialized values as appropriate. Overload this for
*source types you own* (e.g. `JSON.LazyValue`). Do not overload it for target types —
overload `lift` instead.
"""
extract(style::StructStyle, ::Type{T}, source, tags) where {T} =
    _normalizelift(lift(style, T, source, tags), defaultstate(style))
# _normalizelift = JSON's current _liftresult logic, moved here, so bare-value
# returns from user lifts are officially supported everywhere (tuple form deprecated).
```

JSON then moves the body of today's `lift(::JSONReadStyle, ::Type{T}, x::LazyValues,
tags)` driver to:

```julia
function StructUtils.extract(style::StructStyle, ::Type{T}, x::LazyValues, tags) where {T}
    opts = getopts(x)
    # STRING:   parsestring → PtrString fast paths (String/Symbol/Enum/…) internal;
    #           otherwise convert(String, s), then lift(style, T, str, tags)  [bare hook]
    # NUMBER:   parsenumber → lift(style, T, int_or_float, tags)
    # NULL:     lift(style, T, opts.null, tags)
    # TRUE/FALSE: lift(style, T, bool, tags)
    # OBJECT/ARRAY (target not aggregate-traited): materialize default repr
    #           (Object{String,Any}/Vector{Any}), then lift(style, T, materialized, tags)
    # returns (value, pos) — state never touches user code
end
```

Why this kills each piece of machinery:

- **Forwarding methods** (`dictlike`/`arraylike`/`nulllike`/`structlike`/`unknownfield`/
  `defaultstate` on `JSONReadStyle`): deleted. Traits are called with the bare style;
  user methods of *any* breadth (`::StructStyle`, `::JSON.JSONStyle`, `::MyStyle`) fire
  by ordinary specificity. The #464 ambiguity class is structurally impossible — there is
  no JSON method that is style-specific and type-generic on those functions.
- **`_NO_CUSTOM_LAZY_LIFT` + `customlazylift`**: deleted. The question "did the user
  define a custom lazy lift?" disappears — users lift from materialized values
  (`lift(::MyStyle, ::Type{Date}, x::JSON.Object)` just works because `x` *is* an
  `Object` by the time the hook runs). Power users who need raw-lazy access overload
  `extract(::MyStyle, ::Type{Date}, x::JSON.LazyValues, tags)` — specific on both axes,
  no crossing.
- **`_liftresult` heuristic**: moves into StructUtils as official normalization;
  long-term (3.0) the user contract is bare-value returns and the tuple form is
  deprecated.
- **PtrString bridges** (`lift`/`liftkey` on `PtrString`): deleted. `PtrString` never
  reaches dispatchable hooks; the driver converts (or fast-paths) internally. The
  "ensure it never escapes" invariant becomes structural. For dict keys, add a tiny
  single-axis hook so `DictClosure` does `liftkey(style, K, preparekey(k))`:

  ```julia
  StructUtils.preparekey(k) = k                       # StructUtils
  StructUtils.preparekey(k::PtrString) = convert(String, k)  # JSON
  ```

  (source-axis only — same safety argument as `applyeach`). The struct-field path keeps
  raw `PtrString` + `keyeq` for the zero-allocation key comparison.

## 6. Configuration moves onto the source

`LazyOptions` (or a `ReadOptions` superset it nests in) grows:

```julia
@kwdef struct LazyOptions
    # existing: allownan, ninf, inf, nan, jsonlines
    null::Any = nothing                    # read: value used for JSON null
    dicttype::Type = Object{String,Any}    # read: object type under `Any` targets
    ignore_unknown::Bool = true            # read: unknown_fields policy
end
```

- `JSON.parse(buf, T; dicttype, null, unknown_fields, style)` writes these into the
  options when constructing the lazy root (or rebuilds an existing `LazyValue`'s opts —
  an immutable-struct copy, cheap).
- `make(::StructStyle, ::Type{Any}, x::LazyValues)` reads `opts.dicttype`, with an
  `opts.dicttype === Object{String,Any}` fast path so the default stays fully static;
  custom dicttypes pay one dynamic `make` call per `Any`-typed object node (today they
  pay whole-chain respecialization on `JSONReadStyle{O,…}` instead — a wash or better).
- `extract`'s NULL branch reads `opts.null` (Union-split fast path for
  `nothing`/`missing`).
- Unknown-field policy: `unknownfield(::StructStyle, ::Type{T}, key, v::LazyValues)`
  reads `getopts(v).ignore_unknown` and throws or ignores. (Residual risk R3′ below.)
- The untyped fast path (`parse(json)` → `applyvalue`) gates on
  `opts.dicttype === default && opts.null === nothing && style === default`. Note this
  *fixes a latent inconsistency*: today `parse(json; style=MyStyle())` takes the fast
  path and silently ignores the custom style for untyped parses; under this design a
  custom style routes through `make`, so custom lifts apply under `Any` targets too.

Cost/benefit of fields on `LazyOptions`: `LazyValue{T}` keeps its single type parameter
(no specialization explosion — strictly better than `JSONReadStyle{O,N,S}` which
specialized the entire make-chain on the cross product). Two implementation details
proved load-bearing (measured during implementation):

- **`LazyOptions` must be carried by pointer, not inline.** Growing the inline struct
  from 5 to 8 fields slowed *untyped* parses 10–20%, because every sub-`LazyValue`
  created during traversal copies the options payload. Making `LazyOptions` a `mutable
  struct` with `const` fields (heap-allocated once per parse, 8-byte field in
  `LazyValue`) made sub-value creation cheaper than master and turned those benchmarks
  into 5–20% wins, at the cost of one small allocation per `parse` call.
- **The `null::Any` field needs a union-split + typeassert at its use site.** The lazy
  driver's NULL branch splits on `nv === nothing` / `nv === missing` (static dispatch
  for the 99.9% cases) and typeasserts the result of the dynamic fallback arm —
  otherwise the `Any` from the cold arm joins into the driver's return type and boxes
  *every* leaf value (+1 allocation per parsed scalar, measured 1.2–2.4x slowdowns on
  typed paths). Master avoided this only because the wrapper carried `null`'s type as a
  parameter.

## 7. Default style symmetry

- The read default becomes a config-free singleton, symmetric with the write side:

  ```julia
  struct JSONReadStyle <: JSONStyle end   # repurposed: empty, like JSONWriteStyle
  ```

  (Or introduce one `DefaultJSONStyle` used by both and alias
  `const JSONWriteStyle = DefaultJSONStyle` — neither name is `public`.)
- JSON read-side defaults stay on the abstract type, as the write side already does:
  `fieldtagkey(::JSONStyle) = :json`, numeric `liftkey(::JSONStyle, …)` (#465 already
  moved these — that part of the PR is correct and survives).
- **Custom styles should subtype `JSON.JSONStyle`.** The write docs already require this;
  the read docs should match. A plain `StructStyle` still parses, but loses the
  `:json` fieldtag namespace and numeric-key lifting (it no longer inherits them from the
  wrapper, because there is no wrapper). Optionally warn on non-`JSONStyle` styles in
  1.x; narrow the kwarg to `style::JSONStyle` in 2.0.

## 8. The contract table (the "make sense going forward" part)

| function | audience | specialize on | receives | returns |
|---|---|---|---|---|
| `lift`, `liftkey` | type/style authors | (style, target type) | bare style, **materialized** value | value |
| `lower`, `lowerkey` | type/style authors | (style, value type) | bare style, value | value |
| `dictlike/arraylike/structlike/nulllike/noarg/kwarg` (Type-form) | type/style authors | (style, target type) | bare style | `Bool` |
| `initialize`, `addkeyval!` | type/style authors | (style, target type) | bare style | instance / — |
| `fieldtags`, `fielddefaults`, `fieldtagkey` | type/style authors | (style, type) | bare style | NamedTuple/Symbol |
| `choosetype` (3.0: real hook; today `make` overloads via macro) | type/style authors | (style, abstract type) | bare style, source | `Type` |
| `applyeach` | **source/container authors** | source type | style (pass through), f, source | state / `EarlyReturn` |
| value-form traits (`structlike(st, x)` …) | source authors | source value type | — | `Bool` |
| `extract` (new) | source authors (and power users on both axes) | source type | style, target, raw source, tags | `(value, state)` |
| `preparekey` (new) | source authors | source key type | raw key | key |
| `make`/`make!` | **internal driver** (entry points public) | — (don't overload; 3.0 deprecates `@choosetype`-style make overloads) | | `(value, state)` |

Reading the table: a name either belongs to the *left audience* (style × target-type) or
the *right audience* (source type). The whack-a-mole happened because `lift`, the traits,
and `make` each served both audiences at once.

### Residual risks (honest list — what bare styles do *not* solve)

- Two *independent* packages specializing opposite axes of the same hook can still
  collide (inherent to multiple dispatch). JSON minimizes its exposure by keeping its
  supertype methods type-specific (e.g. `arraylike(::JSONStyle, ::AbstractVector{<:Pair})`
  is fine; a hypothetical `arraylike(::JSONStyle, ::Any)` would not be).
- R3′: `unknownfield(::StructStyle, T, key, v::LazyValues)` crosses with a user
  `unknownfield(::MyStyle, T, key, v)` written with untyped `v`. `unknownfield` is new
  and rarely overloaded; document the tie-break (`v::JSON.LazyValues`). If it ever bites,
  promote the policy into `extract`-adjacent plumbing.
- Heuristic lift-normalization can misread a user lift whose *value* is a 2-tuple;
  unchanged from today (#458), retired for good when 3.0 lands the bare-value contract.
- The dictlike duck interface (`initialize`/`addkeyval!`/`keytype`/`valtype`) is implicit
  and underdocumented (easy to hit `valtype` MethodErrors) — docs gap, worth its own pass.

## 9. Migration plan

**Phase 0 — now.** Don't merge #465's conditional unwrap (cases 2–5 above remain broken
and dispatch becomes kwarg-dependent). Keep its two correct re-homings (numeric `liftkey`
and PtrString bridges on `::JSONStyle`) only if an emergency 1.6.x patch is needed;
otherwise fold everything into Phase 1 and make Phase 1 the fix for #464.

**Phase 1 — StructUtils minor (2.9):**
1. Add `extract` (make's leaf fallback calls it; default = current behavior + absorbed
   normalization). Add `preparekey`.
2. Declare `extract` with `Base.Experimental.@max_methods 1`. This is essential, not
   cosmetic: in deeply nested struct targets, Julia's inference recursion limiter widens
   the target type mid-recursion, and abstract `extract` sites then match 2–3 methods
   whose (large) bodies inference explores per context — measured 1065s to compile a
   3-level-nested benchmark struct (vs 17s on master, where the wrapper's type-parameter
   bloat happened to push the same sites past the method-match limit so inference bailed
   cheaply). With `@max_methods 1`, abstract sites bail to `Any` immediately while every
   concrete site (the entire static hot path) has exactly one applicable method and
   infers precisely — net result: nested-struct compile times 2–7x *faster* than master.
3. Document the contract table / two audiences. Document bare-value `lift` returns as the
   preferred form.

**Phase 2 — JSON minor (1.7), the actual #464 fix:**
1. Move `dicttype`/`null`/`unknown_fields` into the lazy options; rebuild opts when
   `parse` is called on an existing `LazyValue`.
2. Pass styles bare; default style = empty `JSONReadStyle()` singleton.
3. Reimplement the lazy driver as `extract(::StructStyle, T, ::LazyValues, tags)`.
4. Delete: `jsonreadstyle`, `JSONReadStyle{O,N,S}` (type params/fields), all forwarding
   methods, `customlazylift`, `_NO_CUSTOM_LAZY_LIFT`, `_liftresult`, PtrString
   lift/liftkey bridges, `objecttype`/`nullvalue` style accessors.
5. Tests: keep every regression from #434/#447/#462/#463/#464; add the **ambiguity
   grid** — for each trait breadth (`::StructStyle`, `::JSONStyle`, `::MyStyle`) × each
   kwarg (`null`, `dicttype`, `unknown_fields`) × root vs nested target × `parse`/`parse!`
   — plus a hook-identity test (`lift` asserting `style === MyStyle()`) and
   `isempty(Test.detect_ambiguities(JSON, StructUtils))`.

Changelog notes for 1.7: `JSONReadStyle` internals changed (it was never `public`; anyone
who followed the MethodError hint to define `dictlike(::JSON.JSONReadStyle, ::Type{A})`
should delete that method — their broad method now just works); custom styles should
subtype `JSON.JSONStyle`; untyped `parse(json; style=…)` now honors the style.

**Phase 3 — StructUtils 3.0 / JSON 2.0 (when convenient, not urgent):**
- `choosetype` becomes a first-class hook; `@choosetype` targets it; direct `make`
  overloads deprecated (still honored through 3.x).
- `lift` user contract: bare value; tuple form removed.
- Wrap plumbing positions in `struct Pos; x::Int; end` to retire the
  "random Int return corrupts parsing" footgun in `applyobject`/`applyarray`.
- Consolidate the duplicated Union/Missing/Nothing peeling between the two `make`
  methods; narrow `parse`'s `style` kwarg to `JSONStyle`.

## 10. Why this is the end of the mole game

The ambiguities all required JSON to own a method that is *specific on the style axis and
generic on the type axis* of a user-extensible function. After Phase 2, JSON owns zero
such methods: trait and lift methods it defines are either on the abstract `JSONStyle`
supertype with *specific* types (normal, user-overridable), or on *its own source types*
with generic styles (invisible to users). Configuration can't reintroduce the problem
because it no longer touches dispatch at all. New features land as either (a) a new
per-call option on the options struct — no dispatch, or (b) a new user hook with a
declared audience per the table — single axis. Both are closed under the rules.
