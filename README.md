# JSON.jl
### Parsing and printing JSON in pure Julia.

[![Build Status](https://travis-ci.org/JuliaLang/JSON.jl.svg)](https://travis-ci.org/JuliaLang/JSON.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/2sfomjwl29k6y6oy)](https://ci.appveyor.com/project/staticfloat/json-jl)
[![Coverage Status](https://img.shields.io/coveralls/JuliaLang/JSON.jl.svg)](https://coveralls.io/r/JuliaLang/JSON.jl)
[![JSON](http://pkg.julialang.org/badges/JSON_release.svg)](http://pkg.julialang.org/?pkg=JSON&ver=release)

**Installation**: `julia> Pkg.add("JSON")`


## Basic Usage

```julia
import JSON

# JSON.parse - string or stream to Julia data structures
s = "{\"a_number\" : 5.0, \"an_array\" : [\"string\", 9]}"
j = JSON.parse(s)
#  Dict{String,Any} with 2 entries:
#    "an_array" => {"string",9}
#    "a_number" => 5.0

# JSON.json - Julia data structures to a string
JSON.json([2,3])
#  "[2,3]"
JSON.json(j)
#  "{\"an_array\":[\"string\",9],\"a_number\":5.0}"
```

### Macro Strings

`JSON` and `J` can be used to embed JSON data directly into source code:

```julia
basic_dict = JSON"""
{
  "a_number" : 5.0,
  "an_array" : ["string", 9]
}
"""
```


```julia
basic_dict = J"{'a_number' : 5.0, 'an_array' : ['string', 9]}"
```

Note that the shorter `@J_str` relies on the `single_quote` parsing behavior. 

## Documentation

```julia
JSON.print(io::IO, s::String)
JSON.print(io::IO, s::Union(Integer, FloatingPoint))
JSON.print(io::IO, n::Nothing)
JSON.print(io::IO, b::Bool)
JSON.print(io::IO, a::Associative)
JSON.print(io::IO, v::AbstractVector)
JSON.print{T, N}(io::IO, v::Array{T, N})
```

Writes a compact (no extra whitespace or identation) JSON representation
to the supplied IO.

```julia
json(a::Any)
```

Returns a compact JSON representation as a String.

```julia
JSON.parse(s::String; ordered=false, single_quote=false)
JSON.parse(io::IO; ordered=false, single_quote=false)
JSON.parsefile(filename::String; ordered=false, single_quote=false, use_mmap=true)
```

Parses a JSON String or IO stream into a nested Array or Dict.

If `ordered=true` is specified, JSON objects are parsed into
`OrderedDicts`, which maintains the insertion order of the items in
the object. (*)

Setting `single_quote` enables parsing on non-standard usage of single quote `'\''` for string values. 

(*) Requires the `DataStructures.jl` package to be installed.
