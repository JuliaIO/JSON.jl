"""
Internal implementation detail.
"""
module Common

using Compat

# The expression head to use for constructing types.
# TODO: Remove this hack when 0.5 support is dropped.
const STRUCTHEAD = VERSION < v"0.7.0-DEV.1263" ? :type : :struct

include("bytes.jl")
include("errors.jl")

end
