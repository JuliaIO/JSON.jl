module JSON

export json # returns a compact JSON representation as a String

include("Parser.jl")

function parse(strng::String)
  Parser.parse(strng)
end

function print(io::IO, s::String)
    Base.print(io, '"')
    print_escaped(io, s, "\"")
    Base.print(io, '"')
end

print(io::IO, s::Union(Integer, FloatingPoint)) = Base.print(io, s)

print(io::IO, n::Nothing) = Base.print(io, "null")

print(io::IO, b::Bool) = Base.print(io, b ? "true" : "false")

function print(io::IO, a::Associative)
    Base.print(io, "{")
    first = true
    for (key, value) in a
        if first 
            first = false
        else
            Base.print(io, ",")
        end
        Base.print(io, "\"$key\":")
        JSON.print(io, value)
    end
    Base.print(io, "}") 
end

function print(io::IO, a::AbstractVector)
    Base.print(io, "[")
    if length(a) > 0
        for x in a[1:end-1]
            JSON.print(io, x)
            Base.print(io, ",")
        end
        JSON.print(io, a[end])
    end
    Base.print(io, "]")
end

function print(io::IO, a)
    Base.print(io, "{")

    range = typeof(a).names
    if length(range) > 0
        Base.print(io, "\"", range[1], "\":")
        JSON.print(io, a.(range[1]))

        for name in range[2:end]
            Base.print(io, ",")
            Base.print(io, "\"", name, "\":")
            JSON.print(io, a.(name))
        end
    end

    Base.print(io, "}")
end

function print{T}(io::IO, a::Array{T, 2})
    b = zeros(Any, size(a, 2))
    for j = 1:length(b)
        b[j] = a[:,j]
    end
    JSON.print(io, b)
end

# Default to printing to STDOUT
print{T}(a::T) = JSON.print(STDOUT, a)

json(a) = sprint(JSON.print, a)

function determine_bracket_type(io::IO)
    open_bracket = nothing
    close_bracket = nothing

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

    return (open_bracket, close_bracket)
end


###
# Consume a string (even if it is invalid), with ack to Douglas Crockford.
# On entry we must already have consumed the opening quotation double-quotation mark
# Add the characters of the string to obj
function consumeString(io::IO, obj::IOBuffer)
    c = '"'

    # When parsing for string values, we must look for " and \ characters.
    while (c = read(io, Char)) != '\0'
      if c == '"'
        write(obj, c)
        return
      end
      if c == '\\'
        write(obj, c)
        c = read(io, Char)
        if c == '\0'
       error("EOF while attempting to read a string")
        end
      end
      write(obj, c)
    end
    error("EOF while attempting to read a string")
end

function parse(io::IO)
    open_bracket, close_bracket = determine_bracket_type(io)
    num_brackets_needed = 1

    obj = IOBuffer()
    write(obj, open_bracket)

    while num_brackets_needed > 0
        c = read(io, Char)
        write(obj, c)

        if c == open_bracket
            num_brackets_needed += 1
        elseif c == close_bracket
            num_brackets_needed -= 1
        elseif c == '"'
            consumeString(io, obj)
        end
    end

    JSON.parse(takebuf_string(obj))
end

end
