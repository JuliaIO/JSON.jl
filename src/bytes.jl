# The following bytes have significant meaning in JSON
const BACKSPACE      = UInt8('\b')
const TAB            = UInt8('\t')
const NEWLINE        = UInt8('\n')
const FORM_FEED      = UInt8('\f')
const RETURN         = UInt8('\r')
const SPACE          = UInt8(' ')
const STRING_DELIM   = UInt8('"')
const PLUS_SIGN      = UInt8('+')
const DELIMITER      = UInt8(',')
const MINUS_SIGN     = UInt8('-')
const DECIMAL_POINT  = UInt8('.')
const SOLIDUS        = UInt8('/')
const DIGIT_ZERO     = UInt8('0')
const DIGIT_NINE     = UInt8('9')
const SEPARATOR      = UInt8(':')
const LATIN_UPPER_A  = UInt8('A')
const LATIN_UPPER_E  = UInt8('E')
const LATIN_UPPER_F  = UInt8('F')
const ARRAY_BEGIN    = UInt8('[')
const BACKSLASH      = UInt8('\\')
const ARRAY_END      = UInt8(']')
const LATIN_A        = UInt8('a')
const LATIN_B        = UInt8('b')
const LATIN_E        = UInt8('e')
const LATIN_F        = UInt8('f')
const LATIN_L        = UInt8('l')
const LATIN_N        = UInt8('n')
const LATIN_R        = UInt8('r')
const LATIN_S        = UInt8('s')
const LATIN_T        = UInt8('t')
const LATIN_U        = UInt8('u')
const OBJECT_BEGIN   = UInt8('{')
const OBJECT_END     = UInt8('}')

const CONTROL_ESCAPE = "bfnrt"
const CONTROL_CHARS  = "\b\f\n\r\t"

function create_tab()
    tab = zeros(UInt8, 't' - 'b' + 1)
    for i = 1:5
        tab[CONTROL_ESCAPE[i]%UInt8-LATIN_A] = CONTROL_CHARS[i]%UInt8
    end
    tab
end

const ESCAPE_TAB = create_tab()

export BACKSPACE, TAB, NEWLINE, FORM_FEED, RETURN, SPACE, STRING_DELIM,
       PLUS_SIGN, DELIMITER, MINUS_SIGN, DECIMAL_POINT, SOLIDUS, DIGIT_ZERO,
       DIGIT_NINE, SEPARATOR, LATIN_UPPER_A, LATIN_UPPER_E, LATIN_UPPER_F,
       ARRAY_BEGIN, BACKSLASH, ARRAY_END, LATIN_A, LATIN_B, LATIN_E, LATIN_F,
       LATIN_L, LATIN_N, LATIN_R, LATIN_S, LATIN_T, LATIN_U, OBJECT_BEGIN,
       OBJECT_END, ESCAPE_TAB
