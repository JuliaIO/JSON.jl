module JSONArrowExt

using JSON, ArrowTypes

const JSON_ARROW_NAME = Symbol("JuliaLang.JSON.Object")

ArrowTypes.ArrowKind(::Type{<:JSON.Object}) = ArrowTypes.StructKind()

ArrowTypes.toarrow(x::JSON.Object) = (; x...)
ArrowTypes.arrowname(::Type{<:JSON.Object}) = JSON_ARROW_NAME
ArrowTypes.JuliaType(::Val{JSON_ARROW_NAME}) = JSON.Object{Symbol,Any}

ArrowTypes.fromarrowstruct(::Type{T}, ::Val{nms}, vals...) where {T <: JSON.Object, nms} =
    T(nms[i] => vals[i] for i in 1:length(nms))

ArrowTypes.ToArrow(x::AbstractArray{T}) where {T <: JSON.Object} = _toarrow(x)
ArrowTypes.ToArrow(x::AbstractArray{Union{T,Missing}}) where {T <: JSON.Object} = _toarrow(x)
ArrowTypes.ToArrow(x::JSON.Object) = toarrow(x)

function _toarrow(x::Union{AbstractArray{T}, AbstractArray{Union{T,Missing}}}) where {T<:JSON.Object}
    isempty(x) && return Missing[]
    x isa AbstractArray{Missing} && return x
    fields = JSON.Object{Symbol, Type}()
    seen_fields = Set{Symbol}()
    for (i, y) in enumerate(x)
        y === missing && continue
        current_fields = Set{Symbol}()
        for (k, vv) in y
            key = Symbol(k)
            push!(current_fields, key)
            v = toarrow(vv)
            vtype = typeof(v)
            existing_type = get(fields, key, nothing)
            if existing_type !== nothing
                if !(vtype <: existing_type)
                    fields[key] = ArrowTypes.promoteunion(existing_type, vtype)
                end
            else
                if i == 1
                    fields[key] = vtype
                else
                    fields[key] = Union{vtype, Missing}
                end
            end
        end
        for field in seen_fields
            if !(field in current_fields)
                existing_type = fields[field]
                if !(Missing <: existing_type)
                    fields[field] = Union{existing_type, Missing}
                end
            end
        end
        union!(seen_fields, current_fields)
    end
    for y in x
        obj = toarrow(y)
        obj === missing && continue
        for (field, _) in fields
            if !haskey(obj, field)
                existing_type = fields[field]
                if !(Missing <: existing_type)
                    fields[field] = Union{existing_type, Missing}
                end
            end
        end
    end
    nms = Tuple(keys(fields))
    NT = NamedTuple{nms, Tuple{values(fields)...}}
    return ArrowTypes.ToArrow{NT,typeof(x)}(x)
end

function ArrowTypes._convert(::Type{NamedTuple{nms,T}}, nt) where {nms,T}
    vals = Tuple((nt !== missing && haskey(nt, nm)) ? toarrow(getproperty(nt, nm)) : missing for nm in nms)
    return NamedTuple{nms,T}(vals)
end

end # module
