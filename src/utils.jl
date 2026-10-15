# pre-1.11 compat
if VERSION < v"1.11"
    function _in!(x, s::Set)
        xT = convert(eltype(s), x)
        idx, sh = Base.ht_keyindex2_shorthash!(s.dict, xT)
        idx > 0 && return true
        Base._setindex!(s.dict, nothing, xT, -idx, sh)
        return false
    end
else
    const _in! = Base.in!
end

# hand-rolled scoped enum
module JSONTypes
    primitive type T 8 end
    T(x::UInt8) = reinterpret(T, x)
    const OBJECT = T(0x00)
    const ARRAY = T(0x01)
    const STRING = T(0x02)
    const INT = T(0x03)
    const FLOAT = T(0x04)
    const FALSE = T(0x05)
    const TRUE = T(0x06)
    const NULL = T(0x07)
    const NUMBER = T(0x08) # currently used by LazyValue
    const names = Dict(
        OBJECT => "OBJECT",
        ARRAY => "ARRAY",
        STRING => "STRING",
        INT => "INT",
        FALSE => "FALSE",
        TRUE => "TRUE",
        FLOAT => "FLOAT",
        NULL => "NULL",
        NUMBER => "NUMBER",
    )
    Base.show(io::IO, x::T) = Base.print(io, "JSONTypes.", names[x])
end

isjsonl(filename) = endswith(filename, ".jsonl") || endswith(filename, ".ndjson")

getlength(buf::AbstractVector{UInt8}) = length(buf)
getlength(buf::AbstractString) = sizeof(buf)

# unchecked
function getbyte(buf::AbstractVector{UInt8}, pos)
    @inbounds b = buf[pos]
    return b
end

# unchecked
function getbyte(buf::AbstractString, pos)
    @inbounds b = codeunit(buf, pos)
    return b
end

# helper macro to get the next byte from `buf` at index `pos`
# checks if `pos` is greater than `len` and @goto invalid if so
# if checkwh=true keep going until we get a non-whitespace byte
macro nextbyte(checkwh=true)
    esc(quote
        if pos > len
            error = UnexpectedEOF
            @goto invalid
        end
        b = getbyte(buf, pos)
        if $checkwh
            while b == UInt8('\t') || b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r')
                pos += 1
                if pos > len
                    error = UnexpectedEOF
                    @goto invalid
                end
                b = getbyte(buf, pos)
            end
        end
    end)
end

firstbyteeq(str::String, b::UInt8) = isempty(str) ? false : codeunit(str, 1) == b

# string escape/unescape utilities
const NEEDESCAPE = Set(map(UInt8, ('"', '\\', '\b', '\f', '\n', '\r', '\t')))

function escapechar(b)
    b == UInt8('"')  && return UInt8('"')
    b == UInt8('\\') && return UInt8('\\')
    b == UInt8('\b') && return UInt8('b')
    b == UInt8('\f') && return UInt8('f')
    b == UInt8('\n') && return UInt8('n')
    b == UInt8('\r') && return UInt8('r')
    b == UInt8('\t') && return UInt8('t')
    return 0x00
end

iscntrl(c::Char) = c <= '\x1f' || '\x7f' <= c <= '\u9f'
function escaped(b)
    if b == UInt8('/')
        return [UInt8('/')]
    elseif b >= 0x80
        return [b]
    elseif b in NEEDESCAPE
        return [UInt8('\\'), escapechar(b)]
    elseif iscntrl(Char(b))
        return UInt8[UInt8('\\'), UInt8('u'), Base.string(b, base=16, pad=4)...]
    else
        return [b]
    end
end

const ESCAPECHARS = [escaped(b) for b = 0x00:0xff]
const ESCAPELENS = [length(x) for x in ESCAPECHARS]

function escapelength(str)
    x = 0
    @simd for i = 1:ncodeunits(str)
        @inbounds len = ESCAPELENS[codeunit(str, i) + 1]
        x += len
    end
    return x
end

function reverseescapechar(b)
    b == UInt8('"')  && return UInt8('"')
    b == UInt8('\\') && return UInt8('\\')
    b == UInt8('/')  && return UInt8('/')
    b == UInt8('b')  && return UInt8('\b')
    b == UInt8('f')  && return UInt8('\f')
    b == UInt8('n')  && return UInt8('\n')
    b == UInt8('r')  && return UInt8('\r')
    b == UInt8('t')  && return UInt8('\t')
    return 0x00
end

@noinline invalid_escape(src, n) = throw(ArgumentError("encountered invalid escape character in json string: \"$(unsafe_string(src, n))\""))
@noinline unescaped_control(b) = throw(ArgumentError("encountered unescaped control character in json: '$(escape_string(Base.string(Char(b))))'"))

# the UTF-16 code unit spelled by the 4 hex digits at src[i:i+3]
@inline function unsafe_hex4(src::Ptr{UInt8}, i::Int, n::Int)
    c = UInt32(0)
    for k = i:(i + 3)
        b = unsafe_load(src, k)
        d = UInt8('0') <= b <= UInt8('9') ? b - UInt8('0') :
            UInt8('A') <= b <= UInt8('F') ? b - (UInt8('A') - 0x0a) :
            UInt8('a') <= b <= UInt8('f') ? b - (UInt8('a') - 0x0a) :
            invalid_escape(src, n)
        c = (c << 4) | d
    end
    return c
end

# write code point `c` at dst[len] as UTF-8 (a lone surrogate gives WTF-8); returns the next len
@inline function unsafe_store_utf8!(dst::Ptr{UInt8}, len::Int, c::UInt32)
    if c < 0x80
        unsafe_store!(dst, c % UInt8, len)
        return len + 1
    elseif c < 0x800
        unsafe_store!(dst, (0xc0 | (c >> 6)) % UInt8, len)
        unsafe_store!(dst, (0x80 | (c & 0x3f)) % UInt8, len + 1)
        return len + 2
    elseif c < 0x10000
        unsafe_store!(dst, (0xe0 | (c >> 12)) % UInt8, len)
        unsafe_store!(dst, (0x80 | ((c >> 6) & 0x3f)) % UInt8, len + 1)
        unsafe_store!(dst, (0x80 | (c & 0x3f)) % UInt8, len + 2)
        return len + 3
    end
    unsafe_store!(dst, (0xf0 | (c >> 18)) % UInt8, len)
    unsafe_store!(dst, (0x80 | ((c >> 12) & 0x3f)) % UInt8, len + 1)
    unsafe_store!(dst, (0x80 | ((c >> 6) & 0x3f)) % UInt8, len + 2)
    unsafe_store!(dst, (0x80 | (c & 0x3f)) % UInt8, len + 3)
    return len + 4
end

# unsafe because we're not checking that src or dst are valid pointers
# NOR are we checking that up to `n` bytes after dst are also valid to write to
function unsafe_unescape_to_buffer(src::Ptr{UInt8}, n::Int, dst::Ptr{UInt8})
    len = 1
    i = 1
    while i <= n
        b = unsafe_load(src, i)
        if b == UInt8('\\')
            i += 1
            i > n && invalid_escape(src, n)
            b = unsafe_load(src, i)
            if b == UInt8('u')
                i + 4 > n && invalid_escape(src, n)
                c = unsafe_hex4(src, i + 1, n)
                i += 4
                # a high surrogate followed by an escaped low surrogate is one code point;
                # any other surrogate is kept as a lone surrogate
                if 0xd800 <= c <= 0xdbff && i + 6 <= n &&
                   unsafe_load(src, i + 1) == UInt8('\\') && unsafe_load(src, i + 2) == UInt8('u')
                    lo = unsafe_hex4(src, i + 3, n)
                    if 0xdc00 <= lo <= 0xdfff
                        c = 0x10000 + ((c - 0xd800) << 10) + (lo - 0xdc00)
                        i += 6
                    end
                end
                len = unsafe_store_utf8!(dst, len, c)
                i += 1
                continue
            end
            b = reverseescapechar(b)
            b == 0x00 && invalid_escape(src, n)
        end
        unsafe_store!(dst, b, len)
        len += 1
        i += 1
    end
    return len - 1
end
