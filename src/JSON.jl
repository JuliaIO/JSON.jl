module JSON

export parse,
       print_to_json, #Prints a compact (no extra whitespace or identation) JSON representation 
       to_json #Gives a compact JSON representation as a String

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

function print_to_json(io::IO, a::Vector)
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

#Modified and Adapted from http://www.mathworks.com/matlabcentral/fileexchange/23393
#Original BSD Licence, (c) 2011, François Glineur
function parse(strng::String)
    pos::Int = 1
    len::Int = length(strng)

    # String delimiters and escape characters are identified beforehand to improve speed
    len_esc::Int = 0
    index_esc::Int = 1

    esc_locations::Array{Int64,1}  = map(x->x.offset, [each_match(r"[\"\\\\]", strng)...])
    len_esc = length(esc_locations)  

    function parse_object()
        parse_char('{')
        object = (String=>Any)[]
        if next_char() != '}'
            while true
                str = parse_string()
                if isempty(str)
                    error("Name of value cannot be empty at position $pos: $(errpos())")
                end
                parse_char(':')
                val = parse_value()
                object[str] = val
                if next_char() == '}'
                    break
                end
                parse_char(',')
            end
        end
        parse_char('}')
        return object
    end

    function  parse_array()
        parse_char('[')
        object = Any[]
        if next_char() != ']'
            while true
                val = parse_value()
                push!(object, val)
                if next_char() == ']'
                    break
                end
                parse_char(',')
            end
        end
        parse_char(']')
        return object
    end

    function parse_char(c::Char)
        skip_whitespace()
        if pos > len || strng[pos] != c
            error("Expected $c at position $pos: $(errpos())")
        else
            pos = nextind(strng, pos)
            skip_whitespace()
        end
    end

    function next_char()
        skip_whitespace()
        if pos > len
            error("Unclosed braces at end of file")
        else
            c = strng[pos]
        end        
    end
    
    function skip_whitespace()
        while pos <= len && isspace(strng[pos])
            pos = nextind(strng, pos)
        end
    end

     function parse_string()
        if next_char() != '"'
            error("String starting with \" expected at position $pos: $(errpos())")
        else
            pos = pos + 1
        end
        str = ""
        while pos <= len
            while index_esc <= len_esc && esc_locations[index_esc] < pos 
                 index_esc = index_esc + 1;
            end
            if index_esc > len_esc
                str = strcat(str, strng[pos:end]);
                pos = len + 1;
                break;
            else
                str = strcat(str, strng[pos:esc_locations[index_esc]-1]);
                pos = esc_locations[index_esc];
            end
            nc = strng[pos]
            if nc == '"' 
                pos = nextind(strng, pos)
                return string(str)
            elseif nc ==  '\\'
                if pos+1 > len
                    error("End of file reached right after escape character")
                end
                pos = nextind(strng, pos)
                anc = strng[pos]
                 if anc == '"' || anc == '\\' || anc == '/'
                    str = strcat(str, strng[pos])
                    pos = nextind(strng, pos)
                 elseif anc ==  'b' || anc == 'f'|| anc == 'n' || anc == 'r' || anc == 't'
                    str = strcat(str, unescape_string(strcat('\\', strng[pos])))
                    pos = nextind(strng, pos)
                 elseif  anc == 'u'
                    startpos = prevind(strng, pos)
                    endpos = movpos(4)
                    if endpos > len
                        error("End of file reached in escaped unicode character")
                    end
                    
                    str = strcat(str, unescape_string(strng[startpos:endpos]))
                    pos =  nextind(strng, endpos)
                end
            else #This can be optimised if we have a preselected list of string terminators
                str = strcat(str,strng[pos])
                pos = nextind(strng, pos)
            end
        end
        error("End of file while expecting end of string")
    end

    function parse_number()
        num_regex = r"^[\w]?[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?[\w]?"
        m = match(num_regex, strng[pos:min(len,pos+40)])
        if m==nothing
            error("Error reading number at position $pos")
        end
        delta = m.offset + length(m.match)
        pos = pos + delta -1
        try
            return parse_int(m.match)
        catch
            return parse_float(m.match)
        end
    end

    function  parse_value()
        nc = next_char()
        if nc == '"'
            val = parse_string()
            return val
        elseif nc == '['
            val = parse_array()
            return val
        elseif nc == '{'
            val = parse_object()
            return val
        elseif nc == '-' || nc == '0' || nc == '1' || nc == '2' || nc == '3' || nc == '4' || nc == '5' || nc == '6' || nc == '7' || nc == '8' || nc == '9'
            val = parse_number()
            return val
        elseif nc == 't'
            endpos = movpos(3)
            if endpos <= len && strng[pos:endpos] == "true"
                val = true
                pos = nextind(strng, endpos)
                return val
            end
        elseif nc == 'f'
            endpos = movpos(4)
            if endpos <= len && strng[pos:endpos] == "false"
                val = false
                pos = nextind(strng, endpos)
                return val
            end
        elseif nc == 'n'
            endpos = movpos(3)
            if endpos <= len && strng[pos:endpos] == "null"
                val = nothing
                pos = nextind(strng, endpos)
                return val
            end
        end
        error("Value expected at position $pos: $(errpos())"  )
    end

   
    function isspace(c::Char)
        c==' ' || c=='\n' || c=='\t'
    end

    function errpos()
        if pos+20<len
            return "$(strng[pos:pos+20])..."
        else 
            return strng[pos:len]
        end 
    end

    function movpos(x::Int) 
        endpos = pos
        for i=1:x; endpos = nextind(strng, endpos); end
        return endpos
    end

    if pos <= len
        nc = next_char()
        if nc == '{'
            return parse_object()
        elseif nc == '['
            return parse_array()
        else
            error("Outer level structure must be an object or an array")
        end
    end

end

end
