module JSON

export json # returns a compact JSON representation as a String

include("Parser.jl")

import .Parser.parse

function print_escaped(io, s::String)
    i = start(s)
    while !done(s,i)
        c, j = next(s,i)
        c == '\\'       ? Base.print(io, "\\\\") :
        c == '"'        ? Base.print(io, "\\\"") :
        8 <= c <= 10    ? Base.print(io, '\\', "btn"[c-7]) :
        c == '\f'       ? Base.print(io, "\\f") :
        c == '\r'       ? Base.print(io, "\\r") :
        isprint(c)      ? Base.print(io, c) :
        c <= '\x7f'     ? Base.print(io, "\\u", hex(c, 4)) :
                          Base.print(io, c) #JSON is UTF8 encoded
        i = j
    end
end

function print(io::IO, s::String)
    Base.print(io, '"')
    JSON.print_escaped(io, s)
    Base.print(io, '"')
end

function print(io::IO, s::Union(Integer, FloatingPoint))
    if isnan(s) || isinf(s)
        Base.print(io, "null")
    else
        Base.print(io, s)
    end
end

function print(io::IO, n::Nothing)
        Base.print(io, "null")
    end

function print(io::IO, a::Associative)
    Base.print(io, "{")
    first = true
    for (key, value) in a
        first ? (first = false) : Base.print(io, ",")
        JSON.print(io, string(key))
        Base.print(io, ':')
        JSON.print(io, value)
    end
    Base.print(io, "}")
end

function print(io::IO, a::Union(AbstractVector,Tuple))
    Base.print(io, "[")
    if length(a) > 0
        for x in a[1:end-1]
            JSON.print(io, x)
            Base.print(io, ",")
        end

        try
            JSON.print(io, a[end])
        catch
            # Potentially we got here by accessing
            # something through a 0 dimensional
            # part of an array. Probably expected
            # behavior is to not print and move on
        end
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

function print(io::IO, f::Function)
    Base.print(io, "\"function at ", f.fptr, "\"")
end

function print(io::IO, d::DataType)
    Base.print(io, d)
end

# Note: Arrays are printed in COLUMN MAJOR format.
# i.e. json([1 2 3; 4 5 6]) == "[[1,4],[2,5],[3,6]]"
function print{T, N}(io::IO, a::AbstractArray{T, N})
    Base.print(io, "[")

    lengthN = size(a, N)
    if lengthN >= 0
        newdims = ntuple(N - 1, i -> 1:size(a, i))
        print(io, slice(a, newdims..., 1))

        for j in 2:lengthN
            Base.print(io, ",")

            newdims = ntuple(N - 1, i -> 1:size(a, i))
            print(io, slice(a, newdims..., j))
        end
    end

    Base.print(io, "]")
end

print(a) = print(STDOUT, a)

json(a) = sprint(JSON.print, a)

function determine_bracket_type(io::IO)
    open_bracket = close_bracket = nothing
    while open_bracket == nothing
        eof(io) && throw(EOFError())
        c = read(io, Char)
        if c == '{'
            open_bracket = '{'
            close_bracket = '}'
        elseif c == '['
            open_bracket = '['
            close_bracket = ']'
        elseif c == '\0'
            throw(EOFError())
        end
    end
    open_bracket, close_bracket
end

###
# Consume a string (even if it is invalid), with ack to Douglas Crockford.
# On entry we must already have consumed the opening quotation double-quotation mark
# Add the characters of the string to obj
function consumeString(io::IO, obj::IOBuffer)
    c = '"'

    # When parsing for string values, we must look for " and \ characters.
    while true
        eof(io) && throw(EOFError())
        c = read(io, Char)
        if c == '"'
            write(obj, c)
            return
        end
        if c == '\\'
            write(obj, c)
            eof(io) && throw(EOFError())
            c = read(io, Char)
        end
        write(obj, c)
    end
    throw(EOFError())
end

function parse(io::IO; ordered::Bool=false)
    open_bracket = close_bracket = nothing
    try
        open_bracket, close_bracket = determine_bracket_type(io)
    catch exception
        isa(exception, EOFError) && return
    end
    num_brackets_needed = 1

    obj = IOBuffer()
    write(obj, open_bracket)

    while num_brackets_needed > 0
        eof(io) && throw(EOFError())
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
    JSON.parse(takebuf_string(obj), ordered=ordered)
end

function parsefile(filename::String; ordered::Bool=false, use_mmap=true)
    sz = filesize(filename)
    open(filename) do io
        s = use_mmap ? UTF8String(mmap_array(Uint8, (sz,), io)) : readall(io)
        JSON.parse(s, ordered=ordered)
    end
end

end # module

