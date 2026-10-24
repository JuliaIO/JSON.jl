module JSONArrowExt

using JSON, ArrowTypes

const JSON_ARROW_NAME = Symbol("JuliaLang.JSON.Object")

ArrowTypes.ArrowKind(::Type{<:JSON.Object}) = ArrowTypes.StructKind()

ArrowTypes.toarrow(x::JSON.Object) = (; (Symbol(k) => v for (k, v) in x)...)

# nested objects stay `JSON.Object`s, so Arrow writes them through `_toarrow` too
_fieldvalue(v) = v isa JSON.Object ? v : toarrow(v)
ArrowTypes.arrowname(::Type{<:JSON.Object}) = JSON_ARROW_NAME
ArrowTypes.JuliaType(::Val{JSON_ARROW_NAME}) = JSON.Object{Symbol,Any}

# JSONText columns are stored as their JSON text
const JSONTEXT_ARROW_NAME = Symbol("JuliaLang.JSON.JSONText")
ArrowTypes.ArrowType(::Type{JSON.JSONText}) = String
ArrowTypes.toarrow(x::JSON.JSONText) = x.value
ArrowTypes.arrowname(::Type{JSON.JSONText}) = JSONTEXT_ARROW_NAME
ArrowTypes.JuliaType(::Val{JSONTEXT_ARROW_NAME}) = JSON.JSONText
ArrowTypes.fromarrow(::Type{JSON.JSONText}, x::AbstractString) = JSON.JSONText(String(x))

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
    hasmissing = false
    for (i, y) in enumerate(x)
        y === missing && (hasmissing = true; continue)
        current_fields = Set{Symbol}()
        for (k, vv) in y
            key = Symbol(k)
            push!(current_fields, key)
            v = _fieldvalue(vv)
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
    return ArrowTypes.ToArrow{hasmissing ? Union{NT,Missing} : NT,typeof(x)}(x)
end

function ArrowTypes._convert(::Type{NamedTuple{nms,T}}, nt) where {nms,T}
    vals = Tuple((nt !== missing && haskey(nt, nm)) ? _fieldvalue(getproperty(nt, nm)) : missing for nm in nms)
    return NamedTuple{nms,T}(vals)
end
ArrowTypes._convert(::Type{Union{Missing,NamedTuple{nms,T}}}, nt) where {nms,T} =
    nt === missing ? missing : ArrowTypes._convert(NamedTuple{nms,T}, nt)

end # module
