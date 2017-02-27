module TestSerializer

using JSON
using Base.Test
using Compat

# to define a new serialization behaviour, import these first
import JSON.Serializations: CommonSerialization, StandardSerialization
import JSON: StructuralContext

# those names are long so we can define some type aliases
const CS = CommonSerialization
const SC = StructuralContext

# for test harness purposes
function sprint_kwarg(f, args...; kwargs...)
    b = IOBuffer()
    f(b, args...; kwargs...)
    String(take!(b))
end

# issue #168: Print NaN and Inf as Julia would
immutable NaNSerialization <: CS end
JSON.show_json(io::SC, ::NaNSerialization, f::AbstractFloat) =
    Base.print(io, f)

@test sprint(JSON.show_json, NaNSerialization(), [NaN, Inf, -Inf, 0.0]) ==
    "[NaN,Inf,-Inf,0.0]"

@test sprint_kwarg(
    JSON.show_json,
    NaNSerialization(),
    [NaN, Inf, -Inf, 0.0];
    indent=4
) == """
[
    NaN,
    Inf,
    -Inf,
    0.0
]
"""

# issue #170: Print JavaScript functions directly
immutable JSSerialization <: CS end
immutable JSFunction
    data::Compat.UTF8String
end

function JSON.show_json(io::SC, ::JSSerialization, f::JSFunction)
    first = true
    for line in split(f.data, '\n')
        if !first
            JSON.indent(io)
        end
        first = false
        Base.print(io, line)
    end
end

@test sprint_kwarg(JSON.show_json, JSSerialization(), Any[
    1,
    2,
    JSFunction("function test() {\n  return 1;\n}")
]; indent=2) == """
[
  1,
  2,
  function test() {
    return 1;
  }
]
"""

# test serializing a type without any fields
immutable SingletonType end
@test_throws ErrorException json(SingletonType())

# test printing to STDOUT
let filename = tempname()
    open(filename, "w") do f
        redirect_stdout(f) do
            JSON.print(Any[1, 2, 3.0])
        end
    end
    @test readstring(filename) == "[1,2,3.0]"
    rm(filename)
end

end
