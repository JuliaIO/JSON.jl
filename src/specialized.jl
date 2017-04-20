# Specialized functions for increased performance when JSON is in-memory
using Compat: StringVector

function parse_string(ps::MemoryParserState)
    # "Dry Run": find length of string so we can allocate the right amount of
    # memory from the start. Does not do full error checking.
    fastpath, len = predict_string(ps)

    # Now read the string itself
    b = StringVector(len)

    # Fast path occurs when the string has no escaped characters. This is quite
    # often the case in real-world data, especially when keys are short strings.
    # We can just copy the data from the buffer in this case.
    if fastpath
        s = ps.s
        unsafe_copy!(b, 1, ps.utf8data, s + 1, len)
        ps.s = s + len + 2
    else
        parse_string(ps, b)
    end

    Compat.UTF8String(b)
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
function predict_string(ps::MemoryParserState)
    e = endof(ps.utf8data)
    fastpath = true  # true if no escapes in this string, so it can be copied
    len = 0          # the number of UTF8 bytes the string contains

    s = ps.s + 1     # skip past opening string character "
    @inbounds while s <= e
        c = ps.utf8data[s]
        if c == BACKSLASH
            fastpath = false
            (s += 1) > e && break
            if ps.utf8data[s] == LATIN_U  # Unicode escape
                t = ps.s
                ps.s = s + 1
                len += sizeof(string(read_unicode_escape!(ps)))
                s = ps.s
                ps.s = t
                continue
            end
        elseif c == STRING_DELIM
            return fastpath, len
        elseif c < SPACE
            ps.s = s
            _error(E_BAD_CONTROL, ps)
        end
        len += 1
        s += 1
    end

    ps.s = s
    _error(E_UNEXPECTED_EOF, ps)
end

"""
Parse the string starting at the parser state’s current location into the given
pre-sized buffer. The only correctness checking is for escape sequences, so the
passed-in buffer must exactly represent the amount of space needed for parsing.
"""
function parse_string(ps::MemoryParserState, b)
    s = ps.s
    e = endof(ps.utf8data)
    i = 0  # number of characters copied

    s += 1  # skip past opening string character "
    len = length(b)
    @inbounds while i < len
        c = ps.utf8data[s]
        if c == BACKSLASH
            s += 1
            s > e && break
            c = ps.utf8data[s]
            if c == LATIN_U  # Unicode escape
                ps.s = s + 1
                for c in Vector{UInt8}(string(read_unicode_escape!(ps)))
                    i += 1
                    b[i] = c
                end
                s = ps.s
                continue
            else
                c = get(ESCAPES, c, 0x00)
                if c == 0x00
                    ps.s = s
                    _error(E_BAD_ESCAPE, ps)
                end
            end
        end

        # UTF8-encoded non-ascii characters will be copied verbatim, which is
        # the desired behaviour
        i += 1
        b[i] = c
        s += 1
    end

    # don't worry about non-termination or other edge cases; those should have
    # been caught in the dry run.
    ps.s = s + 1
    b
end

function parse_number(ps::MemoryParserState)
    s = p = ps.s
    e = endof(ps.utf8data)
    isint = true

    # Determine the end of the floating point by skipping past ASCII values
    # 0-9, +, -, e, E, and .
    while p ≤ e
        @inbounds c = ps.utf8data[p]
        if isjsondigit(c) || MINUS_SIGN == c  # no-op
        elseif PLUS_SIGN == c || LATIN_E == c || LATIN_UPPER_E == c ||
                DECIMAL_POINT == c
            isint = false
        else
            break
        end
        p += 1
    end
    ps.s = p

    number_from_bytes(ps, isint, ps.utf8data, s, p - 1)
end
