require("JSON")

require("JSON/test/json_samples")

Running a few times to let the JIT kick in.
out, tracer = JSON.Faster.parse(d, true)
out, tracer = JSON.Faster.parse(d, true)
out, tracer = JSON.Faster.parse(d, true)

JSON.Faster.print_trace(tracer)
