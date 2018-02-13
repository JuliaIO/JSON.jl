# Run modified JSON checker tests

const JSON_DATA_DIR = joinpath(dirname(@__DIR__), "data")

lp(i) = lpad(i, 2, "0")

for i in 1:38
    file = "fail$(lp(i)).json"
    filepath = joinpath(JSON_DATA_DIR, "jsonchecker", file)

    @test_throws ErrorException JSON.parsefile(filepath)
end

for i in 1:3
    # Test that the files parse successfully and match streaming parser
    tf = joinpath(JSON_DATA_DIR, "jsonchecker", "pass$(lp(i)).json")
    @test JSON.parsefile(tf) == open(JSON.parse, tf)
end

# Run JSON roundtrip tests (check consistency of .json)

roundtrip(data) = JSON.json(JSON.Parser.parse(data))

for i in 1:27
    file = "roundtrip$(lp(i)).json"
    filepath = joinpath(JSON_DATA_DIR, "roundtrip", file)

    rt = roundtrip(read(filepath, String))
    @test rt == roundtrip(rt)
end
