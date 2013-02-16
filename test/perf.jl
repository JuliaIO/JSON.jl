require("JSON")
require("JSON/src/FasterJSON")

require("JSON/test/JSON_samples")

# Running a few times to let the JIT kick in.
# out, tracer = FasterJSON.parse(d, true)
# out, tracer = FasterJSON.parse(d, true)
# out, tracer = FasterJSON.parse(d, true)
# 
# FasterJSON.print_trace(tracer)
# 
# exit()

macro timeit(name, ex)
    quote
        t = Inf
        for i=1:10
            t = min(t, @elapsed $ex)
        end
        println($name, "\t", FasterJSON.format(t * 1000))
    end
end

println("Julia Performance (msecs)")

@timeit "JSON\t" begin
  @assert JSON.parse(a) != nothing
  @assert JSON.parse(b) != nothing
  @assert JSON.parse(c) != nothing
  @assert JSON.parse(d) != nothing
  @assert JSON.parse(e) != nothing
end

@timeit "FasterJSON" begin
  @assert FasterJSON.parse(a) != nothing
  @assert FasterJSON.parse(b) != nothing
  @assert FasterJSON.parse(c) != nothing
  @assert FasterJSON.parse(d) != nothing
  @assert FasterJSON.parse(e) != nothing
end

println()
