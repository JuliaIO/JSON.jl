"""
This is mostly a copy of (base/ryu) in the https://github.com/JuliaLang/julia repository.
Unfortunately that code is not public.
"""
module Ryu

# The following imported from Base are also internal so there definitions are copied below
# import .Base: significand_bits, significand_mask, exponent_bits, exponent_mask, exponent_bias, exponent_max, uinttype
const IEEEFloat = Union{Float16, Float32, Float64}

exponent_mask(::Type{Float64}) =    0x7ff0_0000_0000_0000
exponent_one(::Type{Float64}) =     0x3ff0_0000_0000_0000
significand_mask(::Type{Float64}) = 0x000f_ffff_ffff_ffff

exponent_mask(::Type{Float32}) =    0x7f80_0000
exponent_one(::Type{Float32}) =     0x3f80_0000
significand_mask(::Type{Float32}) = 0x007f_ffff

exponent_mask(::Type{Float16}) =    0x7c00
exponent_one(::Type{Float16}) =     0x3c00
significand_mask(::Type{Float16}) = 0x03ff

mantissa(x::T) where {T} = reinterpret(Unsigned, x) & significand_mask(T)

for T in (Float16, Float32, Float64)
    sb = trailing_ones(significand_mask(T))
    em = exponent_mask(T)
    eb = Int(exponent_one(T) >> sb)
    @eval significand_bits(::Type{$T}) = $(sb)
    @eval exponent_bits(::Type{$T}) = $(sizeof(T)*8 - sb - 1)
    @eval exponent_bias(::Type{$T}) = $(eb)
    # maximum float exponent
    @eval exponent_max(::Type{$T}) = $(Int(em >> sb) - eb - 1)
    # maximum float exponent without bias
    @eval exponent_raw_max(::Type{$T}) = $(Int(em >> sb))
end

# integer size of float
uinttype(::Type{Float64}) = UInt64
uinttype(::Type{Float32}) = UInt32
uinttype(::Type{Float16}) = UInt16

# import Base: append_c_digits_fast as append_c_digits, append_nine_digits

# 2-digit decimal characters ("00":"99")
const _dec_d100 = UInt16[
# generating expression: UInt16[(0x30 + i % 10) << 0x8 + (0x30 + i ÷ 10) for i = 0:99]
#    0 0,    0 1,    0 2,    0 3, and so on in little-endian
  0x3030, 0x3130, 0x3230, 0x3330, 0x3430, 0x3530, 0x3630, 0x3730, 0x3830, 0x3930,
  0x3031, 0x3131, 0x3231, 0x3331, 0x3431, 0x3531, 0x3631, 0x3731, 0x3831, 0x3931,
  0x3032, 0x3132, 0x3232, 0x3332, 0x3432, 0x3532, 0x3632, 0x3732, 0x3832, 0x3932,
  0x3033, 0x3133, 0x3233, 0x3333, 0x3433, 0x3533, 0x3633, 0x3733, 0x3833, 0x3933,
  0x3034, 0x3134, 0x3234, 0x3334, 0x3434, 0x3534, 0x3634, 0x3734, 0x3834, 0x3934,
  0x3035, 0x3135, 0x3235, 0x3335, 0x3435, 0x3535, 0x3635, 0x3735, 0x3835, 0x3935,
  0x3036, 0x3136, 0x3236, 0x3336, 0x3436, 0x3536, 0x3636, 0x3736, 0x3836, 0x3936,
  0x3037, 0x3137, 0x3237, 0x3337, 0x3437, 0x3537, 0x3637, 0x3737, 0x3837, 0x3937,
  0x3038, 0x3138, 0x3238, 0x3338, 0x3438, 0x3538, 0x3638, 0x3738, 0x3838, 0x3938,
  0x3039, 0x3139, 0x3239, 0x3339, 0x3439, 0x3539, 0x3639, 0x3739, 0x3839, 0x3939
]

function base_append_c_digits(olength::Int, digits::Unsigned, buf, pos::Int)
    i = olength
    while i >= 2
        d, c = divrem(digits, 0x64)
        digits = oftype(digits, d)
        @inbounds d100 = _dec_d100[(c % Int)::Int + 1]
        @inbounds buf[pos + i - 2] = d100 % UInt8
        @inbounds buf[pos + i - 1] = (d100 >> 0x8) % UInt8
        i -= 2
    end
    if i == 1
        @inbounds buf[pos] = UInt8('0') + rem(digits, 0xa) % UInt8
        i -= 1
    end
    return pos + olength
end

function append_nine_digits(digits::Unsigned, buf, pos::Int)
    if digits == 0
        for _ = 1:9
            @inbounds buf[pos] = UInt8('0')
            pos += 1
        end
        return pos
    end
    return @inline base_append_c_digits(9, digits, buf, pos) # force loop-unrolling on the length
end

function append_c_digits_fast(olength::Int, digits::Unsigned, buf, pos::Int)
    i = olength
    # n.b. olength may be larger than required to print all of `digits` (and will be padded
    # with zeros), but the printed number will be undefined if it is smaller, and may include
    # bits of both the high and low bytes.
    maxpow10 = 0x3b9aca00 # 10e9 as UInt32
    while i > 9 && digits > typemax(UInt)
        # do everything in cheap math chunks, using the processor's native math size
        d, c = divrem(digits, maxpow10)
        digits = oftype(digits, d)
        append_nine_digits(c % UInt32, buf, pos + i - 9)
        i -= 9
    end
    base_append_c_digits(i, digits % UInt, buf, pos)
    return pos + olength
end

const append_c_digits = append_c_digits_fast

include("utils.jl")
include("shortest.jl")
include("fixed.jl")
include("exp.jl")

"""
    Ryu.neededdigits(T)

Number of digits necessary to represent type `T` in fixed-precision decimal.
"""
neededdigits(::Type{Float64}) = 309 + 17
neededdigits(::Type{Float32}) = 39 + 9 + 2
neededdigits(::Type{Float16}) = 9 + 5 + 9

"""
    Ryu.writeshortest(x, plus=false, space=false, hash=true, precision=-1, expchar=UInt8('e'), padexp=false, decchar=UInt8('.'), typed=false, compact=false)
    Ryu.writeshortest(buf::AbstractVector{UInt8}, pos::Int, x, args...)

Convert a float value `x` into its "shortest" decimal string, which can be parsed back to the same value.
This function allows achieving the `%g` printf format.
Note the 2nd method allows passing in a byte buffer and position directly; callers must ensure the buffer has sufficient room to hold the entire decimal string.

Various options for the output format include:
  * `plus`: for positive `x`, prefix decimal string with a `'+'` character
  * `space`: for positive `x`, prefix decimal string with a `' '` character; overridden if `plus=true`
  * `hash`: whether the decimal point should be written, even if no additional digits are needed for precision
  * `precision`: minimum number of digits to be included in the decimal string; extra `'0'` characters will be added for padding if necessary
  * `expchar`: character to use exponent component in scientific notation
  * `padexp`: whether two digits should always be written, even for single-digit exponents (e.g. `e+1` becomes `e+01`)
  * `decchar`: decimal point character to be used
  * `typed`: whether additional type information should be printed for `Float16` / `Float32`
  * `compact`: output will be limited to 6 significant digits
"""
function writeshortest(x::T,
        plus::Bool=false,
        space::Bool=false,
        hash::Bool=true,
        precision::Integer=-1,
        expchar::UInt8=UInt8('e'),
        padexp::Bool=false,
        decchar::UInt8=UInt8('.'),
        typed::Bool=false,
        compact::Bool=false) where {T <: IEEEFloat}
    buf = Vector{UInt8}(undef, neededdigits(T))
    pos = writeshortest(buf, 1, x, plus, space, hash, precision, expchar, padexp, decchar, typed, compact)
    return String(resize!(buf, pos - 1))
end

"""
    Ryu.writefixed(x, precision, plus=false, space=false, hash=false, decchar=UInt8('.'), trimtrailingzeros=false)
    Ryu.writefixed(buf::AbstractVector{UInt8}, pos::Int, x, args...)

Convert a float value `x` into a "fixed" size decimal string of the provided precision.
This function allows achieving the `%f` printf format.
Note the 2nd method allows passing in a byte buffer and position directly; callers must ensure the buffer has sufficient room to hold the entire decimal string.

Various options for the output format include:
  * `plus`: for positive `x`, prefix decimal string with a `'+'` character
  * `space`: for positive `x`, prefix decimal string with a `' '` character; overridden if `plus=true`
  * `hash`: whether the decimal point should be written, even if no additional digits are needed for precision
  * `precision`: minimum number of significant digits to be included in the decimal string; extra `'0'` characters will be added for padding if necessary
  * `decchar`: decimal point character to be used
  * `trimtrailingzeros`: whether trailing zeros of fractional part should be removed
"""
function writefixed(x::T,
    precision::Integer,
    plus::Bool=false,
    space::Bool=false,
    hash::Bool=false,
    decchar::UInt8=UInt8('.'),
    trimtrailingzeros::Bool=false) where {T <: IEEEFloat}
    buf = Vector{UInt8}(undef, precision + neededdigits(T))
    pos = writefixed(buf, 1, x, precision, plus, space, hash, decchar, trimtrailingzeros)
    return String(resize!(buf, pos - 1))
end

"""
    Ryu.writeexp(x, precision, plus=false, space=false, hash=false, expchar=UInt8('e'), decchar=UInt8('.'), trimtrailingzeros=false)
    Ryu.writeexp(buf::AbstractVector{UInt8}, pos::Int, x, args...)

Convert a float value `x` into a scientific notation decimal string.
This function allows achieving the `%e` printf format.
Note the 2nd method allows passing in a byte buffer and position directly; callers must ensure the buffer has sufficient room to hold the entire decimal string.

Various options for the output format include:
  * `plus`: for positive `x`, prefix decimal string with a `'+'` character
  * `space`: for positive `x`, prefix decimal string with a `' '` character; overridden if `plus=true`
  * `hash`: whether the decimal point should be written, even if no additional digits are needed for precision
  * `precision`: minimum number of significant digits to be included in the decimal string; extra `'0'` characters will be added for padding if necessary
  * `expchar`: character to use exponent component in scientific notation
  * `decchar`: decimal point character to be used
  * `trimtrailingzeros`: whether trailing zeros should be removed
"""
function writeexp(x::T,
    precision::Integer,
    plus::Bool=false,
    space::Bool=false,
    hash::Bool=false,
    expchar::UInt8=UInt8('e'),
    decchar::UInt8=UInt8('.'),
    trimtrailingzeros::Bool=false) where {T <: IEEEFloat}
    buf = Vector{UInt8}(undef, precision + neededdigits(T))
    pos = writeexp(buf, 1, x, precision, plus, space, hash, expchar, decchar, trimtrailingzeros)
    return String(resize!(buf, pos - 1))
end

end # module
