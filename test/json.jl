using JSON, Test, Logging

mutable struct CircularRef
    id::Int
    self::Union{Nothing, CircularRef}
end

struct CustomNumber <: Real
    x::Float64
end

@omit_null struct OmitNull
    id::Int
    name::Union{Nothing, String}
end

@omit_empty struct OmitEmpty
    id::Int
    value::Union{Nothing, String}
    values::Vector{Int}
end

@omit_null struct SentinelOverrides
    id::Int
    forced::Union{Nothing, JSON.Null}
    passthrough::Union{Nothing, String}
    dropped::Union{Nothing, JSON.Omit}
end

@testset "JSON.json" begin

@testset "Basics" begin
    @test JSON.json(nothing) == "null"
    @test JSON.json(true) == "true"
    @test JSON.json(false) == "false"
    # test the JSON output of a bunch of numbers
    @test JSON.json(0) == "0"
    @test JSON.json(1) == "1"
    @test JSON.json(1.0) == "1.0"
    @test JSON.json(1.0f0) == "1.0"
    @test JSON.json(1.0f1) == "10.0"
    @test JSON.json(1.0f-1) == "0.1"
    @test JSON.json(1.0f-2) == "0.01"
    @test JSON.json(1.0f-3) == "0.001"
    @test JSON.json(1.0f-4) == "0.0001"
    @test JSON.json(1.0f-5) == "1.0e-5"
    @test JSON.json(-1) == "-1"
    @test JSON.json(-1.0) == "-1.0"
    @test JSON.json(typemin(Int64)) == "-9223372036854775808"
    @test JSON.json(typemax(Int64)) == "9223372036854775807"
    @test JSON.json(BigInt(1)) == "1"
    @test JSON.json(BigInt(1) << 100) == "1267650600228229401496703205376"
    @test JSON.json(BigInt(-1)) == "-1"
    @test JSON.json(BigInt(-1) << 100) == "-1267650600228229401496703205376"
    @test JSON.json(typemin(UInt64)) == "0"
    @test JSON.json(typemax(UInt64)) == "18446744073709551615"
    @test_throws ArgumentError JSON.json(NaN)
    @test_throws ArgumentError JSON.json(Inf)
    @test_throws ArgumentError JSON.json(-Inf)
    @test JSON.json(NaN; allownan=true) == "NaN"
    @test JSON.json(Inf; allownan=true) == "Infinity"
    @test JSON.json(-Inf; allownan=true) == "-Infinity"
    # custom nan or inf strings
    @test JSON.json(NaN; allownan=true, nan="nan") == "nan"
    @test JSON.json(Inf; allownan=true, inf="inf") == "inf"
    @test JSON.json(-Inf; allownan=true, ninf="-inf") == "-inf"
    # test the JSON output of a bunch of strings
    @test JSON.json("") == "\"\""
    @test JSON.json("a") == "\"a\""
    @test JSON.json("a\"b") == "\"a\\\"b\""
    @test JSON.json("a\\b") == "\"a\\\\b\""
    @test JSON.json("a\b") == "\"a\\b\""
    @test JSON.json("a\f") == "\"a\\f\""
    # test the JSON output of a bunch of strings with unicode characters
    @test JSON.json("\u2200") == "\"∀\""
    @test JSON.json("\u2200\u2201") == "\"∀∁\""
    @test JSON.json("\u2200\u2201\u2202") == "\"∀∁∂\""
    @test JSON.json("\u2200\u2201\u2202\u2203") == "\"∀∁∂∃\""
    # test the JSON output of a bunch of arrays
    @test JSON.json(Int[]) == "[]"
    @test JSON.json(Int[1]) == "[1]"
    @test JSON.json(Int[1, 2]) == "[1,2]"
    @test JSON.json((1, 2)) == "[1,2]"
    @test JSON.json(Set([2])) == "[2]"
    @test JSON.json([1, nothing, "hey", 3.14, true, false]) == "[1,null,\"hey\",3.14,true,false]"
    # test the JSON output of a bunch of dicts/namedtuples
    @test JSON.json(Dict{Int, Int}()) == "{}"
    @test JSON.json(Dict{Int, Int}(1 => 2)) == "{\"1\":2}"
    @test JSON.json((a = 1, b = 2)) == "{\"a\":1,\"b\":2}"
    @test JSON.json((a = nothing, b=2, c="hey", d=3.14, e=true, f=false)) == "{\"a\":null,\"b\":2,\"c\":\"hey\",\"d\":3.14,\"e\":true,\"f\":false}"
    # test Vector{Pair} serializes as object, not array
    @test JSON.json(Pair{String, Int}[]) == "{}"
    @test JSON.json([:a => 1, :b => 2]) == "{\"a\":1,\"b\":2}"
    @test JSON.json(["x" => "value", "y" => 42]) == "{\"x\":\"value\",\"y\":42}"
    @test JSON.json([1 => "one", 2 => "two"]) == "{\"1\":\"one\",\"2\":\"two\"}"
    # test Vector{Pair} in nested structures
    @test JSON.json(Dict("data" => [:x => 1, :y => 2])) == "{\"data\":{\"x\":1,\"y\":2}}"
    # test the JSON output of nested array/objects
    @test JSON.json([1, [2, 3], [4, [5, 6]]]) == "[1,[2,3],[4,[5,6]]]"
    @test JSON.json(Dict{Int, Any}(1 => Dict{Int, Any}(2 => Dict{Int, Any}(3 => 4)))) == "{\"1\":{\"2\":{\"3\":4}}}"
    # now a mix of arrays and objects
    @test JSON.json([1, Dict{Int, Any}(2 => Dict{Int, Any}(3 => 4))]) == "[1,{\"2\":{\"3\":4}}]"
    @test JSON.json(Dict{Int, Any}(1 => [2, Dict{Int, Any}(3 => 4)])) == "{\"1\":[2,{\"3\":4}]}"
    # test undefined elements of an array
    arr = Vector{String}(undef, 3)
    arr[1] = "a"
    arr[3] = "b"
    @test JSON.json(arr) == "[\"a\",null,\"b\"]"
    # test custom struct writing
    # defined in the test/struct.jl file
    a = A(1, 2, 3, 4)
    @test JSON.json(a) == "{\"a\":1,\"b\":2,\"c\":3,\"d\":4}"
    x = LotsOfFields("1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35")
    @test JSON.json(x) == "{\"x1\":\"1\",\"x2\":\"2\",\"x3\":\"3\",\"x4\":\"4\",\"x5\":\"5\",\"x6\":\"6\",\"x7\":\"7\",\"x8\":\"8\",\"x9\":\"9\",\"x10\":\"10\",\"x11\":\"11\",\"x12\":\"12\",\"x13\":\"13\",\"x14\":\"14\",\"x15\":\"15\",\"x16\":\"16\",\"x17\":\"17\",\"x18\":\"18\",\"x19\":\"19\",\"x20\":\"20\",\"x21\":\"21\",\"x22\":\"22\",\"x23\":\"23\",\"x24\":\"24\",\"x25\":\"25\",\"x26\":\"26\",\"x27\":\"27\",\"x28\":\"28\",\"x29\":\"29\",\"x30\":\"30\",\"x31\":\"31\",\"x32\":\"32\",\"x33\":\"33\",\"x34\":\"34\",\"x35\":\"35\"}"
    # test custom struct writing with custom field names
    x = L(1, "george", 33.3)
    @test JSON.json(x) == "{\"id\":1,\"firstName\":\"george\",\"rate\":33.3}"
    # test custom struct writing with undef fields
    x = UndefGuy()
    x.id = 10
    @test JSON.json(x) == "{\"id\":10,\"name\":null}"
    # test structs with circular references
    x = CircularRef(11, nothing)
    x.self = x
    @test JSON.json(x) == "{\"id\":11,\"self\":null}"
    # test lowering
    x = K(123, missing)
    @test JSON.json(x) == "{\"id\":123,\"value\":null}"
    x = UUID(typemax(UInt128))
    @test JSON.json(x) == "\"ffffffff-ffff-ffff-ffff-ffffffffffff\""
    @test JSON.json(:a) == "\"a\""
    @test JSON.json(apple) == "\"apple\""
    @test JSON.json('a') == "\"a\""
    @test JSON.json('∀') == "\"∀\""
    @test JSON.json(v"1.2.3") == "\"1.2.3\""
    @test JSON.json(r"1.2.3") == "\"1.2.3\""
    @test JSON.json(Date(2023, 2, 23)) == "\"2023-02-23\""
    @test JSON.json(DateTime(2023, 2, 23, 12, 34, 56)) == "\"2023-02-23T12:34:56\""
    @test JSON.json(Time(12, 34, 56)) == "\"12:34:56\""
    # test field-specific lowering
    x = ThreeDates(Date(2023, 2, 23), DateTime(2023, 2, 23, 12, 34, 56), Time(12, 34, 56))
    @test JSON.json(x) == "{\"date\":\"2023_02_23\",\"datetime\":\"2023/02/23 12:34:56\",\"time\":\"12/34/56\"}"
    # test matrix writing
    @test JSON.json([1 2; 3 4]) == "[[1,3],[2,4]]"
    @test JSON.json((a=[1 2; 3 4],)) == "{\"a\":[[1,3],[2,4]]}"
    # singleton writing
    @test JSON.json(C()) == "\"C()\""
    # module writing
    @test JSON.json(JSON) == "\"JSON\""
    # function writing
    @test JSON.json(JSON.json) == "\"json\""
    # SimpleVector writing
    @test JSON.json(Core.svec(1, 2, 3)) == "[1,2,3]"
    # DataType writing
    @test JSON.json(Float64) == "\"Float64\""
    @test JSON.json(Union{Missing, Float64}) == "\"Union{Missing, Float64}\""
    # LogLevel writing
    @test JSON.json(Logging.Info) == "\"Info\""
    @test JSON.json(Logging.LogLevel(1)) == "\"LogLevel(1)\""
    # multidimensional arrays
    # "[[1.0],[2.0]]" => (1, 2)
    m = Matrix{Float64}(undef, 1, 2)
    m[1] = 1
    m[2] = 2
    @test JSON.json(m) == "[[1.0],[2.0]]"
    # "[[1.0,2.0]]" => (2, 1)
    m = Matrix{Float64}(undef, 2, 1)
    m[1] = 1
    m[2] = 2
    @test JSON.json(m) == "[[1.0,2.0]]"
    # "[[[1.0]],[[2.0]]]" => (1, 1, 2)
    m = Array{Float64}(undef, 1, 1, 2)
    m[1] = 1
    m[2] = 2
    @test JSON.json(m) == "[[[1.0]],[[2.0]]]"
    # "[[[1.0],[2.0]]]" => (1, 2, 1)
    m = Array{Float64}(undef, 1, 2, 1)
    m[1] = 1
    m[2] = 2
    @test JSON.json(m) == "[[[1.0],[2.0]]]"
    # "[[[1.0,2.0]]]" => (2, 1, 1)
    m = Array{Float64}(undef, 2, 1, 1)
    m[1] = 1
    m[2] = 2
    @test JSON.json(m) == "[[[1.0,2.0]]]"

    m = Array{Float64}(undef, 1, 2, 3)
    m[1] = 1
    m[2] = 2
    m[3] = 3
    m[4] = 4
    m[5] = 5
    m[6] = 6
    @test JSON.json(m) == "[[[1.0],[2.0]],[[3.0],[4.0]],[[5.0],[6.0]]]"
    # 0-dimensional array
    m = Array{Float64,0}(undef)
    m[1] = 1.0
    @test JSON.json(m) == "1.0"
    # JSON.json forms
    io = IOBuffer()
    JSON.json(io, missing)
    @test String(take!(io)) == "null"
    fname, io = mktemp()
    close(io)
    JSON.json(fname, missing)
    @test read(fname, String) == "null"
    rm(fname)
    @testset "pretty output" begin
        @test JSON.json([1, 2, 3], pretty=4) == "[\n    1,\n    2,\n    3\n]"
        @test JSON.json([1, 2, 3], pretty=true) == "[\n  1,\n  2,\n  3\n]"
        @test JSON.json([1, 2, 3], pretty=0) == "[1,2,3]"
        # empty object/array
        @test JSON.json([], pretty=true) == "[]"
        @test JSON.json(Dict(), pretty=true) == "{}"
        # several levels of nesting
        @test JSON.json([1, [2, 3], [4, [5, 6]]], pretty=true) == "[\n  1,\n  [\n    2,\n    3\n  ],\n  [\n    4,\n    [\n      5,\n      6\n    ]\n  ]\n]"
        # several levels of nesting with a mix of nulls, numbers, strings, booleans, empty objects, arrays, etc.
        @test JSON.json([1, [2, 3], [4, [5, 6]], nothing, "hey", 3.14, true, false, Dict(), []], pretty=true) == "[\n  1,\n  [\n    2,\n    3\n  ],\n  [\n    4,\n    [\n      5,\n      6\n    ]\n  ],\n  null,\n  \"hey\",\n  3.14,\n  true,\n  false,\n  {},\n  []\n]"
        # JSON.jl pre-1.0 compat
        io = IOBuffer()
        JSON.print(io, [1, 2, 3], 2)
        @test String(take!(io)) == "[\n  1,\n  2,\n  3\n]"
        @test JSON.json([1, 2, 3], 2) == "[\n  1,\n  2,\n  3\n]"
        # inline_limit tests
        @test JSON.json([1, 2]; pretty=2, inline_limit=3) == "[1,2]"
        @test JSON.json([1, 2, 3]; pretty=2, inline_limit=3) == "[\n  1,\n  2,\n  3\n]"
    end
    # non-Integer/AbstractFloat but <: Real output
    @test_throws MethodError JSON.json(CustomNumber(3.14))
    JSON.tostring(x::CustomNumber) = string(x.x)
    @test JSON.json(CustomNumber(3.14)) == "3.14"
    # jsonlines output
    @test JSON.json([1, 2, 3]; jsonlines=true) == "1\n2\n3\n"
    # jsonlines output with pretty not allowed
    @test_throws ArgumentError JSON.json([1, 2, 3]; jsonlines=true, pretty=true)
    # jsonlines each line is an object
    @test JSON.json([(a=1, b=2), (a=3, b=4)]; jsonlines=true) == "{\"a\":1,\"b\":2}\n{\"a\":3,\"b\":4}\n"
    # jsonlines with empty array
    @test JSON.json([]; jsonlines=true) == "\n"
    # jsonlines not allowed on objects
    @test_throws ArgumentError JSON.json((a=1, b=2); jsonlines=true)
    # circular reference tracking
    a = Any[1, 2, 3]
    push!(a, a)
    @test JSON.json(a) == "[1,2,3,null]"
    a = (a=1,)
    x = [a, a, a]
    @test JSON.json(x) == "[{\"a\":1},{\"a\":1},{\"a\":1}]"
    a = CircularRef(1, nothing)
    a.self = a
    x = [a, a, a]
    @test JSON.json(x) == "[{\"id\":1,\"self\":null},{\"id\":1,\"self\":null},{\"id\":1,\"self\":null}]"
    # custom key function
    @test_throws ArgumentError JSON.json(Dict(Point(1, 2) => "hi"))
    StructUtils.lowerkey(::JSON.JSONStyle, p::Point) = "$(p.x)_$(p.y)"
    @test JSON.json(Dict(Point(1, 2) => "hi")) == "{\"1_2\":\"hi\"}"
    x = JSONText("[1,2,3]")
    @test JSON.json(x) == "[1,2,3]"
    @test JSON.json((a=1, b=nothing)) == "{\"a\":1,\"b\":null}"
    @test JSON.json((a=1, b=nothing); omit_null=true) == "{\"a\":1}"
    @test JSON.json((a=1, b=nothing); omit_null=false) == "{\"a\":1,\"b\":null}"
    @test JSON.json((a=1, b=[]); omit_empty=true) == "{\"a\":1}"
    @test JSON.json((a=1, b=[]); omit_empty=false) == "{\"a\":1,\"b\":[]}"
    @testset "Sentinel overrides" begin
        @test JSON.json(JSON.Null()) == "null"
        @test_throws ArgumentError JSON.json(JSON.Omit())
        @test JSON.json((a=1, b=JSON.Null()); omit_null=true) == "{\"a\":1,\"b\":null}"
        @test JSON.json((a=JSON.Omit(), b=JSON.Null())) == "{\"b\":null}"
        @test JSON.json((a=JSON.Omit(), b=2); omit_null=false) == "{\"b\":2}"
        @test JSON.json([JSON.Omit(), 1, JSON.Omit(), 2]) == "[1,2]"
        @test JSON.json([JSON.Omit(), JSON.Omit()]) == "[]"
        x = SentinelOverrides(1, JSON.Null(), nothing, JSON.Omit())
        @test JSON.json(x) == "{\"id\":1,\"forced\":null}"
        @test JSON.json(x; omit_null=false) == "{\"id\":1,\"forced\":null,\"passthrough\":null}"
    end
    # custom style overload
    JSON.lower(::CustomJSONStyle, x::Rational) = (num=x.num, den=x.den)
    @test JSON.json(1//3; style=CustomJSONStyle()) == "{\"num\":1,\"den\":3}"
    # @omit_null and @omit_empty
    @test JSON.json(OmitNull(1, nothing)) == "{\"id\":1}"
    @test JSON.json(OmitNull(1, nothing); omit_null=false) == "{\"id\":1,\"name\":null}"
    @test JSON.json(OmitEmpty(1, nothing, [])) == "{\"id\":1}"
    @test JSON.json(OmitEmpty(1, "abc", []); omit_empty=false) == "{\"id\":1,\"value\":\"abc\",\"values\":[]}"
    # float_style and float_precision
    @test JSON.json(Float64(π); float_style=:fixed, float_precision=2) == "3.14"
    @test JSON.json(Float64(π); float_style=:exp, float_precision=2) == "3.14e+00"
    @test_throws ArgumentError JSON.json(Float64(π); float_style=:fixed, float_precision=0)
    @test_throws ArgumentError JSON.json(Float64(π); float_style=:fixed, float_precision=-1)
    @test_throws ArgumentError JSON.json(Float64(π); float_style=:exp, float_precision=0)
    io = IOBuffer()
    @test_throws ArgumentError JSON.json(io, Float64(π); float_style=:fixed, float_precision=0)
    @test_throws ArgumentError JSON.json(Float64(π); float_style=:not_a_style)
end

@testset "Enhanced @omit_null and @omit_empty macros" begin
    # Test structs for new macro functionality

    # Test case 1: Apply @omit_null to existing struct
    struct ExistingStruct1
        id::Int
        name::Union{Nothing, String}
        value::Union{Nothing, Int}
    end
    @omit_null ExistingStruct1

    # Test case 2: Apply @omit_empty to existing struct
    struct ExistingStruct2
        id::Int
        items::Vector{String}
        data::Dict{String, Int}
    end
    @omit_empty ExistingStruct2

    # Test case 3: Chaining with StructUtils.@defaults macro
    @omit_null @defaults struct ChainedStruct1
        id::Int = 1
        name::Union{Nothing, String} = nothing
    end

    @omit_empty @defaults struct ChainedStruct2
        id::Int = 1
        items::Vector{String} = String[]
    end

    # Test case 4: Complex type expressions
    struct ParametricStruct{T}
        id::Int
        value::Union{Nothing, T}
    end
    @omit_null ParametricStruct{String}  # Apply to specific parametric type

    struct SimpleStruct
        id::Int
        name::Union{Nothing, String}
    end
    @omit_null SimpleStruct

    # Tests for case 1: Apply to existing struct
    @test JSON.json(ExistingStruct1(1, nothing, nothing)) == "{\"id\":1}"
    @test JSON.json(ExistingStruct1(1, "test", 42)) == "{\"id\":1,\"name\":\"test\",\"value\":42}"
    @test JSON.json(ExistingStruct1(1, nothing, nothing); omit_null=false) == "{\"id\":1,\"name\":null,\"value\":null}"

    @test JSON.json(ExistingStruct2(1, String[], Dict{String, Int}())) == "{\"id\":1}"
    @test JSON.json(ExistingStruct2(1, ["test"], Dict("key" => 1))) == "{\"id\":1,\"items\":[\"test\"],\"data\":{\"key\":1}}"
    @test JSON.json(ExistingStruct2(1, String[], Dict{String, Int}()); omit_empty=false) == "{\"id\":1,\"items\":[],\"data\":{}}"

    # Tests for case 3: Chained macros with @defaults
    @test JSON.json(ChainedStruct1()) == "{\"id\":1}"  # Uses default constructor from @defaults
    @test JSON.json(ChainedStruct1(2, "test")) == "{\"id\":2,\"name\":\"test\"}"

    @test JSON.json(ChainedStruct2()) == "{\"id\":1}"  # Uses default constructor from @defaults  
    @test JSON.json(ChainedStruct2(2, ["test"])) == "{\"id\":2,\"items\":[\"test\"]}"

    # Tests for case 4: Complex types
    @test JSON.json(ParametricStruct{String}(1, nothing)) == "{\"id\":1}"
    @test JSON.json(ParametricStruct{String}(1, "test")) == "{\"id\":1,\"value\":\"test\"}"

    @test JSON.json(SimpleStruct(1, nothing)) == "{\"id\":1}"
    @test JSON.json(SimpleStruct(1, "test")) == "{\"id\":1,\"name\":\"test\"}"

    # Test error cases
    @test_throws LoadError eval(:(@omit_null 123))
    @test_throws LoadError eval(:(@omit_empty "not_a_type"))
end

@testset "Buffered IO" begin
    # Helper function to create large test data
    function create_large_object(size::Int)
        return Dict{String, Any}(
            "large_array" => collect(1:size),
            "nested_data" => Dict{String, Any}(
                "strings" => ["test_string_$i" for i in 1:div(size, 10)],
                "numbers" => [i * 3.14159 for i in 1:div(size, 10)],
                "booleans" => [i % 2 == 0 for i in 1:div(size, 10)]
            ),
            "metadata" => Dict{String, Any}(
                "size" => size,
                "type" => "test_data",
                "description" => "Large test object for buffered IO testing" * "x"^100
            )
        )
    end

    @testset "Basic buffered IO functionality" begin
        # Test with small buffer size (512 bytes)
        test_data = create_large_object(100)
        
        # Test writing to IOBuffer with small buffer
        io1 = IOBuffer()
        JSON.json(io1, test_data; bufsize=512)
        result1 = String(take!(io1))
        
        # Test writing to IOBuffer with default buffer size
        io2 = IOBuffer()
        JSON.json(io2, test_data)
        result2 = String(take!(io2))
        
        # Results should be identical regardless of buffer size
        @test result1 == result2
        
        # Test writing to IOBuffer with very large buffer
        io3 = IOBuffer()
        JSON.json(io3, test_data; bufsize=1024*1024)  # 1MB buffer
        result3 = String(take!(io3))
        
        @test result1 == result3
        
        # Verify the JSON can be parsed back correctly
        parsed = JSON.parse(result1)
        @test parsed["large_array"] == collect(1:100)
        @test parsed["metadata"]["size"] == 100
    end

    @testset "Buffer size boundary conditions" begin
        # Create data that will test buffer boundaries
        test_data = create_large_object(500)
        expected_result = JSON.json(test_data)
        
        # Test with various buffer sizes around typical JSON size
        buffer_sizes = [64, 128, 256, 512, 1024, 2048, 4096, 8192]
        
        for bufsize in buffer_sizes
            io = IOBuffer()
            JSON.json(io, test_data; bufsize=bufsize)
            result = String(take!(io))
            @test result == expected_result
        end
    end

    @testset "Multiple flush scenarios" begin
        # Create data large enough to trigger multiple flushes
        large_data = create_large_object(2000)
        
        # Test with very small buffer to force multiple flushes
        io = IOBuffer()
        JSON.json(io, large_data; bufsize=256)
        result_small_buf = String(take!(io))
        
        # Compare with large buffer (no flushes)
        io2 = IOBuffer()
        JSON.json(io2, large_data; bufsize=1024*1024)
        result_large_buf = String(take!(io2))
        
        @test result_small_buf == result_large_buf
        
        # Verify correctness by parsing
        parsed = JSON.parse(result_small_buf)
        @test length(parsed["large_array"]) == 2000
        @test parsed["metadata"]["size"] == 2000
    end

    @testset "Array and object combinations with buffering" begin
        # Test mix of arrays and objects that might cross buffer boundaries
        mixed_data = [
            Dict("id" => i, "data" => collect((i-1)*10+1:i*10), "metadata" => "item_$i" * "x"^50)
            for i in 1:100
        ]
        
        buffer_sizes = [128, 512, 2048]
        expected = JSON.json(mixed_data)
        
        for bufsize in buffer_sizes
            io = IOBuffer()
            JSON.json(io, mixed_data; bufsize=bufsize)
            result = String(take!(io))
            @test result == expected
        end
    end

    @testset "String escaping with buffering" begin
        # Test strings that require escaping across buffer boundaries
        strings_with_escaping = [
            "String with \"quotes\" and \\backslashes\\",
            "String with\nnewlines\tand\ttabs",
            "Unicode string: 🌟🚀💻🔥⭐",
            "Mixed content: \"Hello\\nWorld\"\t🌍",
            "Very long string: " * "A"^1000 * " with \" quotes \" and \\ backslashes \\"
        ]
        
        test_data = Dict("strings" => strings_with_escaping)
        expected = JSON.json(test_data)
        
        # Test with small buffer that will split escaped sequences
        io = IOBuffer()
        JSON.json(io, test_data; bufsize=64)
        result = String(take!(io))
        @test result == expected
        
        # Verify by parsing back
        parsed = JSON.parse(result)
        @test parsed["strings"] == strings_with_escaping
    end

    @testset "Pretty printing with buffering" begin
        test_data = create_large_object(50)
        
        # Test pretty printing with different buffer sizes
        buffer_sizes = [256, 1024, 4096]
        
        for bufsize in buffer_sizes
            # Pretty printing with 2 spaces
            io1 = IOBuffer()
            JSON.json(io1, test_data; pretty=2, bufsize=bufsize)
            result1 = String(take!(io1))
            
            # Compare with reference (large buffer)
            io2 = IOBuffer()
            JSON.json(io2, test_data; pretty=2, bufsize=1024*1024)
            result2 = String(take!(io2))
            
            @test result1 == result2
            
            # Ensure it's actually pretty printed
            @test contains(result1, "\n")
            @test contains(result1, "  ")  # indentation
        end
    end

    @testset "Edge cases and error conditions" begin
        # Test with minimal buffer size
        simple_data = Dict("key" => "value")
        
        # Very small buffer (smaller than a single JSON element)
        io = IOBuffer()
        JSON.json(io, simple_data; bufsize=8)
        result = String(take!(io))
        @test result == "{\"key\":\"value\"}"
        
        # Test with empty data
        io = IOBuffer()
        JSON.json(io, Dict{String,Any}(); bufsize=32)
        result = String(take!(io))
        @test result == "{}"
        
        # Test with array
        io = IOBuffer()
        JSON.json(io, Int[]; bufsize=32)
        result = String(take!(io))
        @test result == "[]"
    end

    @testset "File writing with buffering" begin
        # Test writing to actual file with different buffer sizes
        test_data = create_large_object(300)
        expected = JSON.json(test_data)
        
        temp_files = String[]
        
        try
            for (i, bufsize) in enumerate([512, 2048, 8192])
                filename = tempname() * ".json"
                push!(temp_files, filename)
                
                # Write with specific buffer size
                open(filename, "w") do io
                    JSON.json(io, test_data; bufsize=bufsize)
                end
                
                # Read back and verify
                content = read(filename, String)
                @test content == expected
                
                # Parse to verify correctness
                parsed = JSON.parse(content)
                @test parsed["large_array"][1] == 1
                @test parsed["large_array"][end] == 300
            end
        finally
            # Clean up temp files
            for filename in temp_files
                isfile(filename) && rm(filename)
            end
        end
    end

    @testset "JSONLines with buffering" begin
        # Test JSONLines format with buffering
        data = [
            Dict("id" => i, "value" => "item_$i", "data" => collect(1:i))
            for i in 1:20
        ]
        
        buffer_sizes = [128, 512, 2048]
        expected = JSON.json(data; jsonlines=true)
        
        for bufsize in buffer_sizes
            io = IOBuffer()
            JSON.json(io, data; jsonlines=true, bufsize=bufsize)
            result = String(take!(io))
            @test result == expected
            
            # Verify each line is valid JSON
            lines = split(strip(result), '\n')
            @test length(lines) == 20
            for (i, line) in enumerate(lines)
                parsed_line = JSON.parse(line)
                @test parsed_line["id"] == i
            end
        end
    end

    @testset "Circular references with buffering" begin
        # Test circular reference handling with small buffers
        a = Any[1, 2, 3]
        push!(a, a)  # circular reference
        
        buffer_sizes = [64, 256, 1024]
        expected = "[1,2,3,null]"  # circular ref becomes null
        
        for bufsize in buffer_sizes
            io = IOBuffer()
            JSON.json(io, a; bufsize=bufsize)
            result = String(take!(io))
            @test result == expected
        end
    end

    @testset "Test pre-1.0 compat for object Tuple keys" begin
        @test JSON.json(Dict(("a", "b") => 1)) == "{\"(\\\"a\\\", \\\"b\\\")\":1}"
    end
end

end # @testset "JSON.json"
