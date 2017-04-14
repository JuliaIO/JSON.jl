__precompile__()

module JSON

using Compat

export json # returns a compact (or indented) JSON representation as a string

include("Common.jl")

# Parser modules
include("Parser.jl")

# Writer modules
include("Serializations.jl")
include("Writer.jl")

# stuff to re-"export"
# note that this package does not actually export anything except `json` but
# all of the following are part of the public interface in one way or another
using .Parser: parse, parsefile
using .Writer: show_json, json, lower, print, StructuralContext, show_element,
               show_string, show_key, show_pair, show_null, begin_array,
               end_array, begin_object, end_object, indent, delimit, separate
using .Serializations: Serialization, CommonSerialization,
                       StandardSerialization

end # module
