@testset begin
    test_str = """
        {
            "x": NaN,
            "y": Infinity,
            "z": -Infinity,
            "q": [true, null, "hello", 1, -1, 1.5, -1.5, [true]]
        }"""

    test_dict = Dict(
        "x" => NaN,
        "y" => Inf,
        "z" => -Inf,
        "q" => [true, nothing, "hello", 1, -1, 1.5, -1.5, [true]]
    )

    @test_throws ErrorException JSON.parse(test_str, allownan=false)
    val = JSON.parse(test_str)
    @test isequal(val, test_dict)

    @test_throws ErrorException JSON.parse(IOBuffer(test_str), allownan=false)
    val2 = JSON.parse(IOBuffer(test_str))
    @test isequal(val2, test_dict)

    # Test that the number following -Infinity parses correctly
    @test isequal(JSON.parse("[-Infinity, 1]"), [-Inf, 1])
    @test isequal(JSON.parse("[-Infinity, -1]"), [-Inf, -1])
    @test isequal(JSON.parse("""{"a": -Infinity, "b": 1.0}"""), Dict("a" => -Inf, "b"=> 1.0))
    @test isequal(JSON.parse("""{"a": -Infinity, "b": -1.0}"""), Dict("a" => -Inf, "b"=> -1.0))

    @test isequal(JSON.parse(IOBuffer("[-Infinity, 1]")), [-Inf, 1])
    @test isequal(JSON.parse(IOBuffer("[-Infinity, -1]")), [-Inf, -1])
    @test isequal(JSON.parse(IOBuffer("""{"a": -Infinity, "b": 1.0}""")), Dict("a" => -Inf, "b"=> 1.0))
    @test isequal(JSON.parse(IOBuffer("""{"a": -Infinity, "b": -1.0}""")), Dict("a" => -Inf, "b"=> -1.0))
end
