module JSON

export parse,
       print_to_json, # Prints a compact (no extra whitespace or identation)
                      # JSON representation
       to_json # Gives a compact JSON representation as a String

include("Parser.jl")
function parse(strng::String)
  Parser.parse(strng)
end

print_to_json(io::IO, s::String) = print_quoted(io, s)

print_to_json(io::IO, s::Union(Integer, FloatingPoint)) = print(io, s)

print_to_json(io::IO, n::Nothing) = print(io, "null")

print_to_json(io::IO, b::Bool) = print(io, b ? "true" : "false")

function print_to_json(io::IO, a::Associative)
    print(io, "{")
    first = true
    for (key, value) in a
        if first 
            first = false
        else
            print(io, ",")
        end
        print(io, "\"$key\":")
        print_to_json(io, value)
    end
    print(io, "}") 
end

function print_to_json(io::IO, a::AbstractVector)
    print(io, "[")
    if length(a) > 0
        for x in a[1:end-1]
            print_to_json(io, x)
            print(io, ",")
        end
        print_to_json(io, a[end])
    end
    print(io, "]")
end

function print_to_json(io::IO, a)
    print(io, "{")

    range = typeof(a).names
    if length(range) > 0
        print(io, "\"", range[1], "\":")
        print_to_json(io, a.(range[1]))

        for name in range[2:end]
            print(io, ",")
            print(io, "\"", name, "\":")
            print_to_json(io, a.(name))
        end
    end

    print(io, "}")
end

# Default to printing to STDOUT
print_to_json{T}(a::T) = print_to_json(OUTPUT_STREAM, a)

to_json(a) = sprint(print_to_json, a)

end
