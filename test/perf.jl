require("JSON")

require("JSON/test/json_samples")

macro timeit(name, ex)
  quote
    t = Inf
    for i=1:1000
      t = min(t, @elapsed $ex)
    end
    println($name, "\t", JSON.Faster.format(t * 1000))
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
  @assert JSON.Faster.parse(a) != nothing
  @assert JSON.Faster.parse(b) != nothing
  @assert JSON.Faster.parse(c) != nothing
  @assert JSON.Faster.parse(d) != nothing
  @assert JSON.Faster.parse(e) != nothing
end

println()
