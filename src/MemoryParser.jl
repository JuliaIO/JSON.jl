# Specialized functions for increased performance when JSON is in-memory

check_end(str, pnt, fin) = pnt >= fin && _error(E_UNEXPECTED_EOF, str, pnt)

@inline set_codeunit!(pnt, ch) = unsafe_store!(pnt, ch)
@inline get_codeunit(pnt) = unsafe_load(pnt)

@static VERSION < v"0.7.0-DEV" ? (substr_index(str, pos) = pos) : (const substr_index = thisind)

function _parse(str::String, pc::ParserContext)
    siz = sizeof(str)
    pnt = pointer(str)
    fin = pnt + siz
    v, pnt = parse_value(pc, str, pnt, fin)
    # Make sure only space is at end
    while pnt < fin
        is_json_space(get_codeunit(pnt)) || _error(E_EXPECTED_EOF, str, pnt)
        pnt += 1
    end
    v
end

_parse(str::AbstractString, pc::ParserContext) = _parse(convert(String, str), pc)

@inline function skip_space(str, pnt, fin)
    while pnt < fin
        ch = get_codeunit(pnt)
        is_json_space(ch) || return ch, pnt
        pnt += 1
    end
    _error(E_UNEXPECTED_EOF, str, pnt)
end

@inline check(expected::UInt8, str, pnt) =
    (ch = get_codeunit(pnt)) == expected || _expecterr(expected, ch, str, pnt)

function parse_value(pc::ParserContext, str, pnt, fin)
    ch, pnt = skip_space(str, pnt, fin)
    if ch == STRING_DELIM
        parse_string(str, pnt, fin)
    elseif is_json_digit(ch) || ch == MINUS_SIGN
        parse_number(pc, ch, str, pnt, fin)
    elseif ch == OBJECT_BEGIN
        parse_object(pc, str, pnt, fin)
    elseif ch == ARRAY_BEGIN
        parse_array(pc, str, pnt, fin)
    elseif ch == LATIN_T  # true
        check_end(str, pnt + 3, fin)
        check(LATIN_R, str, pnt + 1)
        check(LATIN_U, str, pnt + 2)
        check(LATIN_E, str, pnt + 3)
        true, pnt + 4
    elseif ch == LATIN_F  # false
        check_end(str, pnt + 4, fin)
        check(LATIN_A, str, pnt + 1)
        check(LATIN_L, str, pnt + 2)
        check(LATIN_S, str, pnt + 3)
        check(LATIN_E, str, pnt + 4)
        false, pnt + 5
    elseif ch == LATIN_N  # null
        check_end(str, pnt + 3, fin)
        check(LATIN_U, str, pnt + 1)
        check(LATIN_L, str, pnt + 2)
        check(LATIN_L, str, pnt + 3)
        nothing, pnt + 4
    else
        _error(E_UNEXPECTED_CHAR, str, pnt)
    end
end

# Used for line counts
function _count_before(haystack::AbstractString, needle, fin::Int)
    count = 0
    for (pos, ch) in enumerate(haystack)
        # This is incorrect!  Only works if no Unicode characters
        # or not a multi-byte representation
        pos >= fin && break
        count += (ch == needle)
    end
    count
end

# Throws an error message with an indicator to the source
@noinline function _error(message::AbstractString, str, pnt)
    pos = Int(pnt - pointer(str) + 1)
    lines = _count_before(str, '\n', pos)
    # Replace all special multi-line/multi-space characters with a space.
    strnl = replace(str, r"[\b\f\n\r\t\s]" => " ")
    li = substr_index(strnl, (pos > 20) ? pos - 9 : 1)    # Left index
    ri = substr_index(strnl, min(sizeof(str), pos + 20))  # Right index
    error("$message\nLine: $lines\nAround: ...$(strnl[li:ri])...\n$(" " ^ (11 + pos - li))^\n")
end

_expecterr(expected, ch, str, pos) =
    _error("Expected '$(Char(expected))' here, got '\\x$(hex(ch,2))'", str, pos)

_expecterr(exp1, exp2, ch, str, pos) =
    _error("Expected '$(Char(exp1))' or '$(Char(exp2))' here, got '\\x$(hex(ch,2))'", str, pos)

function parse_array(pc::ParserContext, str, pos, fin)
    ch, pos = skip_space(str, pos + 1, fin) # Skip over opening '[' and any space after it
    arr = Any[]
    ch == ARRAY_END && return arr, pos + 1
    while true
        val, pos = parse_value(pc, str, pos, fin)
        push!(arr, val)
        ch, pos = skip_space(str, pos, fin)
        ch == ARRAY_END && break
        ch == DELIMITER || _expecterr(ARRAY_END, DELIMITER, ch, str, pos)
        pos += 1
    end
    arr, pos + 1
end

function parse_object(pc::ParserContext, str, pos, fin)
    DictType = get_dict_type(pc)
    obj = DictType()
    ch, pos = skip_space(str, pos + 1, fin) # Skip over opening '{' and any space after it
    ch == OBJECT_END && return obj, pos + 1
    KeyType = keytype(DictType)
    while true
        # Read key
        ch, pos = skip_space(str, pos, fin)
        ch == STRING_DELIM || _error(E_BAD_KEY, str, pos)
        key, pos = parse_string(str, pos, fin)
        ch, pos = skip_space(str, pos, fin)
        ch == SEPARATOR || _expecterr(SEPARATOR, ch, str, pos)
        # Read value
        value, pos = parse_value(pc, str, pos + 1, fin)
        obj[KeyType(key)] = value
        ch, pos = skip_space(str, pos, fin)
        ch == OBJECT_END && break
        ch == DELIMITER || _expecterr(OBJECT_END, DELIMITER, ch, str, pos)
        pos += 1
    end
    obj, pos + 1
end

@inline function _get_hex_digit(str, pnt)
    ch = get_codeunit(pnt)
    if (ch - DIGIT_ZERO) < 10
        ch - DIGIT_ZERO
    elseif (ch - LATIN_A) < 6
        ch - LATIN_A + 0x0a
    elseif (ch - LATIN_UPPER_A) < 6
        ch - LATIN_UPPER_A + 0x0a
    else
        _error(E_BAD_ESCAPE, str, pnt)
    end
end

@inline function check_hex_digit(str, pnt)
    ch = get_codeunit(pnt)
    ((ch - DIGIT_ZERO) > 9) && ((ch - LATIN_A) > 5) && ((ch - LATIN_UPPER_A) > 5) &&
        _error(E_BAD_ESCAPE, str, pnt)
end

@inline get_four_hex_digits(str, pnt) =
    (_get_hex_digit(str, pnt - 3)%UInt16 << 12) |
    (_get_hex_digit(str, pnt - 2)%UInt16 << 8) |
    (_get_hex_digit(str, pnt - 1) << 4) |
     _get_hex_digit(str, pnt)

function parse_string(str, beg, fin)
    # "Dry Run": find length of string so we can allocate the right amount of
    # memory from the start. Does not do full error checking.
    pnt, tot = predict_string(str, beg, fin)
    len = pnt - beg - 1 - tot  # Adjust for beginning and end quotes, and escape sequences

    # Fast path occurs when the string has no escaped characters. This is quite
    # often the case in real-world data, especially when keys are short strings.
    # We can just copy the data from the buffer in this case or return a SubString
    if tot == 0
        # SubString(str, beg + 1, substr_index(str, beg + len)), pnt + 1
        unsafe_string(beg + 1, len), pnt + 1
    else
        # Now read the string itself
        outstr = Base._string_n(len)
        out = pointer(outstr)
        parse_string!(out, out + len, str, beg)
        outstr, pnt + 1
    end
end

"""
Scan through a string at the current parser state and return a tuple containing
information about the string. This function avoids memory allocation where
possible.

The first element of the returned tuple is a boolean indicating whether the
string may be copied directly from the parser state. Special casing string
parsing when there are no escaped characters leads to substantially increased
performance in common situations.

The second element of the returned tuple is an integer representing the exact
length of the string, in bytes when encoded as UTF-8. This information is useful
for pre-sizing a buffer to contain the parsed string.

This function will throw an error if:

 - invalid control characters are found
 - an invalid unicode escape is read
 - the string is not terminated

No error is thrown when other invalid backslash escapes are encountered.
"""
function predict_string(str, pnt, fin)
    # pnt is positioned at the opening "
    fastpath = true  # true if no escapes in this string, so it can be copied
    tot = 0
    while true
        check_end(str, pnt += 1, fin)
        if (ch = get_codeunit(pnt)) == BACKSLASH
            check_end(str, pnt += 1, fin)
            if (ch = get_codeunit(pnt)) == LATIN_U  # Unicode escape
                check_end(str, pnt += 4, fin)
                u1 = get_four_hex_digits(str, pnt)
                if utf16_is_surrogate(u1)
                    check_end(str, pnt += 6, fin)
                    check(BACKSLASH, str, pnt - 5)
                    check(LATIN_U,   str, pnt - 4)
                    check_hex_digit(str, pnt - 3)
                    check_hex_digit(str, pnt - 2)
                    check_hex_digit(str, pnt - 1)
                    check_hex_digit(str, pnt)
                    tot += 8
                else
                    tot += 5 - (u1 < 0x80 ? 0 : u1 < 0x800 ? 1 : 2)
                end
            else
                tot += 1
            end
        elseif ch == STRING_DELIM
            break
        elseif ch < SPACE
            _error(E_BAD_CONTROL, str, pnt)
        end
    end
    pnt, tot
end

"""
Parse the string starting at the parser state’s current location into the given
pre-sized buffer. The only correctness checking is for escape sequences, so the
passed-in buffer must exactly represent the amount of space needed for parsing.
"""
function parse_string!(buf, fin, str, pnt)
    while buf < fin
        ch = get_codeunit(pnt += 1)
        if ch == BACKSLASH
            ch = get_codeunit(pnt += 1)
            if ch == LATIN_U  # Unicode escape
                u1 = get_four_hex_digits(str, pnt += 4)
                if u1 < 0x80
                    set_codeunit!(buf, u1%UInt8)
                elseif u1 < 0x800
                    set_codeunit!(buf,      0xc0 | (u1 >>> 6))
                    set_codeunit!(buf += 1, 0x80 | (u1 & 0x3f))
                elseif !utf16_is_surrogate(u1)
                    set_codeunit!(buf,      0xe0 | ((u1 >>> 12) & 0x3f))
                    set_codeunit!(buf += 1, 0x80 | ((u1 >>> 6) & 0x3f))
                    set_codeunit!(buf += 1, 0x80 | (u1 & 0x3f))
                else
                    c32 = utf16_get_supplementary(u1, get_four_hex_digits(str, pnt += 6)%UInt32)
                    set_codeunit!(buf,      0xf0 | (c32 >>> 18))
                    set_codeunit!(buf += 1, 0x80 | ((c32 >>> 12) & 0x3f))
                    set_codeunit!(buf += 1, 0x80 | ((c32 >>> 6) & 0x3f))
                    set_codeunit!(buf += 1, 0x80 | (c32 & 0x3f))
                end
            elseif ch == BACKSLASH || ch == STRING_DELIM || ch == SOLIDUS
                set_codeunit!(buf, ch)
            elseif (ch - LATIN_B) < 19 && (ch = ESCAPE_TAB[ch - LATIN_B + 1]) != 0x00
                set_codeunit!(buf, ch)
            else
                _error(E_BAD_ESCAPE, str, pnt)
            end
        else
            # UTF8-encoded non-ascii characters will be copied verbatim, which is
            # the desired behaviour
            set_codeunit!(buf, ch)
        end
        buf += 1
    end
    # don't worry about non-termination or other edge cases; those should have
    # been caught in the dry run.
    pnt + 1 # Skip over terminating "
end

@inline function skip_digits!(str, pnt, fin)
    while (pnt += 1) < fin
        ch = get_codeunit(pnt)
        is_json_digit(ch) || return ch, pnt
    end
    0x00, pnt
end

function parse_int(::Type{T}, isneg, pnt, fin) where {T<:Integer}
    pnt += isneg
    num = T(get_codeunit(pnt) - DIGIT_ZERO)
    ten = T(10)
    while (pnt += 1) < fin
        num = muladd(num, ten, T(get_codeunit(pnt) - DIGIT_ZERO))
    end
    isneg ? -num : num
end

function parse_number(pc::ParserContext, ch, str, pnt, fin)
    beg = pnt
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
        check_end(str, pnt += 1, fin)
        ch = get_codeunit(pnt)
        is_json_digit(ch) || _error(E_BAD_NUMBER, str, pnt)
        isneg = true
    end
    # Handle 0 specially
    if ch == DIGIT_ZERO
        (pnt += 1) > fin && return zero(get_int_type(pc)), pnt
        ch = get_codeunit(pnt)
        is_json_digit(ch) && _error(E_LEADING_ZERO, str, pnt)
        is_json_float(ch) || return zero(get_int_type(pc)), pnt
    else
        # Must be 1..9 or -1..9
        ch, pnt = skip_digits!(str, pnt, fin)
        is_json_float(ch) || return parse_int(get_int_type(pc), isneg, beg, pnt), pnt
    end
    if ch == DECIMAL_POINT
        # Must have one or more digits after decimal point
        check_end(str, pnt += 1, fin)
        ch = get_codeunit(pnt)
        is_json_digit(ch) || _error(E_BAD_NUMBER, str, pnt)
        ch, pnt = skip_digits!(str, pnt, fin)
    end
    if is_json_exp(ch)
        # e or E, followed by +, -, or 0-9+ followed by non-digit or EOF
        #    + or -, followed by 0-9+ followed by non-digit or EOF
        # Must have one or more digits after 'e' or 'E'
        check_end(str, pnt += 1, fin)
        ch = get_codeunit(pnt)
        if ch == PLUS_SIGN || ch == MINUS_SIGN
            check_end(str, pnt += 1, fin)
            ch = get_codeunit(pnt)
        end
        is_json_digit(ch) || _error(E_BAD_NUMBER, str, pnt)
        ch, pnt = skip_digits!(str, pnt, fin)
    end
    base = pointer(str)
    parse_float(get_float_type(pc), isneg, str, Int(beg - base + 1), Int(pnt - base)), pnt
end
