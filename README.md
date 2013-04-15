#JSON parsing and printing for Julia. 
[![Build Status](https://travis-ci.org/aviks/JSON.jl.png)](https://travis-ci.org/aviks/JSON.jl)

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
print_to_json(io::IO, v::AbstractVector)

Writes a compact (no extra whitespace or identation) JSON representation
to the supplied IO
```

```julia
to_json(a::Any)

Returns a compact JSON representation as a String
```

```julia
parse(s::String)
parse(io::IO)

Parses a JSON String into a nested Array or Dict
```
