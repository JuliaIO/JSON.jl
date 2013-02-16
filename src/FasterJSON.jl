
# Recklessly faster JSON parser.
module FasterJSON
  
  function _search(haystack, needle, _start)
    range = search(haystack, needle, _start)
    return (first(range), last(range))
  end
  
  function chomp_space(str, s, e)
    if !(s < e)
      return s
    end
    c = str[s]
    while c == ' ' || c == '\t' || c == '\n'
      s += 1
      c = str[s]
    end
    return s
  end
  
  function parse_array(str, s, e)
    # s = start of array (str[s:e] = "[...")
    s += 1 # Skip over the '['
    s = chomp_space(str, s, e)
    _array = Any[]
    # Quick check for empty array
    if str[s] == ']'
      return (_array, s + 1, e)
    end
    # Extract values from array
    while true
      # Extract value
      v, s, e = parse_value(str, s, e)
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
        error("Unexpected char: " * string(c))
      end
    end
    return (_array, s, e)
  end
  
  function parse_object(str, s, e)
    s += 1 # Skip over opening '{'
    
    obj = Dict{Any,Any}()
    # Quick check for empty object
    if str[s] == '}'
      return (obj, s + 1, e)
    end
    
    while true
      s = chomp_space(str, s, e)
      
      _key, s, e = parse_value(str, s, e)
      
      ss, se = _search(str, ':', s)
      # TODO: Error handling if it doesn't find the separator
      # Skip over separator
      s = se + 1
      _value, s, e = parse_value(str, s, e)
      # Assign into the dict
      obj[_key] = _value
      # Find the next pair or end of object
      s = chomp_space(str, s, e)
      c = str[s]
      if c == ','
        s += 1
        continue
      elseif c == '}'
        s += 1
        break
      else
        error("Unexpected char: " * str[s:s + 20])
      end
    end
    
    return(obj, s, e)
  end
  
  function parse_string(str, s, e)
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
    
    return (join(parts, ""), te + 1, e)
  end
  
  function parse_bool(str, s, e)
    # Looks like "true"
    if str[s] == 't' && str[s + 3] == 'e'
      return (true, s + 4, e)
    # Looks like "false"
    elseif str[s] == 'f' && str[s + 4] == 'e'
      return (false, s + 5, e)
    # Looks like "null"
    elseif str[s] == 'n' && str[s + 3] == 'l'
      return (nothing, s + 4, e)
    else
      error("Unexpected bool-like: " * str[s:s + 4])
    end
  end
  
  function parse_value(str, s, e)
    s = chomp_space(str, s, e)
    
    if s == e
      return (nothing, s, e)
    end
    
    ch = str[s]
    
    if ch == '"'
      return parse_string(str, s, e)
    elseif ch == '{'
      return parse_object(str, s, e)
    elseif (ch >= '0' && ch <= '9') || ch == '-'
      return parse_number(str, s, e)
    elseif ch == '['
      return parse_array(str, s, e)
    elseif ch == 'f' || ch == 't' || ch == 'n'
      return parse_bool(str, s, e)
    else
      error("Unexpected value: " * str[s:s + 20])
    end
  end
  
  # TODO: Speed up number parsing
  _separator = r"[^0-9.eE+-]"
  function parse_number(str, s, e)
    ss, se = _search(str, _separator, s)
    v = Base.parse(str[s:ss - 1])
    return (v, se, e)
  end
  
  function parse(_str::String)
    str = strip(_str)
    pos = 1
    len = endof(str)
    
    v, s, e = parse_value(str, pos, len)
    return v
  end
  
end
