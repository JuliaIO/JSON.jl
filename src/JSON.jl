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

function parse(io::AsyncStream)
    open_bracket = nothing
    close_bracket = nothing
    num_brackets_needed = 1

    # find the opening bracket type
    while open_bracket == nothing
        c = read(io, Char)
        if c == '{'
            open_bracket = '{'
            close_bracket = '}'
        elseif c == '['
            open_bracket = '['
            close_bracket = ']'
        end
    end

    obj = string(open_bracket)

    # read chunks at a time until we get a full object
    while true
        curr = readavailable(io)
        nb = length(curr)

        i = start(curr)
        while num_brackets_needed > 0 && !done(curr, i)
            c, i = next(curr, i)

            if c == open_bracket
                num_brackets_needed += 1
            elseif c == close_bracket
                num_brackets_needed -= 1
            end
        end

        obj = RopeString(obj, curr[1:i-1])

        if num_brackets_needed < 1
            write(io.buffer, curr[i:end])
            return parse(utf8(obj))
        end
    end
end

end
