macro timeit(name, ex)
  quote
    #t = Inf
    #t = min(t, @elapsed $ex)
    
    # Let it do some optimizations
    for i=1:100
      @elapsed $ex
    end
    
    t = 0.0
    for i=1:1_000
      t += @elapsed $ex
    end
    println($name, "\t1,000 iter\t", t * 1000, " ms")
    
    t = 0.0
    for i=1:10_000
      t += @elapsed $ex
    end
    println($name, "\t10,000 iter\t", t * 1000, " ms")
    
    t = 0.0
    for i=1:100_000
      t += @elapsed $ex
    end
    println($name, "\t100,000 iter\t", t * 1000, " ms")
  end
end


escapes_dict = Dict{Char, Char}()
escapes_dict['"'] = '"'
escapes_dict['\\'] = '\\'
escapes_dict['/'] = '/'
escapes_dict['b'] = '\b'
escapes_dict['f'] = '\f'
escapes_dict['n'] = '\n'
escapes_dict['r'] = '\r'
escapes_dict['t'] = '\t'

function parse_with_dict(str::String)
  s = 1
  e = length(str)
  o = Array(Uint8, e)
  os = 1
  
  while s <= e
    c = str[s]
    if c == '\\'
      s += 1
      c = str[s]
      if c === 'u'
        # pass
      else
        o[os] = uint8(escapes_dict[c])
      end
    else
      o[os] = uint8(c)
    end
    s += 1
    os += 1
  end
  
  if os != s
    resize!(o, os - 1)
  end
  
  return utf8(o)
end

escapes_array = Array(Uint8, 256)
escapes_array[uint8('"' )] = uint8('"' )
escapes_array[uint8('\\')] = uint8('\\')
escapes_array[uint8('/' )] = uint8('/' )
escapes_array[uint8('b' )] = uint8('\b')
escapes_array[uint8('f' )] = uint8('\f')
escapes_array[uint8('n' )] = uint8('\n')
escapes_array[uint8('r' )] = uint8('\r')
escapes_array[uint8('t' )] = uint8('\t')

function parse_with_array(str::String)
  s = 1
  e = length(str)
  o = Array(Uint8, e)
  os = 1
  
  while s <= e
    c = str[s]
    if c == '\\'
      s += 1
      c = str[s]
      if c === 'u'
        # pass
      else
        o[os] = escapes_array[uint8(c)]
      end
    else
      o[os] = uint8(c)
    end
    s += 1
    os += 1
  end
  
  if os != s
    resize!(o, os - 1)
  end
  
  return utf8(o)
end

_dq = uint8('"' )
_bs = uint8('\\')
_fs = uint8('/' )
_b = uint8('\b')
_f = uint8('\f')
_n = uint8('\n')
_r = uint8('\r')
_t = uint8('\t')

function parse_with_condition(str::String)
  s = 1
  e = length(str)
  o = Array(Uint8, e)
  os = 1
  
  while s <= e
    c = str[s]
    if c == '\\'
      s += 1
      c = str[s]
      if c === 'u'
        # pass
      elseif c == '"'
        o[os] = _dq
      elseif c == '\\'
        o[os] = _bs
      elseif c == '/'
        o[os] = _fs
      elseif c == 'b'
        o[os] = _b
      elseif c == 'f'
        o[os] = _f
      elseif c == 'n'
        o[os] = _n
      elseif c == 'r'
        o[os] = _r
      elseif c == 't'
        o[os] = _t
      else
        error("Unrecognized escaped character: " * string(c))
      end
    else
      o[os] = uint8(c)
    end
    s += 1
    os += 1
  end
  
  if os != s
    resize!(o, os - 1)
  end
  
  return utf8(o)
end

test_json  = "test\\\\/\\\"\\b\\f\\n\\r\\ttest"
test_julia = "test\\/\"\b\f\n\r\ttest"

@timeit "dict\t" begin
  @assert parse_with_dict(test_json) == test_julia
end
println()
@timeit "array\t" begin
  @assert parse_with_array(test_json) == test_julia
end
println()
@timeit "condition" begin
  @assert parse_with_condition(test_json) == test_julia
end

# Output from testing on Feb 18 on 2012 MacBook Pro:
# 
# dict        1,000 iter    1.1386871337890625 ms
# dict        10,000 iter   19.232749938964844 ms
# dict        100,000 iter  115.24224281311035 ms
# 
# array       1,000 iter    0.8826255798339844 ms
# array       10,000 iter   8.373737335205078 ms
# array       100,000 iter  98.06418418884277 ms
# 
# condition   1,000 iter    0.7371902465820312 ms
# condition   10,000 iter   7.101535797119141 ms
# condition   100,000 iter  81.36272430419922 ms
