#JSON parsing and printing for Julia.
[![Build Status](https://travis-ci.org/JuliaLang/JSON.jl.png)](https://travis-ci.org/JuliaLang/JSON.jl)

##Installation

```julia
Pkg.add("JSON")
```

##Usage

```julia
using JSON

# parse json
JSON.parse("{\"a\":1}")
["a"=>1]
JSON.parse("{\"a\":[1,2]}")
["a"=>{1,2}]

JSON.parse("{\"a\"")
ERROR: Separator not found


# Dict to Json
json({"a"=>1})
"{\"a\":1}"
json({"a"=>[1,2]})

```

##The API

```julia
JSON.print(io::IO, s::String)
JSON.print(io::IO, s::Union(Integer, FloatingPoint))
JSON.print(io::IO, n::Nothing)
JSON.print(io::IO, b::Bool)
JSON.print(io::IO, a::Associative)
JSON.print(io::IO, v::AbstractVector)
JSON.print{T, N}(io::IO, v::Array{T, N})

Writes a compact (no extra whitespace or identation) JSON representation
to the supplied IO
```

```julia
json(a::Any)

Returns a compact JSON representation as a String
```

```julia
JSON.parse(s::String)
JSON.parse(io::IO)

Parses a JSON String into a nested Array or Dict
```
