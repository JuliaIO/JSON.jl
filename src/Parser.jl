module Parser  # JSON

using Compat
using Compat.Mmap
using ..Common

"""
Like `isspace`, but work on bytes and includes only the four whitespace
characters defined by the JSON standard: space, tab, line feed, and carriage
return.
"""
is_json_space(ch::UInt8) = ch == SPACE || ch == TAB || ch == NEWLINE || ch == RETURN

is_json_exp(ch::UInt8) =  ch == LATIN_E || ch == LATIN_UPPER_E

is_json_float(ch::UInt8) = ch == DECIMAL_POINT || is_json_exp(ch)

is_json_digit(ch::UInt8) = (ch - DIGIT_ZERO) < 0xa

abstract type ParserState end

struct ParserContext{DictType, IntType, FloatType} end

get_dict_type(::ParserContext{T,<:Any,<:Any}) where {T} = T
get_int_type(::ParserContext{<:Any,T,<:Any}) where {T<:Real} = T
get_float_type(::ParserContext{<:Any,<:Any,T}) where {T<:Real} = T

utf16_is_surrogate(ch::UInt16) = (ch & 0xf800) == 0xd800
utf16_get_supplementary(lead::UInt16, trail::Unsigned) = (lead-0xd7f7)%UInt32<<10 + trail

function unparameterize_type(T::Type)
    candidate = typeintersect(T, AbstractDict{String, Any})
    candidate <: Union{} ? T : candidate
end

# Support functions for handling parsing numbers more generically

@static isdefined(Base, :codeunits) ||
    (Base.codeunit(str::AbstractString) = eltype(codeunits(str)))

"""
Parse a float from the given bytes vector, starting at `from` and ending at the
byte before `to`. Bytes enclosed should all be ASCII characters.
"""
function parse_float end

@noinline numerror(bytes, from, to, msg) =
    error("Unable to parse \"$(bytes[from:to])\"$msg")
@noinline numerror(io::IO, ch) =
    error("Unable to parse \"$(String(take!(io)))$(Char(ch))\"")

# Handle removal of Nullables from Base
@static if VERSION < v"0.7.0-DEV"

using Nullables

function _parse_float64(::Type{UInt8}, bytes, from::Int, to::Int)
    # The ccall is not ideal (Base.tryparse would be better), but it actually
    # makes an 2× difference to performance
    # Handle differences in return values from tryparse
    res = ccall(:jl_try_substrtod, Nullable{Float64},
                (Ptr{UInt8}, Csize_t, Csize_t),
                bytes, from - 1, to - from + 1)
    isnull(res) && numerror(bytes, from, to, " as a Float64")
    get(res)
end

else

function _parse_float64(::Type{UInt8}, bytes, from::Int, to::Int)
    hasvalue, val = ccall(:jl_try_substrtod, Tuple{Bool, Float64},
                          (Ptr{UInt8}, Csize_t, Csize_t),
                          bytes, from - 1, to - from + 1)
    hasvalue || numerror(bytes, from, to, " as a Float64")
    val
end

end

function _parse_float64(::Type{Union{UInt16,UInt32}}, str, from::Int, to::Int)
    str = convert(String, SubString(str, from, to))
    _parse_float64(UInt8, str, 1, sizeof(str))
end

parse_float(::Type{T}, isneg, str::AbstractString) where {T<:AbstractFloat} =
    Base.parse(T, str)
parse_float(::Type{T}, isneg, str::AbstractString,
            from::Int64, to::Int64) where {T<:AbstractFloat} =
    Base.parse(T, SubString(str, from, to))

parse_float(::Type{Float64}, isneg, str::AbstractString, from::Int, to::Int) =
    _parse_float64(codeunit(str), str, from, to)
parse_float(::Type{Float16}, isneg, str::AbstractString, from::Int, to::Int) =
    convert(Float16, _parse_float64(codeunit(str), str, from, to))
parse_float(::Type{Float32}, isneg, str::AbstractString, from::Int, to::Int) =
    convert(Float32, _parse_float64(codeunit(str), str, from, to))

"""
Parse an integer, starting at `from` and ending at `to`
Bytes enclosed should all be ASCII characters.
"""
function parse_int end

# Todo: There is no reason that you should ever have an overflow in Julia, or lose precision
# Also, parsing numbers can be faster by having a "JSON" number type, that can be converted
# to whatever types wanted by the user (it would probably be 2 types, one primitive bits type,
# with 64 bits, that can hold 53 bits of unsigned integer, 1 bit of sign, and 10 bits of
# *decimal* exponent (i.e. -512..511), if that overflows, use a BigInt/Int, or BigInt/BigInt.

# Have to test how this compares as a fallback
# Also want to see about optionally promoting to a larger type if there is any overflow
function parse_int(::Type{T}, isneg, str::AbstractString,
                    from::Int=1, to::Int=ncodeunits(str)) where {T<:Integer}
    from += isneg
    num = T(codeunit(str, from) - DIGIT_ZERO)
    ten = T(10)
    @inbounds for i = from+1:to
        num = muladd(num, ten, T(codeunit(str, i) - DIGIT_ZERO))
    end
    isneg ? -num : num
end

const _BuiltInSigned   = Union{Int8, Int16, Int32, Int64, Int128}
const _BuiltInUnsigned = Union{UInt8, UInt16, UInt32, UInt64, UInt128}
const _BuiltInInteger  = Union{_BuiltInSigned, _BuiltInUnsigned, BigInt}

parse_int(::Type{T}, isneg, str::AbstractString,
                   from::Int, to::Int) where {T<:_BuiltInInteger} =
    Base.parse(T, SubString(str, from, to))
parse_int(::Type{T}, isneg, str::AbstractString) where {T<:_BuiltInInteger} =
    Base.parse(T, str)

parse(input;
#      dicttype::Type{<:AbstractDict}=Dict{SubString{String},Any},
      dicttype::Type{<:AbstractDict}=Dict{String,Any},
      inttype::Type{<:Real}=Int64,
      floattype::Type{<:Real}=Float64) =
    _parse(input, ParserContext{unparameterize_type(dicttype), inttype, floattype}())

function parsefile(filename::AbstractString; use_mmap=false, kwargs...)
    open(filename) do io
        parse((use_mmap
               ? String(Mmap.mmap(io, Vector{UInt8}, filesize(filename)))
               : read(io, String)); kwargs...)
    end
end

include("StreamParser.jl") # More generic implementations, can work on IO stream
include("MemoryParser.jl") # Efficient implementations for in-memory parsing

end  # module Parser
