
# Recklessly faster JSON parser.
module Faster
  
  # Types it may encounter
  TYPES = Union(Dict, Array, String, Number, Bool, Nothing)
  # Types it may encounter as object keys
  KEY_TYPES = Union(String)
  
  export parse
  
  # TRACING
  
  type Trace
    name::String
    depth::Int64
    start::Float64
    stop::Float64
    data::Union(String, Nothing)
    
    Trace(name::String, depth::Int64, start::Float64) =
      new(name, depth, start, 0.0, nothing)
  end
  
  type Tracer
    do_trace::Bool
    stack::Vector{Trace}
    current_depth::Int64
    
    Tracer(trace) = new(trace, Trace[], 0)
  end
  
  function start_trace(trace::Bool)
    return Tracer(trace)
  end
  
  function trace_in(tracer::Tracer, name::String)
    if !tracer.do_trace; return; end
    # Create and add trace
    _trace = Trace(name, tracer.current_depth, time())
    push!(tracer.stack, _trace)
    tracer.current_depth += 1 # Increase depth
    # Return the position (tail index) of the trace
    return endof(tracer.stack) # ti (trace index)
  end
  
  function trace_out(tracer::Tracer, ti::Int64, data::Union(String, Nothing))
    if !tracer.do_trace; return; end
    # Get the tracer at the index ti and update its values.
    _trace = tracer.stack[ti]
    _trace.stop = time() 
    _trace.data = data
    tracer.current_depth -= 1 # Decrease depth
  end
  trace_out(tracer, ti) = trace_out(tracer, ti, nothing)
  # Called when trace_in returns ti as nothing.
  trace_out(tracer::Tracer, ti::Nothing, data::Any) = @thunk nothing
  
  # Format a float as 1.234 (using by print_trace).
  function format(e::Float64)
    s = int(floor(e))
    msec = int((e - floor(e)) * 1000)
    return string(s) * "." * lpad(string(msec), 3, "0")
  end
  
  function print_trace(tracer::Tracer)
    # println("tracing: " * format(tracer.tracing * 1000) * "ms")
    for trace = tracer.stack
      print_trace(trace)
    end
  end
  function print_trace(trace::Trace)
    println(
      ("|   " ^ trace.depth) *
      trace.name * ": " *
      format((trace.stop - trace.start) * 1000) * "ms" *
      ((trace.data != nothing) ? " (" * repr(trace.data) * ")" : "")
    )
  end
  
  # UTILITIES
  
  function _search(haystack::String, needle::Union(String, Regex, Char), _start::Int64)
    range = search(haystack, needle, _start)
    return (first(range), last(range))
  end
  
  # Eat up spaces starting at s.
  function chomp_space(str::String, s::Int64, e::Int64)
    if !(s < e)
      return s
    end
    c = str[s]
    while (c == ' ' || c == '\t' || c == '\n') && s < e
      s += 1
      c = str[s]
    end
    return s
  end
  
  # Used for line counts
  function _count_before(haystack::String, needle::Char, _end::Int64)
    count = 0
    i = 1
    while i < _end
      if haystack[i] == needle
        count += 1
      end
      i += 1
    end
    return count
  end
  
  # Prints an error message with an indicator to the source
  function _error(message::String, str::String, s::Int64, e::Int64)
    lines = _count_before(str, '\n', s)
    # Replace all special multi-line/multi-space characters with a space.
    strnl = replace(str, r"[\b\f\n\r\t\s]", " ")
    # Left index
    li = (s > 20) ? s - 9 : 1
    # Right index
    ri = s + 20
    if ri > e
      ri = e
    end
    error(
      message *
      "\nLine: " * string(lines) *
      "\nAround: ..." * strnl[li:ri] * "..." *
      "\n           " * (" " ^ (s - li)) * "^\n"
    )
  end
  
  # PARSING
  
  function parse_array(str::String, s::Int64, e::Int64, tracer::Tracer)
    _ti = trace_in(tracer, "array")
    s += 1 # Skip over the '['
    _array = TYPES[]
    s = chomp_space(str, s, e)
    # Check for empty array
    if str[s] == ']'
      trace_out(tracer, _ti)
      return (_array, s + 1, e)
    end
    # Extract values from array
    while true
      # Extract value
      v, s, e = parse_value(str, s, e, tracer)
      push!(_array, v)
      # Eat up trailing whitespace
      s = chomp_space(str, s, e)
      c = str[s]
      if c == ','
        s += 1
        continue
      elseif c == ']'
        s += 1
        break
      else
        _error(
          "Unexpected char: " * string(c),
          str, s, e
        )
      end
    end
    trace_out(tracer, _ti)
    return (_array, s, e)
  end
  
  function parse_object(str::String, s::Int64, e::Int64, tracer::Tracer)
    _ti = trace_in(tracer, "object")
    s += 1 # Skip over opening '{'
    obj = Dict{KEY_TYPES,TYPES}()
    # Eat up some space
    s = chomp_space(str, s, e)
    # Check for empty object
    if str[s] == '}'
      trace_out(tracer, _ti)
      return (obj, s + 1, e)
    end
    while true
      s = chomp_space(str, s, e)
      # Key
      _key, s, e = parse_string(str, s, e, tracer)
      # Separator
      ss, se = _search(str, ':', s)
      # TODO: Error handling if it doesn't find the separator
      if ss < 1
        _error( "Separator not found ", str, s, e)
      end
      # Skip over separator
      s = se + 1
      # Value
      _value, s, e = parse_value(str, s, e, tracer)
      obj[_key] = _value # Building object
      
      s = chomp_space(str, s, e)
      # Find the next pair or end of object
      c = str[s]
      if c == ','
        s += 1
        continue
      elseif c == '}'
        s += 1
        break
      else
        _error("Unexpected char: " * string(c), str, s, e)
      end
    end
    trace_out(tracer, _ti)
    return (obj, s, e)
  end
  
  # Special characters for parse_string
  const _dq = uint8('"' )
  const _bs = uint8('\\')
  const _fs = uint8('/' )
  const _b  = uint8('\b')
  const _f  = uint8('\f')
  const _n  = uint8('\n')
  const _r  = uint8('\r')
  const _t  = uint8('\t')
  # TODO: Try to find ways to improve the performance of this (currently one
  #       of the slowest parsing methods).
  function parse_string(str::String, s::Int64, e::Int64, tracer::Tracer)
    _ti = trace_in(tracer, "string")
    if str[s] != '"'
      _error("Missing opening string char", str, s, e)
    end
    s = nextind(str, s) # Skip over opening '"'
    
    b = IOBuffer()
    
    found_end = false
    while s <= e
      c = str[s]
      if c == '\\'
        s = nextind(str, s)
        c = str[s]
        if c == 'u'
          # Unicode escape
          # Get the string
          u = unescape_string(str[s - 1:s + 4])
          # Get the uint8s for the string
          d = bytestring(u).data
          # append!(o, d)
          write(b, bytestring(u))
          # Skip over those next four characters
          [s = nextind(str, s) for _ = 1:4]
        elseif c == '"'
          write(b, '"')
        elseif c == '\\'
          write(b, '\\')
        elseif c == '/'
          write(b, '/')
        elseif c == 'b'
          write(b, '\b')
        elseif c == 'f'
          write(b, '\f')
        elseif c == 'n'
          write(b, '\n')
        elseif c == 'r'
          write(b, '\r')
        elseif c == 't'
          write(b, '\t')
        else
          _error("Unrecognized escaped character: " * string(c), str, s, e)
        end
      elseif c == '"'
        found_end = true
        s = nextind(str, s)
        break
      else
        write(b, c)
      end
      s = nextind(str, s)
    end
    
    if !found_end
      _error("Unterminated string", str, s, e)
    end
    
    r = takebuf_string(b)
    trace_out(tracer, _ti)
    return (r, s, e)
  end
  
  # NOTE: SERIOUS PERFORMANCE IMPROVEMENTS LURKING
  # new parse_string (above): 0.313, 0.312, 0.310 ms
  # parse_string_old (below): 0.693, 0.687, 0.692 ms
  
  function parse_string_old(str::String, s::Int64, e::Int64, tracer::Tracer)
    _ti = trace_in(tracer, "string")
    if str[s] != '"'
      _error("Missing opening string char", str, s, e)
    end
    s += 1 # Skip over opening '"'
    
    # Search for a terminating '"'
    ts, te = _search(str, '"', s)
    # Search for an escape character
    es, ee = _search(str, "\\", s)
    
    parts = String[]
    # If there are escape characters before the terminator.
    if es < ts
      while es >= s
        push!(parts, str[s:es - 1])
        
        s = ee + 1
        c = str[s]
        
        if c == 'u'
          # Unicode escape
          push!(parts, unescape_string(str[s - 1:s + 4]))
          s += 4 # Skip over those next four characters
        elseif c == '"'
          s = __dq
        elseif c == '\\'
          push!(parts, __bs)
        elseif c == '/'
          push!(parts, __fs)
        elseif c == 'b'
          push!(parts, __b )
        elseif c == 'f'
          push!(parts, __f )
        elseif c == 'n'
          push!(parts, __n )
        elseif c == 'r'
          push!(parts, __r )
        elseif c == 't'
          push!(parts, __t )
        else
          # push!(parts, string(c))
          _error("Unrecognized escaped character: " * string(c), str, s, e)
        end
        
        s += 1 # Move past the character
        # Find the next escape
        es, ee = _search(str, "\\", s)
      end
      ts, te = _search(str, '"', s)
    else
      # pass
    end
    if ts < 1
      _error("Missing closing string char", str, s, e)
    end
    # Add any remaining content up to the terminator
    push!(parts, str[s:ts - 1])
    trace_out(tracer, _ti)
    return (join(parts, ""), te + 1, e)
  end
  
  function parse_simple(str::String, s::Int64, e::Int64, tracer::Tracer)
    _ti = trace_in(tracer, "simple")
    c = str[s]
    if c == 't' && str[s + 3] == 'e'
      # Looks like "true"
      ret = (true, s + 4, e)
    elseif c == 'f' && str[s + 4] == 'e'
      # Looks like "false"
      ret = (false, s + 5, e)
    elseif c == 'n' && str[s + 3] == 'l'
      # Looks like "null"
      ret = (nothing, s + 4, e)
    else
      _error("Unknown simple: " * string(c), str, s, e)
    end
    trace_out(tracer, _ti)
    return ret
  end
  
  function parse_value(str::String, s::Int64, e::Int64, tracer::Tracer)
    #_ti = trace_in(tracer, "value")
    s = chomp_space(str, s, e)
    # Nothing left
    if s == e
      return (nothing, s, e)
    end
    
    ch = str[s]
    if ch == '"'
      ret = parse_string(str, s, e, tracer)
    elseif ch == '{'
      ret = parse_object(str, s, e, tracer)
    elseif (ch >= '0' && ch <= '9') || ch == '-'
      ret = parse_number(str, s, e, tracer)
    elseif ch == '['
      ret = parse_array(str, s, e, tracer)
    elseif ch == 'f' || ch == 't' || ch == 'n'
      ret = parse_simple(str, s, e, tracer)
    else
      _error("Unknown value", str, s, e)
    end
    #trace_out(tracer, _ti)
    return ret
  end
  
  function parse_number(str::String, s::Int64, e::Int64, tracer::Tracer)
    _ti = trace_in(tracer, "number")
    
    p = s
    # Look for negative
    if str[p] == '-'
      p += 1
    end
    # Look for number
    if str[p] == '0'
      p += 1
      if str[p] == '.'
        is_decimal = true
        p += 1
      else
        is_decimal = false
      end
    elseif str[p] > '0' && str[p] <= '9'
      p += 1
      # Match more digits
      while str[p] >= '0' && str[p] <= '9'
        p += 1
      end
      if str[p] == '.'
        p += 1
        is_decimal = true
      else
        is_decimal = false
      end
    else
      _error(
        "Unrecognized number",
        str, p, e
      )
    end
    if is_decimal
      # Match digits after decimal
      while str[p] >= '0' && str[p] <= '9'
        p += 1
      end
    else
      # Not decimal
    end
    if str[p] == 'E' || str[p] == 'e'
      p += 1
      # Exponent sign
      if str[p] == '-' || str[p] == '+'
        p += 1
      end
      # Exponent digits
      while str[p] >= '0' && str[p] <= '9'
        p += 1
      end
    end
    
    vs = str[s:p - 1]
    if is_decimal
      v = parse_float(vs)
    else
      v = parse_int(vs)
    end
    
    trace_out(tracer, _ti, vs)
    s = p
    return (v, s, e)
  end
  
  function parse(str::String)
    pos::Int64 = 1
    len::Int64 = endof(str)
    # Don't actually trace
    tracer = start_trace(false)
    
    if len < 1; return nothing; end
    
    v, s, e = parse_value(str, pos, len, tracer)
    return v
  end
  
  function parse(str::String, trace::Bool)
    pos::Int64 = 1
    len::Int64 = endof(str)
    tracer = start_trace(trace)
    
    if len < 1; return nothing; end
    
    v, s, e = parse_value(str, pos, len, tracer)
    return v, tracer
  end
  
end#module FasterJSON
