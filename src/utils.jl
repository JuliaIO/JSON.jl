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

utf16_is_surrogate(c::UInt16) = (c & 0xf800) == 0xd800
utf16_get_supplementary(lead::UInt16, trail::UInt16) = Char(UInt32(lead-0xd7f7)<<10 + trail)

@noinline invalid_escape(src, n) = throw(ArgumentError("encountered invalid escape character in json string: \"$(unsafe_string(src, n))\""))
@noinline unescaped_control(b) = throw(ArgumentError("encountered unescaped control character in json: '$(escape_string(Base.string(Char(b))))'"))

# unsafe because we're not checking that src or dst are valid pointers
# NOR are we checking that up to `n` bytes after dst are also valid to write to
function unsafe_unescape_to_buffer(src::Ptr{UInt8}, n::Int, dst::Ptr{UInt8})
    len = 1
    i = 1
    @inbounds begin
        while i <= n
            b = unsafe_load(src, i)
            if b == UInt8('\\')
                i += 1
                i > n && invalid_escape(src, n)
                b = unsafe_load(src, i)
                if b == UInt8('u')
                    # need at least 4 hex digits for '\uXXXX'
                    if i + 4 > n
                        invalid_escape(src, n)
                    end
                    # parse 4 hex digits into c without throwing
                    c = UInt16(0)
                    for offset in 1:4
                        bb = unsafe_load(src, i + offset)
                        nv = if UInt8('0') <= bb <= UInt8('9')
                                 bb - UInt8('0')
                             elseif UInt8('A') <= bb <= UInt8('F')
                                 bb - (UInt8('A') - 10)
                             elseif UInt8('a') <= bb <= UInt8('f')
                                 bb - (UInt8('a') - 10)
                             else
                                 invalid_escape(src, n)
                             end
                        c = (c << 4) + UInt16(nv)
                    end
                    # advance past the 4 hex digits
                    i += 4
                    b = unsafe_load(src, i)
                    if utf16_is_surrogate(c)
                        # check for a following "\uXXXX" to form a pair
                        if i + 6 > n || unsafe_load(src, i+1) != UInt8('\\') || unsafe_load(src, i+2) != UInt8('u')
                            # lone surrogate: emit raw code unit in WTF-8
                            b1 = UInt8(0xE0 | ((c >> 12) & 0x0F))
                            b2 = UInt8(0x80 | ((c >>  6) & 0x3F))
                            b3 = UInt8(0x80 | ( c         & 0x3F))
                            unsafe_store!(dst, b1, len); len += 1
                            unsafe_store!(dst, b2, len); len += 1
                            unsafe_store!(dst, b3, len); len += 1
                            continue
                        end
                        # parse next 4 hex digits into c2
                        c2 = UInt16(0)
                        for offset in 3:6
                            bb = unsafe_load(src, i + offset)
                            nv = if UInt8('0') <= bb <= UInt8('9')
                                     bb - UInt8('0')
                                 elseif UInt8('A') <= bb <= UInt8('F')
                                     bb - (UInt8('A') - 10)
                                 elseif UInt8('a') <= bb <= UInt8('f')
                                     bb - (UInt8('a') - 10)
                                 else
                                     invalid_escape(src, n)
                                 end
                            c2 = (c2 << 4) + UInt16(nv)
                        end
                        if utf16_is_surrogate(c2)
                            # valid surrogate pair: combine and emit as UTF-8
                            ch = utf16_get_supplementary(c, c2)
                            # consume the '\\uYYYY'
                            i += 6
                            st = codeunits(Base.string(ch))
                            for k = 1:length(st)-1
                                unsafe_store!(dst, st[k], len); len += 1
                            end
                            b = st[end]
                        else
                            # invalid trailing surrogate: treat lead as lone
                            b1 = UInt8(0xE0 | ((c >> 12) & 0x0F))
                            b2 = UInt8(0x80 | ((c >>  6) & 0x3F))
                            b3 = UInt8(0x80 | ( c         & 0x3F))
                            unsafe_store!(dst, b1, len); len += 1
                            unsafe_store!(dst, b2, len); len += 1
                            unsafe_store!(dst, b3, len); len += 1
                            continue
                        end
                    else
                        # non-surrogate: emit as usual
                        ch = Char(c)
                        st = codeunits(Base.string(ch))
                        for k = 1:length(st)-1
                            unsafe_store!(dst, st[k], len); len += 1
                        end
                        b = st[end]
                    end
                else
                    b = reverseescapechar(b)
                    b == 0x00 && invalid_escape(src, n)
                end
            end
            unsafe_store!(dst, b, len)
            len += 1
            i += 1
        end
    end
    return len-1
end
