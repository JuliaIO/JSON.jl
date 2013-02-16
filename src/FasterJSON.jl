
# Recklessly faster JSON parser.
module FasterJSON
  
  # Types it may encounter
  TYPES = Union(Dict, Array, String, Number, Bool, Nothing)
  # Types it may encounter as object keys
  KEY_TYPES = Union(String, Number, Bool)
  
  export parse
  
  function _search(haystack::String, needle::Union(String, Regex, Char), _start::Int64)
    range = search(haystack, needle, _start)
    return (first(range), last(range))
  end
  
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
    trace::Bool
    stack::Vector{Trace}
    current_depth::Int64
    tracing::Float64
    
    Tracer(trace) = new(trace, Trace[], 0, 0.0)
  end
  
  function start_trace(trace::Bool)
    return Tracer(trace)
  end
  
  function trace_in(tracer::Tracer, name::String)
    if !tracer.trace; return; end
    
    _trace = Trace(name, tracer.current_depth, time())
    push!(tracer.stack, _trace)
    
    tracer.current_depth += 1
    
    return endof(tracer.stack) # ti (trace index)
  end
  
  function trace_out(tracer::Tracer, ti::Int64, data::Union(String, Nothing))
    if !tracer.trace; return; end
    
    _start = time()
    
    _trace = tracer.stack[ti]
    _trace.stop = time()
    _trace.data = data
    
    tracer.current_depth -= 1
    
    tracer.tracing += (time() - _start)
  end
  trace_out(tracer, ti) = trace_out(tracer, ti, nothing)
  trace_out(tracer::Tracer, ti::Nothing, data::Any) = @thunk nothing
  
  function format(e::Float64)
    s = int(floor(e))
    msec = int((e - floor(e)) * 1000)
    return string(s) * "." * lpad(string(msec), 3, "0")
  end
  
  function print_trace(tracer::Tracer)
    println("tracing: " * format(tracer.tracing * 1000) * "ms")
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
  
  function parse_array(str::String, s::Int64, e::Int64, tracer::Tracer)
    _ti = trace_in(tracer, "array")
    
    # s = start of array (str[s:e] = "[...")
    s += 1 # Skip over the '['
    
    _array = TYPES[]
    
    s = chomp_space(str, s, e)
    # Quick check for empty array
    if str[s] == ']'
      trace_out(tracer, _ti)
      return (_array, s + 1, e)
    end
    # Extract values from array
    cont = true
    while cont
      # Extract value
      v, s, e = parse_value(str, s, e, tracer)
      push!(_array, v)
      # Eat up trailing whitespace
      s = chomp_space(str, s, e)
      c = str[s]
      if c == ','
        s += 1
        #cont = true
      elseif c == ']'
        s += 1
        cont = false
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
    # Quick check for empty object
    if str[s] == '}'
      trace_out(tracer, _ti)
      return (obj, s + 1, e)
    end
    
    cont = true
    while cont
      s = chomp_space(str, s, e)
      
      # TODO: Make this only look for KEY_TYPES.
      _key, s, e = parse_value(str, s, e, tracer)
      
      ss, se = _search(str, ':', s)
      # TODO: Error handling if it doesn't find the separator
      if ss < 1
        _error(
          "Separator not found ",
          str, s, e
        )
      end
      # Skip over separator
      s = se + 1
      _value, s, e = parse_value(str, s, e, tracer)
      # Assign into the dict
      obj[_key] = _value
      # Find the next pair or end of object
      s = chomp_space(str, s, e)
      c = str[s]
      if c == ','
        s += 1
        #cont = true
      elseif c == '}'
        s += 1
        cont = false
      else
        _error(
          "Unexpected char: " * string(c),
          str, s, e
        )
      end
    end
    
    trace_out(tracer, _ti)
    
    return (obj, s, e)
  end
  
  # TODO: Try to find ways to improve the performance of this (currently one
  #       of the slowest parsing methods).
  function parse_string(str::String, s::Int64, e::Int64, tracer::Tracer)
    _ti = trace_in(tracer, "string")
    
    s += 1 # Skip over opening '"'
    
    ts, te = _search(str, '"', s)
    es, ee = _search(str, "\\", s)
    
    parts = String[]
    
    if es < ts
      while es >= s
        push!(parts, str[s:es - 1])
        
        s = ee + 1
        c = str[s]
        # Unicode escape
        if c == 'u'
          #show(str[s - 1:s + 4]);println()
          push!(parts, unescape_string(str[s - 1:s + 4]))
          s += 4 # Skip over those next four characters
        else
          push!(parts, string(c))
        end
        s += 1 # Move past the character
        # Find the next escape
        es, ee = _search(str, "\\", s)
      end
      ts, te = _search(str, '"', s)
    else
      # pass
    end
    
    push!(parts, str[s:ts - 1])
    
    trace_out(tracer, _ti)
    return (join(parts, ""), te + 1, e)
  end
  
  function parse_simple(str::String, s::Int64, e::Int64, tracer::Tracer)
    _ti = trace_in(tracer, "simple")
    
    # Looks like "true"
    c = str[s]
    if c == 't' && str[s + 3] == 'e'
      ret = (true, s + 4, e)
    # Looks like "false"
    elseif c == 'f' && str[s + 4] == 'e'
      ret = (false, s + 5, e)
    # Looks like "null"
    elseif c == 'n' && str[s + 3] == 'l'
      ret = (nothing, s + 4, e)
    else
      _error(
        "Unknown simple: " * string(c),
        str, s, e
      )
    end
    
    trace_out(tracer, _ti)
    return ret
  end
  
  function parse_value(str::String, s::Int64, e::Int64, tracer::Tracer)
    #_ti = trace_in(tracer, "value")
    
    s = chomp_space(str, s, e)
    
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
      _error(
        "Unknown value",
        str, s, e
      )
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
    tracer = start_trace(false)
    
    if len < 1
      return nothing
    end
    
    v, s, e = parse_value(str, pos, len, tracer)
    return v
  end
  
  function parse(str::String, trace::Bool)
    pos::Int64 = 1
    len::Int64 = endof(str)
    tracer = start_trace(trace)
    
    if len < 1
      return nothing
    end
    
    v, s, e = parse_value(str, pos, len, tracer)
    return v, tracer
  end
  
end



