struct NotSet end
const notset = NotSet()

# empty Object: key, value, child all notset
# root Object: key, value are notset, child is defined
# non-root Object: key, value are set, child is notset for last node
"""
    JSON.Object{K,V}

A mutable `AbstractDict` type for JSON objects. Internally is a linked list of key-value pairs, where each pair is represented by an `Object` instance. The first instance is the root object.
The `Object` type is used to represent JSON objects in a mutable way, allowing for efficient insertion and deletion of key-value pairs. It is designed to be used with the `JSON` package for parsing and deserializing JSON data.

Because of the linked-list representation, key lookups are O(n), using a simple linear scan.
For small objects, this is very efficient, and worth the memory overhead vs. a full `Dict` or `OrderedDict`.
For Objects with many entries (hundreds or thousands), this is not as efficient. In that case, consider using a `Dict` or `OrderedDict` instead.

Typed constructors convert keys and values to `K` and `V`. Pair and iterator constructors
preserve input order and may contain repeated keys. `setindex!(obj, value, key)` returns
`obj`, while `delete!(obj, key)` removes all matching entries and returns `obj`.

`pop!(obj, key)` removes the first matching entry and returns its value, or throws `KeyError` when the key is absent.
`pop!(obj, key, default)` returns `default` for an absent key. Without a key, `pop!(obj)`
removes the last inserted pair, while `popfirst!(obj)` removes the first pair. Both throw
`ArgumentError` for an empty object. Removing a pair preserves the order of the remaining pairs.
"""
mutable struct Object{K,V} <: AbstractDict{K,V}
    key::Union{NotSet, K} # for root object, key/value are notset
    value::Union{NotSet, V}
    child::Union{NotSet, Object{K,V}} # possibly notset

    # root constructor: key is const notset
    function Object{K,V}() where {K,V}
        x = new{K,V}(notset, notset, notset)
        return x
    end

    # all non-root Objects *must* be set as the child of another Object
    # WARNING: this constructor can allow duplicate `k` in a root Object as no check is done
    function Object{K,V}(obj::Object{K,V}, k, v) where {K,V}
        @assert _ch(obj) === notset "Object child already defined"
        nobj = new{K,V}(convert(K, k), convert(V, v), notset)
        setfield!(obj, :child, nobj)
        return nobj
    end
end

Object() = Object{Any, Any}() # default empty object

_k(obj::Object) = getfield(obj, :key)
_v(obj::Object) = getfield(obj, :value)
_ch(obj::Object) = getfield(obj, :child)

Object(d::AbstractDict{K,V}) where {K,V} = Object{K,V}(d)

function Object{K,V}(d::AbstractDict{K,V}) where {K,V}
    root = obj = Object{K,V}()
    for (k, v) in d
        obj = Object{K,V}(obj, k, v)
    end
    return root
end

Object(pairs::Pair{K,V}...) where {K,V} = Object{K,V}(pairs...)
Object(pairs::Pair...) = Object{Any,Any}(pairs...)

function Object{K,V}(pairs::Pair...) where {K,V}
    root = obj = Object{K,V}()
    for (k, v) in pairs
        obj = Object{K,V}(obj, k, v)
    end
    return root
end

# generic iterator constructors
function Object(itr)
    root = obj = nothing
    st = iterate(itr)
    while st !== nothing
        kv, state = st
        if kv isa Pair || kv isa Tuple{Any,Any}
            k, v = kv
            if root === nothing
                root = Object{typeof(k), typeof(v)}()
                obj = root
            end
            obj = Object{typeof(k), typeof(v)}(obj, k, v)
        else
            throw(ArgumentError("Iterator must yield Pair or 2-tuple, got $(typeof(kv))"))
        end
        st = iterate(itr, state)
    end
    return root === nothing ? Object{Any,Any}() : root
end

function Object{K,V}(itr) where {K,V}
    root = obj = Object{K,V}()
    st = iterate(itr)
    while st !== nothing
        kv, state = st
        if kv isa Pair || kv isa Tuple{Any,Any}
            k, v = kv
            obj = Object{K, V}(obj, k, v)
        else
            throw(ArgumentError("Iterator must yield Pair or 2-tuple, got $(typeof(kv))"))
        end
        st = iterate(itr, state)
    end
    return root
end

function Base.iterate(orig::Object{K,V}, obj=orig) where {K,V}
    obj === nothing && return nothing
    if _k(obj) === notset
        # if key is notset, we either have to iterate from the child or we're done
        return _ch(obj) === notset ? nothing : iterate(_ch(obj)::Object{K,V})
    end
    return (Pair{K,V}(_k(obj)::K, _v(obj)::V), _ch(obj) === notset ? nothing : _ch(obj)::Object{K,V})
end

function Base.length(obj::Object{K,V}) where {K,V}
    count = 0
    while true
        _k(obj) !== notset && (count += 1)
        _ch(obj) === notset && break
        obj = _ch(obj)::Object{K,V}
    end
    return count
end
Base.isempty(obj::Object) = _k(obj) === notset && _ch(obj) === notset
Base.empty(::Object{K,V}) where {K,V} = Object{K,V}() # empty object

# copies the entries in a loop: Base's generic method recurses once per entry
function Base.deepcopy_internal(x::Object{K,V}, stackdict::IdDict) where {K,V}
    haskey(stackdict, x) && return stackdict[x]::Object{K,V}
    root = obj = Object{K,V}()
    stackdict[x] = root
    for (k, v) in x
        obj = Object{K,V}(obj, deepcopyfield(k, stackdict), deepcopyfield(v, stackdict))
    end
    return root
end
deepcopyfield(x, stackdict) = isbits(x) ? x : Base.deepcopy_internal(x, stackdict)

# linear node lookup
@inline function find_node_by_key(obj::Object{K,V}, key) where {K,V}
    while true
        _k(obj) !== notset && isequal(_k(obj)::K, key) && return obj
        _ch(obj) === notset && break
        obj = _ch(obj)::Object{K,V}
    end
    return nothing
end

# get with fallback callable
function Base.get(f::Base.Callable, obj::Object{K,V}, key) where {K,V}
    node = find_node_by_key(obj, key)
    node !== nothing && return _v(node)::V
    return f()
end
Base.get(f::Base.Callable, obj::Object{String}, key::Symbol) = get(f, obj, String(key))
Base.get(f::Base.Callable, obj::Object{Symbol}, key::String) = get(f, obj, Symbol(key))

Base.getindex(obj::Object, key) = get(() -> throw(KeyError(key)), obj, key)
Base.getindex(obj::Object{String}, key::Symbol) = get(() -> throw(KeyError(key)), obj, String(key))
Base.getindex(obj::Object{Symbol}, key::String) = get(() -> throw(KeyError(key)), obj, Symbol(key))
Base.setindex!(obj::Object{String,V}, value, key::AbstractString) where {V} = _setindex!(obj, value, String(key))
Base.setindex!(obj::Object{String,V}, value, key::Symbol) where {V} = _setindex!(obj, value, String(key))
Base.setindex!(obj::Object{Symbol}, value, key::String) = setindex!(obj, value, Symbol(key))
Base.delete!(obj::Object{String,V}, key::AbstractString) where {V} = _delete!(obj, String(key))
Base.delete!(obj::Object{String,V}, key::Symbol) where {V} = _delete!(obj, String(key))
Base.delete!(obj::Object{Symbol}, key::String) = delete!(obj, Symbol(key))
Base.get(obj::Object, key, default) = get(() -> default, obj, key)
Base.get(obj::Object{String}, key::Symbol, default) = get(obj, String(key), default)
Base.get(obj::Object{Symbol}, key::String, default) = get(obj, Symbol(key), default)

# support getproperty for dot access
Base.getproperty(obj::Object{Symbol}, sym::Symbol) = getindex(obj, sym)
Base.getproperty(obj::Object{String}, sym::Symbol) = getindex(obj, String(sym))
Base.propertynames(obj::Object) = Tuple(Symbol(key) for key in keys(obj))

# haskey
Base.haskey(obj::Object, key) = find_node_by_key(obj, key) !== nothing
Base.haskey(obj::Object{String}, key::Symbol) = haskey(obj, String(key))
Base.haskey(obj::Object{Symbol}, key::String) = haskey(obj, Symbol(key))

# setindex! finds node with key and sets value or inserts a new node
function _setindex!(obj::Object{K,V}, value, key::K) where {K,V}
    root = obj
    while true
        if _k(obj) !== notset && isequal(_k(obj)::K, key)
            setfield!(obj, :value, convert(V, value))
            return root
        end
        _ch(obj) === notset && break
        obj = _ch(obj)::Object{K,V}
    end
    # if we reach here, we need to insert a new node
    Object{K,V}(obj, key, value)
    return root
end
Base.setindex!(obj::Object{K,V}, value, key::K) where {K,V} = _setindex!(obj, value, key)

# delete! removes node
function _delete!(obj::Object{K,V}, key::K) where {K,V}
    # check empty case
    _ch(obj) === notset && return obj
    root = parent = obj
    obj = _ch(obj)::Object{K,V}
    while true
        if _k(obj) !== notset && isequal(_k(obj)::K, key)
            # we found the node to remove
            # if node is leaf, we need to set parent as leaf
            # otherwise, we set child as child of parent
            if _ch(obj) === notset
                setfield!(parent, :child, notset)
            else
                setfield!(parent, :child, _ch(obj)::Object{K,V})
            end
        else
            parent = obj
        end
        _ch(obj) === notset && break
        obj = _ch(obj)::Object{K,V}
    end
    return root
end
Base.delete!(obj::Object{K,V}, key::K) where {K,V} = _delete!(obj, key)

function _pop!(f::Base.Callable, obj::Object{K,V}, key) where {K,V}
    parent = obj
    node = _ch(obj)
    while node !== notset
        node = node::Object{K,V}
        if isequal(_k(node)::K, key)
            setfield!(parent, :child, _ch(node))
            return _v(node)::V
        end
        parent = node
        node = _ch(node)
    end
    return f()
end

Base.pop!(obj::Object, key) = _pop!(() -> throw(KeyError(key)), obj, key)
Base.pop!(obj::Object, key, default) = _pop!(() -> default, obj, key)
Base.pop!(obj::Object{String}, key::Symbol) = pop!(obj, String(key))
Base.pop!(obj::Object{String}, key::Symbol, default) = pop!(obj, String(key), default)
Base.pop!(obj::Object{Symbol}, key::String) = pop!(obj, Symbol(key))
Base.pop!(obj::Object{Symbol}, key::String, default) = pop!(obj, Symbol(key), default)

function Base.pop!(obj::Object{K,V}) where {K,V}
    _ch(obj) === notset && throw(ArgumentError("Object must be non-empty"))
    parent = obj
    node = _ch(obj)::Object{K,V}
    while _ch(node) !== notset
        parent = node
        node = _ch(node)::Object{K,V}
    end
    setfield!(parent, :child, notset)
    return Pair{K,V}(_k(node)::K, _v(node)::V)
end

function Base.popfirst!(obj::Object{K,V}) where {K,V}
    _ch(obj) === notset && throw(ArgumentError("Object must be non-empty"))
    node = _ch(obj)::Object{K,V}
    setfield!(obj, :child, _ch(node))
    return Pair{K,V}(_k(node)::K, _v(node)::V)
end

function Base.empty!(obj::Object)
    setfield!(obj, :child, notset)
    return obj
end

# support setproperty for dot access
Base.setproperty!(obj::Object, sym::Symbol, val) = setindex!(obj, val, sym)
Base.setproperty!(obj::Object{String}, sym::Symbol, val) = setindex!(obj, val, String(sym))

Base.merge(a::NamedTuple, b::Object{String,Any}) = merge(a, (Symbol(k) => v for (k, v) in b))

# Whole-object operations on more than `SCAN_LIMIT` entries look keys up in a table of
# each key's first node instead of scanning the list once per key. A repeated key updates
# its first entry, as `setindex!` does.
const SCAN_LIMIT = 16

# the key `setindex!(obj, value, key)` stores
storedkey(::Object{K}, key::K) where {K} = key
storedkey(::Object{String}, key::Union{AbstractString,Symbol}) = String(key)
storedkey(::Object{Symbol}, key::String) = Symbol(key)

# each key's first node in an object, and the object's last node
mutable struct NodeIndex{K,V}
    nodes::Dict{K,Object{K,V}}
    leaf::Object{K,V}
end

# the index of `d`, with its table sized for `n` keys
function NodeIndex(d::Object{K,V}, n::Int) where {K,V}
    leaf = d
    while _ch(leaf) !== notset
        leaf = _ch(leaf)::Object{K,V}
    end
    return NodeIndex(nodetable(d, n), leaf)
end

# where `mergepair!` adds to `d`: `d` itself for `n` entries or fewer, else its index
mergedest(d::Object, n::Int) = n <= SCAN_LIMIT ? d : NodeIndex(d, n)

# adds `key => v` as `setindex!` (`combine === nothing`) or `mergewith!` does; inlined, as
# a call that passes an `Any` value and calls `combine` is otherwise dispatched at run time
@inline function mergepair!(combine, d::Object{K,V}, key::K, v) where {K,V}
    node = d # one scan, as in `_setindex!`
    while true
        if _k(node) !== notset && isequal(_k(node)::K, key)
            setfield!(node, :value, convert(V, combine === nothing ? v : combine(_v(node)::V, v)))
            return
        end
        _ch(node) === notset && break
        node = _ch(node)::Object{K,V}
    end
    Object{K,V}(node, key, v)
    return
end

@inline function mergepair!(combine, ix::NodeIndex{K,V}, key, v) where {K,V}
    node = get(ix.nodes, key, nothing)
    if node === nothing
        ix.nodes[key] = ix.leaf = Object{K,V}(ix.leaf, key, v)
    else
        setfield!(node, :value, convert(V, combine === nothing ? v : combine(_v(node)::V, v)))
    end
    return
end

# `F` makes Julia specialize on `combine`, which is passed on rather than called here
function mergeinto!(combine::F, d::Object, dest, other) where {F}
    for (k, v) in other
        mergepair!(combine, dest, storedkey(d, k), v)
    end
end

# also used by Base's `copy` and `copy!`; `N` makes Julia specialize on the number of dicts
function Base.merge!(d::Object, others::Vararg{AbstractDict,N}) where {N}
    dest = mergedest(d, length(d) + sum(length, others; init=0))
    for other in others
        mergeinto!(nothing, d, dest, other)
    end
    return d
end

Base.mergewith!(combine::F, d::Object, other::AbstractDict) where {F} =
    (mergeinto!(combine, d, mergedest(d, length(d) + length(other)), other); d)

function Base.filter(f, d::Object)
    df = empty(d)
    dest = df
    n = 0
    for p in d
        f(p) || continue
        (n += 1) == SCAN_LIMIT + 1 && (dest = NodeIndex(df, length(d)))
        mergepair!(nothing, dest, p.first, p.second)
    end
    return df
end

# Base's `AbstractDict` `==`/`isequal`: each pair of `l` is looked up in `r` (its first
# entry for a repeated key), in a table instead of a scan of `r` for larger objects.
Base.:(==)(l::Object{K}, r::Object{K}) where {K} = objectequal(==, l, r)
Base.isequal(l::Object{K}, r::Object{K}) where {K} = l === r || objectequal(isequal, l, r)

function objectequal(valcmp, l::Object{K}, r::Object{K,V}) where {K,V}
    n = length(l)
    n == length(r) || return false
    nodes = n <= SCAN_LIMIT ? nothing : nodetable(r, n)
    anymissing = false
    for (k, v) in l
        node = nodes === nothing ? find_node_by_key(r, k) : get(nodes, k, nothing)
        node === nothing && return false
        eq = valcmp(_v(node)::V, v)
        if ismissing(eq)
            anymissing = true
        elseif !eq
            return false
        end
    end
    return anymissing ? missing : true
end
