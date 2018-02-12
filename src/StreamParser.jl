@inline read_byte(io) = read(io, UInt8)

@noinline _eoferr() = error("Unexpected end of input")

"""
Return the next byte from `io`. If there is no byte, then an error is thrown that the
input ended unexpectedly.
"""
@inline next_byte(io) = eof(io) ? _eoferr() : read_byte(io)

@noinline _error(message::AbstractString, ch) =
    error("$message\n ...when parsing byte with value '\\x$(hex(ch,2))'")

_expecterr(expected, ch) =
    _error("Expected '$(Char(expected))' here", ch)

_expecterr(exp1, exp2, ch) =
    _error("Expected '$(Char(exp1))' or '$(Char(exp2))' here", ch)

@inline output_codeunit(buf, cu) = write(buf, cu%UInt8)

"""
Require the next byte from `io` to be the given byte. Otherwise, an error is thrown.
"""
@inline skip!(io::IO, expected::UInt8) =
    ((ch = next_byte(io)) == expected || _expecterr(expected, ch))

@inline function skip_digits!(io::IO, number)
    while !eof(io)
        ch = read_byte(io)
        is_json_digit(ch) || return ch
        write(number, ch)
    end
    0x00
end

"""
Remove as many whitespace bytes as possible from the io stream, return non-space
"""
@inline function chomp_space!(io::IO)
    while !eof(io)
        ch = read_byte(io)
        is_json_space(ch) || return ch
    end
    0x00
end

# PARSING

"""
Given an io stream, and initial byte, return the next parseable value
"""
function parse_value(pc::ParserContext, io::IO, ch::UInt8)
    if ch == STRING_DELIM
        parse_string(io)
    elseif ch == OBJECT_BEGIN
        parse_object(pc, io)
    elseif ch == ARRAY_BEGIN
        parse_array(pc, io)
    elseif ch == LATIN_T  # true
        skip!(io, LATIN_R)
        skip!(io, LATIN_U)
        skip!(io, LATIN_E)
        true
    elseif ch == LATIN_F  # false
        skip!(io, LATIN_A)
        skip!(io, LATIN_L)
        skip!(io, LATIN_S)
        skip!(io, LATIN_E)
        false
    elseif ch == LATIN_N  # null
        skip!(io, LATIN_U)
        skip!(io, LATIN_L)
        skip!(io, LATIN_L)
        nothing
    else
        _error(E_UNEXPECTED_CHAR, ch)
    end
end

function parse_array(pc::ParserContext, io::IO)
    arr = Any[]
    while (ch = chomp_space!(io)) != ARRAY_END
        if is_json_digit(ch) || ch == MINUS_SIGN
            val, ch = parse_number(pc, io, ch)
            push!(arr, val)
        else
            push!(arr, parse_value(pc, io, ch))
            ch = next_byte(io)
        end
        ch == DELIMITER && continue
        ch == ARRAY_END && break
        if is_json_space(ch)
            ch = chomp_space!(io)
            ch == DELIMITER && continue
            ch == ARRAY_END && break
        end
        _expecterr(ARRAY_END, DELIMITER, ch)
    end
    arr
end

function parse_object(pc::ParserContext, io::IO)
    DictType = get_dict_type(pc)
    obj = DictType()
    keyT = keytype(DictType)
    while (ch = chomp_space!(io)) != OBJECT_END
        # Read key
        ch == STRING_DELIM || _error(E_BAD_KEY, ch)
        key = parse_string(io)
        chomp_space!(io) == SEPARATOR || _expecterr(SEPARATOR, ch)
        ch = chomp_space!(io) # Skip over separator
        # Read value
        if is_json_digit(ch) || ch == MINUS_SIGN
            val, ch = parse_number(pc, io, ch)
            obj[keyT(key)] = val
        else
            obj[keyT(key)] = parse_value(pc, io, ch)
            ch = next_byte(io)
        end
        ch == DELIMITER && continue
        ch == OBJECT_END && break
        if is_json_space(ch)
            ch = chomp_space!(io)
            ch == DELIMITER && continue
            ch == OBJECT_END && break
        end
        _expecterr(OBJECT_END, DELIMITER, ch)
    end
    obj
end

@inline function _get_hex_digit!(io::IO)
    ch = next_byte(io)
    if (ch - DIGIT_ZERO) < 0xa
        ch - DIGIT_ZERO
    elseif (ch - LATIN_A) < 0x6
        ch - LATIN_A + 0x0a
    elseif (ch - LATIN_UPPER_A) < 0x6
        ch - LATIN_UPPER_A + 0x0a
    else
        _error(E_BAD_ESCAPE, ch)
    end
end

read_four_hex_digits!(io::IO) =
    (_get_hex_digit!(io)%UInt16 << 12) |
    (_get_hex_digit!(io)%UInt16 << 8) |
    (_get_hex_digit!(io) << 4) |
     _get_hex_digit!(io)

# Always called with last character seen STRING_DELIM
function parse_string(io::IO)
    buf = IOBuffer()
    while true
        ch = next_byte(io)
        if ch == BACKSLASH
            ch = next_byte(io)
            if ch == LATIN_U  # Unicode escape
                u1 = read_four_hex_digits!(io)
                if u1 < 0x80
                    output_codeunit(buf, u1)
                elseif u1 < 0x800
                    output_codeunit(buf, 0xc0 | (u1 >>> 6))
                    output_codeunit(buf, 0x80 | (u1 & 0x3f))
                elseif !utf16_is_surrogate(u1)
                    output_codeunit(buf, 0xe0 | ((u1 >>> 12) & 0x3f))
                    output_codeunit(buf, 0x80 | ((u1 >>> 6) & 0x3f))
                    output_codeunit(buf, 0x80 | (u1 & 0x3f))
                else
                    skip!(io, BACKSLASH)
                    skip!(io, LATIN_U)
                    c32 = utf16_get_supplementary(u1, read_four_hex_digits!(io)%UInt32)
                    output_codeunit(buf, 0xf0 | (c32 >>> 18))
                    output_codeunit(buf, 0x80 | ((c32 >>> 12) & 0x3f))
                    output_codeunit(buf, 0x80 | ((c32 >>> 6) & 0x3f))
                    output_codeunit(buf, 0x80 | (c32 & 0x3f))
                end
            elseif ch == BACKSLASH || ch == STRING_DELIM || ch == SOLIDUS
                output_codeunit(buf, ch)
            elseif (ch - LATIN_B) < 19 && (ch = ESCAPE_TAB[ch - LATIN_B + 1]) != 0x00
                output_codeunit(buf, ch)
            else
                _error(E_BAD_ESCAPE, ch)
            end
        elseif ch < SPACE
            _error(E_BAD_CONTROL, ch)
        elseif ch == STRING_DELIM
            break
        else
            output_codeunit(buf, ch)
        end
    end
    String(take!(buf))
end

function parse_number(pc::ParserContext, io::IO, ch::UInt8)
    # Determine the end of the floating point by skipping past ASCII values
    # 0-9, +, -, e, E, and .
    number = IOBuffer()
    write(number, ch)
    isneg = false

    # optional - followed by:
    #   0 followed by . or non-digit or EOF
    #   1-9 followed by 0-9* followed by . or non-digit or EOF
    #   . followed by 0-9+ followed by 0-9* followed by:
    #      EOF or non-digit
    #      e or E, followed by +, -, or 0-9+ followed by non-digit or EOF
    #         + or -, followed by 0-9+ followed by non-digit or EOF
    #
    if ch == MINUS_SIGN
        isneg = true
        ch = next_byte(io)
        is_json_digit(ch) || numerror(number, ch)
        write(number, ch)
    end
    # Handle 0 specially
    if ch == DIGIT_ZERO
        eof(io) && return zero(get_int_type(pc)), 0x00
        ch = read_byte(io)
        is_json_digit(ch) && _error(E_LEADING_ZERO, ch)
        is_json_float(ch) || return zero(get_int_type(pc)), ch
    else
        # Must be 1..9 or -1..9
        ch = skip_digits!(io, number)
        is_json_float(ch) || return parse_int(get_int_type(pc), isneg, String(take!(number))), ch
    end
    if ch == DECIMAL_POINT
        # Must have one or more digits after decimal point
        write(number, ch)
        ch = next_byte(io)
        is_json_digit(ch) || numerror(number, ch)
        write(number, ch)
        ch = skip_digits!(io, number)
    end
    if is_json_exp(ch)
        # e or E, followed by +, -, or 0-9+ followed by non-digit or EOF
        #    + or -, followed by 0-9+ followed by non-digit or EOF
        # Must have one or more digits after 'e' or 'E'
        write(number, ch)
        ch = next_byte(io)
        if ch == PLUS_SIGN || ch == MINUS_SIGN
            write(number, ch)
            ch = next_byte(io)
        end
        is_json_digit(ch) || numerror(number, ch)
        write(number, ch)
        ch = skip_digits!(io, number)
    end
    str = String(take!(number))
    parse_float(get_float_type(pc), isneg, str, 1, sizeof(str)), ch
end

function _parse(io::IO, pc::ParserContext)
    eof(io) && _eoferr()
    ch = chomp_space!(io)
    ((is_json_digit(ch) || ch == MINUS_SIGN)
     ? parse_number(pc, io, ch)[1]
     : parse_value(pc, io, ch))
end
