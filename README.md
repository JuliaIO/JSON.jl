#JSON parsing and printing for Julia.

##Installation

```julia
Pkg.add("JSON")
```

##Usage

```julia
require("JSON")
JSON.parse(s)
JSON.to_json(a)
```

##The API

```julia
print_to_json(io::IO, s::String)
print_to_json(io::IO, s::Union(Integer, FloatingPoint))
print_to_json(io::IO, n::Nothing)
print_to_json(io::IO, b::Bool)
print_to_json(io::IO, a::Associative)
print_to_json(io::IO, v::Vector)

Writes a compact (no extra whitespace or identation) JSON representation
to the supplied IOStream
```

```julia
to_json(a::Any)

Returns a compact JSON representation as a String
```

```julia
parse(s::String)

Parses a JSON String into a nested Array or Dict
```

## FasterJSON

Prototype/experimental JSON parser loosely based off of [Douglas Crockford's reference implementation](https://github.com/douglascrockford/JSON-js/blob/master/json_parse.js). Achieves ~2x the speed of the main JSON module's parser, however it is a bit more reckless. Caution is advised.

```julia
FasterJSON.parse(str::String)

Parses a JSON String. Will return any of the FasterJSON.TYPES.
```

### Performance

From 2.2 GHz Core i7 2012 Early 2011 MacBook Pro running Ruby 1.8.7 and Julia 0.1.0+109977662.r2426. Run `julia test/perf.jl` and `ruby test/perf.rb` to get your own results (for Ruby you will need the `json`, `json_pure`, and `yajl` gems).

```
Julia Performance (msecs)
JSON        3.901
FasterJSON  0.964

Ruby Performance (msecs)
JSON::Ext   0.107
JSON::Pure  3.025
Yajl        0.14
```
