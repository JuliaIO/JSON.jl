module JSONSerializationExt

using JSON: Object
using Serialization: Serialization, AbstractSerializer, deserialize, deserialize_cycle,
    serialize_cycle_header, serialize_dict_data

# Marks the flat entry layout below. JSON ≤ 1.12 used Serialization's default layout, which
# starts with the root's `key` field (always `JSON.notset`), so the two are told apart on read.
struct EntryLayout end

# entries are written in order as a flat list, as for a `Dict`; the default field-by-field
# layout recurses once per entry of the linked list and overflows the stack
function Serialization.serialize(s::AbstractSerializer, x::Object)
    serialize_cycle_header(s, x) && return
    Serialization.serialize(s, EntryLayout())
    serialize_dict_data(s, x)
end

function Serialization.deserialize(s::AbstractSerializer, ::Type{Object{K,V}}) where {K,V}
    root = Object{K,V}()
    deserialize_cycle(s, root)
    first = deserialize(s)
    if first isa EntryLayout
        n = read(s.io, Int32)
        obj = root
        for _ in 1:n
            k = deserialize(s)
            v = deserialize(s)
            obj = Object{K,V}(obj, k, v)
        end
        return root
    end
    # JSON ≤ 1.12: the node's fields `key`, `value` and `child`, where `child` is the next
    # node in the same layout (or `notset`), so it arrives back here
    setfield!(root, :key, first)
    setfield!(root, :value, deserialize(s))
    setfield!(root, :child, deserialize(s))
    return root
end

end
