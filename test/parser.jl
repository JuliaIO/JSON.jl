const InputType = Ref{DataType}()

const FAILURES = [
    # Unexpected character in array
    "[1,2,3/4,5,6,7]",
    # Unexpected character in object
    "{\"1\":2, \"2\":3 _ \"4\":5}",
    # Invalid escaped character
    "[\"alpha\\α\"]",
    "[\"\\u05AG\"]",
    # Invalid 'simple' and 'unknown value'
    "[tXXe]",
    "[fail]",
    "∞",
    # Invalid number
    "[5,2,-]",
    "[5,2,+β]",
    # Incomplete escape
    "\"\\",
    # Control character
    "\"\0\"",
    # Issue #99
    "[\"🍕\"_\"🍕\"",
    # Issue with allowing multiple -
    "-----1233123"
]

const MISC = [("true", true),
              ("false", false),
              ("null", nothing),
              ("\"hello\"", "hello"),
              ("\"a\"", "a"),
              ("1", 1),
              ("1.5", 1.5),
              ("[true]", [true])]

const issue21 = "[\r\n{\r\n\"a\": 1,\r\n\"b\": 2\r\n},\r\n{\r\n\"a\": 3,\r\n\"b\": 4\r\n}\r\n]"

mutable struct t109
    i::Int
end

const explist = ("0", "00030", "60", "123", "12341231234123412")

makeexplist() = [string(pre, ex) for pre in ("e", "e-", "e+", "E", "E-", "E+") for ex in explist]

for t in (String, IOBuffer)
    InputType[] = t
    @testset "Parser: $t" begin
        @testset for fail in FAILURES
            @test_throws ErrorException JSON.parse(InputType[](fail))
        end
        @testset "dicttype" begin
            @testset for T in [DataStructures.OrderedDict, Dict{Symbol, Int32}]
                val = JSON.parse(InputType[]("{\"x\": 3}"), dicttype=T)
                @test isa(val, T)
                @test length(val) == 1
                key = collect(keys(val))[1]
                @test string(key) == "x"
                @test val[key] == 3
            end
        end
        @testset "inttype" begin
            @testset for T in [Int32, Int64, Int128, BigInt]
                val = JSON.parse(InputType[]("{\"x\": 3}"), inttype=T)
                @test isa(val, Dict{String, Any})
                @test length(val) == 1
                key = collect(keys(val))[1]
                @test string(key) == "x"
                value = val[key]
                @test value == 3
                @test typeof(value) == T
            end
            @testset begin
                teststr = """{"201736327611975630": 18005722827070440994}"""
                val = JSON.parse(InputType[](teststr), inttype=Int128)
                @test val == Dict{String,Any}("201736327611975630" => 18005722827070440994)
            end
        end
        @testset "floattype" begin
            @testset for T in [Float16, Float32, Float64, BigFloat]
                for pref in ("0", "-0", "1234234", "-1234234", "999999999999999999"),
                    frac in ("", ".123", ".000000000000000000000555", ".999"),
                    expo in vcat("", makeexplist()),
                    post in ("", "    ", "   \t", "\t", "\r", "\n", "    \r", "    \n")

                    str = string(pref, frac, expo)
                    res = tryparse(T, str)
                    (VERSION < v"0.7.0-DEV" ? isnull(res) : res == nothing) && continue
                    val = JSON.parse(InputType[]("{\"x\": $str$post}"), floattype=T)
                    @test isa(val, Dict{String, Any})
                    @test length(val) == 1
                    key = collect(keys(val))[1]
                    @test string(key) == "x"
                    value = val[key]
                    VT = typeof(value) <: Integer ? Int64 : T
                    @test value == parse(VT, str)
                    @test typeof(value) == VT
                end
            end
        end
        @testset for (str, val) in MISC
            @test JSON.parse(InputType[](str)) == val
        end
        @testset "Issue # 21" begin
            a = JSON.parse(InputType[](issue21))
            @test isa(a, Vector{Any})
            @test length(a) == 2
        end
        @testset "Issue # 26" begin
            @test JSON.parse(InputType[]("{\"a\":2e10}"))["a"] == 2e10
        end
        @testset "Issue # 57" begin
            @test(JSON.parse(InputType[]("{\"\U0001d712\":\"\\ud835\\udf12\"}"))["𝜒"] == "𝜒")
        end
        @testset "Issue # 109" begin
            let iob = IOBuffer()
                JSON.print(iob, t109(1))
                str = String(take!(iob))
                @test get(JSON.parse(InputType[](str)), "i", 0) == 1
            end
        end
        @testset "Issue # 163" begin
            @test Float32(JSON.parse(InputType[](json(2.1f-8)))) == 2.1f-8
        end
    end
end

@testset "Parse File" begin
    tmppath, io = mktemp()
    write(io, facebook)
    close(io)
    if Compat.Sys.iswindows()
        # don't use mmap on Windows, to avoid ERROR: unlink: operation not permitted (EPERM)
        @test haskey(JSON.parsefile(tmppath; use_mmap=false), "data")
    else
        @test haskey(JSON.parsefile(tmppath), "data")
    end
    rm(tmppath)
end
