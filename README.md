#JSON parsing and printing for Julia.
[![Build Status](https://travis-ci.org/JuliaLang/JSON.jl.png)](https://travis-ci.org/JuliaLang/JSON.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/2sfomjwl29k6y6oy)](https://ci.appveyor.com/project/staticfloat/json-jl)
[![Coverage Status](https://img.shields.io/coveralls/JuliaLang/JSON.jl.svg)](https://coveralls.io/r/JuliaLang/JSON.jl)

##Installation

```julia
Pkg.add("JSON")
```

##Usage

```julia
using JSON
JSON.parse(s)
json(a)
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
JSON.parse(s::String; ordered=false)
JSON.parse(io::IO; ordered=false)
JSON.parsefile(filename::String; ordered=false, use_mmap=true)

Parses a JSON String or IO stream into a nested Array or Dict.

If `ordered=true` is specified, JSON objects are parsed into
`OrderedDicts`, which maintains the insertion order of the items in
the object. (*)

(*) Requires the `DataStructures.jl` package to be installed.

```
