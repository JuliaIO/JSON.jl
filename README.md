# JSON.jl
### Parsing and printing JSON in pure Julia.

[![Build Status](https://travis-ci.org/JuliaLang/JSON.jl.svg)](https://travis-ci.org/JuliaLang/JSON.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/2sfomjwl29k6y6oy)](https://ci.appveyor.com/project/staticfloat/json-jl)
[![codecov.io](http://codecov.io/github/JuliaLang/JSON.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaLang/JSON.jl?branch=master)

[![JSON](http://pkg.julialang.org/badges/JSON_0.3.svg)](http://pkg.julialang.org/?pkg=JSON&ver=0.3)
[![JSON](http://pkg.julialang.org/badges/JSON_0.4.svg)](http://pkg.julialang.org/?pkg=JSON&ver=0.4)

**Installation**: `julia> Pkg.add("JSON")`


## Basic Usage

```julia
import JSON

# JSON.parse - string or stream to Julia data structures
s = "{\"a_number\" : 5.0, \"an_array\" : [\"string\", 9]}"
j = JSON.parse(s)
#  Dict{AbstractString,Any} with 2 entries:
#    "an_array" => {"string",9}
#    "a_number" => 5.0

# JSON.json - Julia data structures to a string
JSON.json([2,3])
#  "[2,3]"
JSON.json(j)
#  "{\"an_array\":[\"string\",9],\"a_number\":5.0}"
```

## Documentation

```julia
JSON.print(io::IO, s::AbstractString)
JSON.print(io::IO, s::Union{Integer, AbstractFloat})
JSON.print(io::IO, n::Void)
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

Returns a compact JSON representation as an `AbstractString`.

```julia
JSON.parse(s::AbstractString; ordered=false)
JSON.parse(io::IO; ordered=false)
JSON.parsefile(filename::AbstractString; ordered=false, use_mmap=true)
```

Parses a JSON `AbstractString` or IO stream into a nested Array or Dict.

If `ordered=true` is specified, JSON objects are parsed into
`OrderedDicts`, which maintains the insertion order of the items in
the object. (*)

(*) Requires the `DataStructures.jl` package to be installed.
