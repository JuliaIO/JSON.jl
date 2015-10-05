_HAVE_DATASTRUCTURES = try
    @eval import DataStructures.OrderedDict
    true
catch
    false
end

open("deps.jl", "w") do f
    println(f, "const _HAVE_DATASTRUCTURES = $_HAVE_DATASTRUCTURES")
end
