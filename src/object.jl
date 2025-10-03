struct NotSet end
const notset = NotSet()

"""
    JSON.Object{K,V}

A mutable `AbstractDict` type for JSON objects. Internally is a linked list of key-value pairs, where each pair is represented by an `Object` instance. The first instance is the root object.
The `Object` type is used to represent JSON objects in a mutable way, allowing for efficient insertion and deletion of key-value pairs. It is designed to be used with the `JSON` package for parsing and deserializing JSON data.

Because of the linked-list representation, key lookups are O(n), using a simple linear scan.
For small objects, this is very efficient, and worth the memory overhead vs. a full `Dict` or `OrderedDict`.
For Objects with many entries (hundreds or thousands), this is not as efficient. In that case, consider using a `Dict` or `OrderedDict` instead.
"""
# empty Object: key, value, child all notset
# root Object: key, value are notset, child is defined
# non-root Object: key, value are set, child is notset for last node
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
        nobj = new{K,V}(k, v, notset)
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

# linear node lookup
@inline function find_node_by_key(obj::Object{K,V}, key::K) where {K,V}
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

Base.getindex(obj::Object, key) = get(() -> throw(KeyError(key)), obj, key)
Base.get(obj::Object, key, default) = get(() -> default, obj, key)

# support getproperty for dot access
Base.getproperty(obj::Object{Symbol}, sym::Symbol) = getindex(obj, sym)
Base.getproperty(obj::Object{String}, sym::Symbol) = getindex(obj, String(sym))
Base.propertynames(obj::Object{K,V}) where {K,V} = _k(obj) === notset && _ch(obj) === notset ? () : _propertynames(_ch(obj)::Object{K,V}, ())

function _propertynames(obj::Object{K,V}, acc) where {K,V}
    new = (acc..., Symbol(_k(obj)::K))
    return _ch(obj) === notset ? new : _propertynames(_ch(obj)::Object{K,V}, new)
end

# haskey
Base.haskey(obj::Object, key) = find_node_by_key(obj, key) !== nothing
Base.haskey(obj::Object{String}, key::Symbol) = haskey(obj, String(key))

# setindex! finds node with key and sets value or inserts a new node
function Base.setindex!(obj::Object{K,V}, value, key::K) where {K,V}
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
    return value
end

# delete! removes node
function Base.delete!(obj::Object{K,V}, key::K) where {K,V}
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
        end
        _ch(obj) === notset && break
        parent = obj
        obj = _ch(obj)::Object{K,V}
    end
    return root
end

function Base.empty!(obj::Object)
    setfield!(obj, :child, notset)
    return obj
end

# support setproperty for dot access
Base.setproperty!(obj::Object, sym::Symbol, val) = setindex!(obj, val, sym)
Base.setproperty!(obj::Object{String}, sym::Symbol, val) = setindex!(obj, val, String(sym))

Base.merge(a::NamedTuple, b::Object{String,Any}) = merge(a, (Symbol(k) => v for (k, v) in b))