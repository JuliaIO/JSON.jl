module JSONSerializationExt

using JSON: Object
using Serialization: Serialization, AbstractSerializer, deserialize, deserialize_cycle,
    serialize_cycle_header, serialize_dict_data

# entries are written in order as a flat list, as for a `Dict`; the default field-by-field
# format recurses once per entry of the linked list and overflows the stack
function Serialization.serialize(s::AbstractSerializer, x::Object)
    serialize_cycle_header(s, x) && return
    serialize_dict_data(s, x)
end

function Serialization.deserialize(s::AbstractSerializer, ::Type{Object{K,V}}) where {K,V}
    n = read(s.io, Int32)
    root = obj = Object{K,V}()
    deserialize_cycle(s, root)
    for _ in 1:n
        k = deserialize(s)
        v = deserialize(s)
        obj = Object{K,V}(obj, k, v)
    end
    return root
end

end
