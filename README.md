# JSON.jl

A Julia package for reading and writing JSON data.

[![Build Status](https://github.com/JuliaIO/JSON.jl/workflows/CI/badge.svg)](https://github.com/JuliaIO/JSON.jl/actions/workflows/CI.yml?query=branch%3Amaster)
[![codecov.io](http://codecov.io/github/JuliaIO/JSON.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaIO/JSON.jl?branch=master)

## Installation

Install JSON using the Julia package manager:
```julia
import Pkg
Pkg.add("JSON")
```

## Documentation

The [documentation](https://juliaio.github.io/JSON.jl/stable) includes extensive
guides and examples. It also has advice for migrating to JSON.jl v1.0 from
JSON.jl v0.21 or JSON3.jl.

## Basic Usage

```julia
import JSON

# JSON.parse - JSON to Julia
json = """{"a": 1, "b": null, "c": [1, 2, 3]}"""

# parse into default Julia types
j = JSON.parse(json)
# JSON.Object{String, Any} with 3 entries:
#   "a" => 1
#   "b" => nothing
#   "c" => Any[1, 2, 3]

struct MyType
    a::Int
    b::Union{Nothing, String}
    c::Vector{Int}
end

# parse into a custom type
j = JSON.parse(json, MyType)
# MyType(1, nothing, [1, 2, 3])

# parse into existing container
dict = Dict{String, Any}()
JSON.parse!(json, dict)

# JSON.parsefile - JSON file to Julia
x = JSON.parsefile("test.json")

# JSON.json - Julia to JSON
JSON.json([2,3])
#  "[2,3]"

# Julia struct to JSON, pretty printed, written to IO (stdout)
JSON.json(stdout, j; pretty=true)
# {
#     "a": 1,
#     "b": null,
#     "c": [
#         1,
#         2,
#         3
#     ]
# }

# test that JSON is valid
JSON.isvalidjson(json)

# Write JSON to file
JSON.json("test.json", j)

# Download json data and parse into a DataFrame
using HTTP, JSON, Tables, DataFrames
resp = HTTP.get("https://raw.githubusercontent.com/altair-viz/vega_datasets/master/vega_datasets/_data/wheat.json")
# null=missing will read json `null` as Julia `missing; `allownan=true` parses all numbers as Float64
df = DataFrame(Tables.dictrowtable(JSON.parse(resp.body; null=missing, allownan=true)))
```

## Vendor Directory

This package includes a `vendor/` directory containing a simplified,
no-dependency JSON parser (`JSONX`) that can be vendored (copied) into other
projects. See the [vendor README](vendor/README.md) for details.

## Contributing and Questions

Contributions are very welcome, as are feature requests and suggestions. Please
open an [issue](https://github.com/JuliaIO/JSON.jl/issues) if you encounter any
problems or would just like to ask a question.
