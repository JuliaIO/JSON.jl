"""
Internal implementation detail.
"""
module Common

using Compat
if VERSION >= v"0.7.0-DEV.2915"
    using Unicode
end

include("bytes.jl")
include("errors.jl")

end
