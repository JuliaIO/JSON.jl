using JSON, StructUtils, UUIDs, Dates, Test

struct CustomJSONStyle <: JSON.JSONStyle end

struct A
    a::Int
    b::Int
    c::Int
    d::Int
end

@noarg mutable struct B
    a::Int
    b::Int
    c::Int
    d::Int
end

struct C
end

struct D
    a::Int
    b::Float64
    c::String
end

struct LotsOfFields
    x1::String
    x2::String
    x3::String
    x4::String
    x5::String
    x6::String
    x7::String
    x8::String
    x9::String
    x10::String
    x11::String
    x12::String
    x13::String
    x14::String
    x15::String
    x16::String
    x17::String
    x18::String
    x19::String
    x20::String
    x21::String
    x22::String
    x23::String
    x24::String
    x25::String
    x26::String
    x27::String
    x28::String
    x29::String
    x30::String
    x31::String
    x32::String
    x33::String
    x34::String
    x35::String
end

struct Wrapper
    x::NamedTuple{(:a, :b), Tuple{Int, String}}
end

@noarg mutable struct UndefGuy
    id::Int
    name::String
end

struct E
    id::Int
    a::A
end

@kwarg struct F
    id::Int
    rate::Float64
    name::String
end

@kwarg struct G
    id::Int
    rate::Float64
    name::String
    f::F
end

struct H
    id::Int
    name::String
    properties::Dict{String, Any}
    addresses::Vector{String}
end

@enum Fruit apple banana

struct I
    id::Int
    name::String
    fruit::Fruit
end

abstract type Vehicle end

struct Car <: Vehicle
    type::String
    make::String
    model::String
    seatingCapacity::Int
    topSpeed::Float64
end

struct Truck <: Vehicle
    type::String
    make::String
    model::String
    payloadCapacity::Float64
end

struct J
    id::Union{Int, Nothing}
    name::Union{String, Nothing}
    rate::Union{Int64, Float64}
end

struct K
    id::Int
    value::Union{Float64, Missing}
end

@kwarg struct System
    duration::Real = 0 # mandatory
    cwd::Union{Nothing, String} = nothing
    environment::Union{Nothing, Dict} = nothing
    batch::Union{Nothing, Dict} = nothing
    shell::Union{Nothing, Dict} = nothing
end

StructUtils.@defaults struct L
    id::Int
    first_name::String &(json=(name=:firstName,),)
    rate::Float64 = 33.3
end

StructUtils.@tags struct ThreeDates
    date::Date &(json=(dateformat=dateformat"yyyy_mm_dd",),)
    datetime::DateTime &(json=(dateformat=dateformat"yyyy/mm/dd HH:MM:SS",),)
    time::Time &(json=(dateformat=dateformat"HH/MM/SS",),)
end

struct M
    id::Int
    value::Union{Nothing,K}
end

struct Recurs
    id::Int
    value::Union{Nothing,Recurs}
end

struct N
    id::Int
    uuid::UUID
end

struct O
    id::Int
    name::Union{I,L,Missing,Nothing}
end

struct Point
    x::Int
    y::Int
end

@defaults struct P
    num::Int64
    foo::String = "bar"
end

# example from JSON.parse docstring
abstract type AbstractMonster end

struct Dracula <: AbstractMonster
    num_victims::Int
end

JSON.lower(x::Dracula) = (type="vampire", num_victims=x.num_victims)

struct Werewolf <: AbstractMonster
    witching_hour::DateTime
end

JSON.lower(x::Werewolf) = (type="werewolf", witching_hour=x.witching_hour)

JSON.@choosetype AbstractMonster x -> x.monster_type[] == "vampire" ? Dracula : Werewolf

@nonstruct struct Percent <: Number
    value::Float64
end

JSON.lift(::Type{Percent}, x) = Percent(Float64(x))
StructUtils.liftkey(::Type{Percent}, x::String) = Percent(parse(Float64, x))

@defaults struct FrankenStruct
    id::Int = 0
    name::String = "Jim"
    address::Union{Nothing, String} = nothing
    rate::Union{Missing, Float64} = missing
    type::Symbol = :a &(json=(name="franken_type",),)
    notsure::Any = nothing
    monster::AbstractMonster = Dracula(0)
    percent::Percent = Percent(0.0)
    birthdate::Date = Date(0) &(json=(dateformat="yyyy/mm/dd",),)
    percentages::Dict{Percent, Int} = Dict{Percent, Int}()
    json_properties::JSONText = JSONText("")
    matrix::Matrix{Float64} = Matrix{Float64}(undef, 0, 0)
end

@tags struct Q
    id::Int
    any::Any &(choosetype=x -> x.type[] == "int" ? @NamedTuple{type::String, value::Int} : x.type[] == "float" ? @NamedTuple{type::String, value::Float64} : @NamedTuple{type::String, value::String},)
end

@testset "JSON.parse" begin
    @testset "errors" begin
        # Unexpected character in array
        @test_throws ArgumentError JSON.lazy("[1,2,3/4,5,6,7]")[]
        # Unexpected character in object
        @test_throws ArgumentError JSON.lazy("{\"1\":2, \"2\":3 _ \"4\":5}")[]
        # Invalid escaped character
        @test_throws ArgumentError JSON.lazy("[\"alpha\\α\"]")[]
        # Invalid 'simple' and 'unknown value'
        @test_throws ArgumentError JSON.lazy("[tXXe]")[]
        @test_throws ArgumentError JSON.lazy("[fail]")[]
        @test_throws ArgumentError JSON.lazy("∞")[]
        # Invalid number
        @test_throws ArgumentError JSON.lazy("[5,2,-]")[]
        @test_throws ArgumentError JSON.lazy("[5,2,+β]")[]
        # Incomplete escape
        @test_throws ArgumentError JSON.lazy("\"\\")[]
        @test_throws ArgumentError JSON.lazy("[\"🍕\"_\"🍕\"")[]
        # incomplete surrogate pair *doesn't* throw, but resulting string is invalid utf8
        # https://github.com/JuliaIO/JSON.jl/issues/232
        x = JSON.parse("{\"id\":\"5\",\"name\":\"IllegalUnicodehalf-surrogateU+D800\",\"url\":\"http://www.example.com/#\\\\\\ud800\\\\\\u597D\",\"expect_url\":\"http://www.example.com/#\\\\\\uFFFD\\\\\\u597D\"}")
        @test !isvalid(x.url)
        @test x.url == "http://www.example.com/#\\\ud8000\\好"
    end # @testset "errors"

    # JSON.jl pre-1.0 compat
    x = JSON.parse("{}")
    @test isempty(x) && typeof(x) == JSON.Object{String, Any}
    x = JSON.parsefile(makefile("empty_object.json", "{}"))
    @test isempty(x) && typeof(x) == JSON.Object{String, Any}
    x = JSON.parsefile(makefile("empty_object.json", "{}"), Any)
    @test isempty(x) && typeof(x) == JSON.Object{String, Any}
    x = Dict{String, Any}()
    JSON.parsefile!(makefile("empty_object.json", "{}"), x)
    @test isempty(x)
    io = IOBuffer()
    write(io, "{}")
    seekstart(io)
    x = JSON.parse(io)
    @test isempty(x) && typeof(x) == JSON.Object{String, Any}
    seekstart(io)
    x = Dict{String, Any}()
    JSON.parse!(io, x)
    @test isempty(x)
    seekstart(io)
    @test JSON.isvalidjson(io)
    open(makefile("empty_object.json", "{}"), "r") do io
        x = Dict{String, Any}()
        JSON.parse!(io, x)
        @test isempty(x)
    end
    open(makefile("empty_object.json", "{}"), "r") do io
        @test JSON.isvalidjson(io)
    end
    @test JSON.isvalidjson("{}")
    @test !JSON.isvalidjson("{JSON")
    @test !JSON.isvalidjson("JSON")
    @test !JSON.isvalidjson(collect(codeunits("JSON")))
    x = JSON.parse("{}")
    @test isempty(x) && typeof(x) == JSON.Object{String, Any}
    @test_throws ArgumentError JSON.parse(JSON.LazyValue(".", 1, JSON.JSONTypes.OBJECT, JSON.LazyOptions(), true))
    x = JSON.lazy("1")
    @test_throws ArgumentError JSON.StructUtils.applyeach((k, v) -> nothing, x)
    x = JSON.parse("{\"a\": 1}")
    @test !isempty(x) && x["a"] == 1 && typeof(x) == JSON.Object{String, Any}
    x = JSON.parse("{\"a\": 1, \"b\": null, \"c\": true, \"d\": false, \"e\": \"\", \"f\": [], \"g\": {}}")
    @test !isempty(x) && x["a"] == 1 && x["b"] === nothing && x["c"] === true && x["d"] === false && x["e"] == "" && x["f"] == Any[] && x["g"] == JSON.Object{String, Any}()
    # custom dicttype
    x = JSON.parse("{\"a\": 1, \"b\": null, \"c\": true, \"d\": false, \"e\": \"\", \"f\": [], \"g\": {}}"; dicttype=Dict{String, Any})
    # test that x isa Dict and nested x.g is also a Dict
    @test x isa Dict{String, Any} && !isempty(x) && x["a"] == 1 && x["b"] === nothing && x["c"] === true && x["d"] === false && x["e"] == "" && x["f"] == Any[] && x["g"] == Dict{String, Any}() && typeof(x["g"]) == Dict{String, Any}
    # alternative key types
    x = JSON.parse("{\"a\": 1, \"b\": null}"; dicttype=JSON.Object{Symbol, Any})
    @test x isa JSON.Object{Symbol, Any} && !isempty(x) && x[:a] == 1 && x[:b] === nothing
    x = JSON.parse("{\"apple\": 1, \"banana\": null}"; dicttype=JSON.Object{Fruit, Any})
    @test x isa JSON.Object{Fruit, Any} && !isempty(x) && x[apple] == 1 && x[banana] === nothing
    x = JSON.parse("[]")
    @test isempty(x) && x == Any[]
    x = JSON.parse("[1, null, true, false, \"\", [], {}]")
    @test !isempty(x) && x[1] == 1 && x[2] === nothing && x[3] === true && x[4] === false && x[5] == "" && x[6] == Any[] && x[7] == JSON.Object{String, Any}()
    x = JSON.parse("1")
    @test x == 1
    x = JSON.parse("true")
    @test x === true
    x = JSON.parse("false")
    @test x === false
    x = JSON.parse("null")
    @test x === nothing
    x = JSON.parse("\"\"")
    @test x == ""
    x = JSON.parse("\"a\"")
    @test x == "a"
    x = JSON.parse("\"\\\"\"")
    @test x == "\""
    x = JSON.parse("\"\\\\\"")
    @test x == "\\"
    x = JSON.parse("\"\\/\"")
    @test x == "/"
    x = JSON.parse("\"\\b\"")
    @test x == "\b"
    x = JSON.parse("\"\\f\"")
    @test x == "\f"
    x = JSON.parse("\"\\n\"")
    @test x == "\n"
    x = JSON.parse("\"\\r\"")
    @test x == "\r"
    x = JSON.parse("\"\\t\"")
    @test x == "\t"
    x = JSON.parse("\"\\u0000\"")
    @test x == "\0"
    x = JSON.parse("\"\\uD83D\\uDE00\"")
    @test x == "😀"
    x = JSON.parse("\"\\u0061\"")
    @test x == "a"
    x = JSON.parse("\"\\u2028\"")
    @test x == "\u2028"
    x = JSON.parse("\"\\u2029\"")
    @test x == "\u2029"
    @test_throws ArgumentError JSON.parse("nula")
    @test_throws ArgumentError JSON.parse("nul")
    @test_throws ArgumentError JSON.parse("trub")
    # allownan for parsing normally invalid json values
    @test JSON.parse("NaN"; allownan=true) === NaN
    @test JSON.parse("Inf"; inf="Inf", allownan=true) === Inf
    # jsonlines support
    @test JSON.parse("1"; jsonlines=true) == [1]
    @test JSON.parse("1 \t"; jsonlines=true) == [1]
    @test JSON.parse("1 \t\r"; jsonlines=true) == [1]
    @test JSON.parse("1 \t\r\n"; jsonlines=true) == [1]
    @test JSON.parse("1 \t\r\nnull"; jsonlines=true) == [1, nothing]
    @test JSON.lazy("1\nnull"; jsonlines=true)[] == [1, nothing]
    @test JSON.parse("1\n\n2\n\n"; jsonlines=true) == [1, 2]
    # auto-detected jsonlines
    @test JSON.parsefile(makefile("jsonlines.jsonl", "1\n2\n3\n4")) == [1, 2, 3, 4]
    # missing newline
    @test_throws ArgumentError JSON.parse("1 \t\bnull"; jsonlines=true)
    @test_throws ArgumentError JSON.parse(""; jsonlines=true)
    @test JSON.parse("1\n2\n3\n4"; jsonlines=true) == [1, 2, 3, 4]
    @test JSON.parse("[1]\n[2]\n[3]\n[4]"; jsonlines=true) == [[1], [2], [3], [4]]
    @test JSON.parse("{\"a\": 1}\n{\"b\": 2}\n{\"c\": 3}\n{\"d\": 4}"; jsonlines=true) == [Dict("a" => 1), Dict("b" => 2), Dict("c" => 3), Dict("d" => 4)]
    @test JSON.parse("""
    ["Name", "Session", "Score", "Completed"]
    ["Gilbert", "2013", 24, true]
    ["Alexa", "2013", 29, true]
    ["May", "2012B", 14, false]
    ["Deloise", "2012A", 19, true]
    """; jsonlines=true, allownan=true) ==
    [["Name", "Session", "Score", "Completed"],
     ["Gilbert", "2013", 24, true],
     ["Alexa", "2013", 29, true],
     ["May", "2012B", 14, false],
     ["Deloise", "2012A", 19, true]]
    @test JSON.parse("""
    {"name": "Gilbert", "wins": [["straight", "7♣"], ["one pair", "10♥"]]}
    {"name": "Alexa", "wins": [["two pair", "4♠"], ["two pair", "9♠"]]}
    {"name": "May", "wins": []}
    {"name": "Deloise", "wins": [["three of a kind", "5♣"]]}
    """; jsonlines=true) ==
    [Dict("name" => "Gilbert", "wins" => [["straight", "7♣"], ["one pair", "10♥"]]),
     Dict("name" => "Alexa", "wins" => [["two pair", "4♠"], ["two pair", "9♠"]]),
     Dict("name" => "May", "wins" => []),
     Dict("name" => "Deloise", "wins" => [["three of a kind", "5♣"]])]
    
    @test_throws ArgumentError JSON.parse("{\"a\" 1}")
    @test_throws ArgumentError JSON.parse("123a")
    @test_throws ArgumentError JSON.parse("123.4a")
    @test_throws ArgumentError JSON.parse("[1]e")
    @test_throws ArgumentError JSON.parse("\"abc\"e+")
    @test_throws ArgumentError JSON.parse("1a\n2\n3"; jsonlines=true)
    @test_throws ArgumentError JSON.parse("1\n2\n3a"; jsonlines=true)
    @test_throws ArgumentError JSON.parse(" 123a")

    @testset "Number parsing" begin
        @test JSON.parse("1") === Int64(1)
        @test JSON.parse("1 ") === Int64(1)
        @test JSON.parse("-1") === Int64(-1)
        @test_throws ArgumentError JSON.parse("1.")
        @test_throws ArgumentError JSON.parse("-1.")
        @test_throws ArgumentError JSON.parse("-1. ")
        @test JSON.parse("1.1") === 1.1
        @test JSON.parse("1e1") === 10.0
        @test JSON.parse("1E23") === 1e23
        # @test JSON.parse("1f23") === 1f23
        # @test JSON.parse("1F23") === 1f23
        @test JSON.parse("100000000000000000000000") == 100000000000000000000000
        for T in (Int8, Int16, Int32, Int64, Int128)
            @test JSON.parse(string(T(1))) == T(1)
            @test JSON.parse(string(T(-1))) == T(-1)
        end

        @test JSON.parse("428.0E+03") === 428e3
        @test JSON.parse("1e+1") === 10.0
        @test JSON.parse("1e-1") === 0.1
        @test JSON.parse("1.1e1") === 11.0
        @test JSON.parse("1.1e+1") === 11.0
        @test JSON.parse("1.1e-1") === 0.11
        @test JSON.parse("1.1e-01") === 0.11
        @test JSON.parse("1.1e-001") === 0.11
        @test JSON.parse("1.1e-0001") === 0.11
        @test JSON.parse("9223372036854775797") === 9223372036854775797
        @test JSON.parse("9223372036854775798") === 9223372036854775798
        @test JSON.parse("9223372036854775799") === 9223372036854775799
        @test JSON.parse("9223372036854775800") === 9223372036854775800
        @test JSON.parse("9223372036854775801") === 9223372036854775801
        @test JSON.parse("9223372036854775802") === 9223372036854775802
        @test JSON.parse("9223372036854775803") === 9223372036854775803
        @test JSON.parse("9223372036854775804") === 9223372036854775804
        @test JSON.parse("9223372036854775805") === 9223372036854775805
        @test JSON.parse("9223372036854775806") === 9223372036854775806
        @test JSON.parse("9223372036854775807") === 9223372036854775807
        # promote to BigInt
        x = JSON.parse("9223372036854775808")
        # only == here because BigInt don't compare w/ ===
        @test x isa BigInt && x == 9223372036854775808
        x = JSON.parse("170141183460469231731687303715884105727")
        @test x isa BigInt && x == 170141183460469231731687303715884105727
        x = JSON.parse("170141183460469231731687303715884105728")
        @test x isa BigInt && x == 170141183460469231731687303715884105728
        # BigFloat
        @test JSON.parse("1.7976931348623157e310") == big"1.7976931348623157e310"

        # zeros
        @test JSON.parse("0") === Int64(0)
        @test JSON.parse("0e0") === 0.0
        @test JSON.parse("-0e0") === -0.0
        @test JSON.parse("0e-0") === 0.0
        @test JSON.parse("-0e-0") === -0.0
        @test JSON.parse("0e+0") === 0.0
        @test JSON.parse("-0e+0") === -0.0
        @test JSON.parse("0e+01234567890123456789") == big"0.0"
        @test JSON.parse("0.00e-01234567890123456789") == big"0.0"
        @test JSON.parse("-0e+01234567890123456789") == big"0.0"
        @test JSON.parse("-0.00e-01234567890123456789") == big"0.0"
        @test JSON.parse("0e291") === 0.0
        @test JSON.parse("0e292") === 0.0
        @test JSON.parse("0e347") == big"0.0"
        @test JSON.parse("0e348") == big"0.0"
        @test JSON.parse("-0e291") === 0.0
        @test JSON.parse("-0e292") === 0.0
        @test JSON.parse("-0e347") == big"0.0"
        @test JSON.parse("-0e348") == big"0.0"
        @test JSON.parse("2e-324") === 0.0
        # extremes
        @test JSON.parse("1e310") == big"1e310"
        @test JSON.parse("-1e310") == big"-1e310"
        @test JSON.parse("1e-305") === 1e-305
        @test JSON.parse("1e-306") === 1e-306
        @test JSON.parse("1e-307") === 1e-307
        @test JSON.parse("1e-308") === 1e-308
        @test JSON.parse("1e-309") === 1e-309
        @test JSON.parse("1e-310") === 1e-310
        @test JSON.parse("1e-322") === 1e-322
        @test JSON.parse("5e-324") === 5e-324
        @test JSON.parse("4e-324") === 5e-324
        @test JSON.parse("3e-324") === 5e-324
        # errors
        @test_throws ArgumentError JSON.parse("1e")
        @test_throws ArgumentError JSON.parse("1.0ea")
        @test_throws ArgumentError JSON.parse("1e+")
        @test_throws ArgumentError JSON.parse("1e-")
        @test_throws ArgumentError JSON.parse(".")
        @test_throws ArgumentError JSON.parse("1.a")
        @test_throws ArgumentError JSON.parse("1e1.")
        @test_throws ArgumentError JSON.parse("-")
        @test_throws ArgumentError JSON.parse("1.1.")
        @test_throws ArgumentError JSON.parse("+0e0")
        @test_throws ArgumentError JSON.parse("+0e+0")
        @test_throws ArgumentError JSON.parse("+0e-0")
        @test_throws ArgumentError JSON.parse(".1")
        @test_throws ArgumentError JSON.parse("+1")
    end
    @testset "JSON.parse with types" begin
        obj = JSON.parse("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", A)
        @test obj == A(1, 2, 3, 4)
        # test order doesn't matter
        obj2 = JSON.parse("""{ "d": 1,"b": 2,"c": 3,"a": 4}""", A)
        @test obj2 == A(4, 2, 3, 1)
        # NamedTuple
        obj = JSON.parse("""{ "d": 1,"b": 2,"c": 3,"a": 4}""", NamedTuple{(:a, :b, :c, :d), Tuple{Int, Int, Int, Int}})
        @test obj == (a = 4, b = 2, c = 3, d = 1)
        @test JSON.parse("{}", C) === C()
        # we also support materializing singleton from JSON.json output
        @test JSON.parse("\"C()\"", C) === C()
        obj = B()
        JSON.parse!("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", obj)
        @test obj.a == 1 && obj.b == 2 && obj.c == 3 && obj.d == 4
        obj = JSON.parse("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", B)
        @test obj.a == 1 && obj.b == 2 && obj.c == 3 && obj.d == 4
        # can materialize json array into struct assuming field order
        obj = JSON.parse("""[1, 2, 3, 4]""", A)
        @test obj == A(1, 2, 3, 4)
        # must be careful though because we don't check that the array is the same length as the struct
        @test JSON.parse("""[1, 2, 3, 4, 5]""", A) == A(1, 2, 3, 4)
        @test_throws Any JSON.parse("""[1, 2, 3]""", A)
        # materialize singleton from empty json array
        @test JSON.parse("""[]""", C) == C()
        # materialize mutable from json array
        obj = JSON.parse("""[1, 2, 3, 4]""", B)
        @test obj.a == 1 && obj.b == 2 && obj.c == 3 && obj.d == 4
        obj = B()
        JSON.parse!("""[1, 2, 3, 4]""", obj)
        @test obj.a == 1 && obj.b == 2 && obj.c == 3 && obj.d == 4
        # materialize kwdef from json array
        obj = JSON.parse("""[1, 3.14, "hey there sailor"]""", F)
        @test obj == F(1, 3.14, "hey there sailor")
        # materialize NamedTuple from json array
        obj = JSON.parse("""[1, 3.14, "hey there sailor"]""", NamedTuple{(:id, :rate, :name), Tuple{Int, Float64, String}})
        @test obj == (id = 1, rate = 3.14, name = "hey there sailor")
        # materialize Tuple from json array
        obj = JSON.parse("""[1, 3.14, "hey there sailor"]""", Tuple{Int, Float64, String})
        @test obj == (1, 3.14, "hey there sailor")
        obj = JSON.parse("""{ "a": 1,"b": 2.0,"c": "3"}""", Tuple{Int, Float64, String})
        @test obj == (1, 2.0, "3")
        obj = JSON.parse("""{ "a": 1,"b": 2.0,"c": "3"}""", D)
        @test obj == D(1, 2.0, "3")
        obj = JSON.parse("""{ "x1": "1","x2": "2","x3": "3","x4": "4","x5": "5","x6": "6","x7": "7","x8": "8","x9": "9","x10": "10","x11": "11","x12": "12","x13": "13","x14": "14","x15": "15","x16": "16","x17": "17","x18": "18","x19": "19","x20": "20","x21": "21","x22": "22","x23": "23","x24": "24","x25": "25","x26": "26","x27": "27","x28": "28","x29": "29","x30": "30","x31": "31","x32": "32","x33": "33","x34": "34","x35": "35"}""", LotsOfFields)
        @test obj == LotsOfFields("1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35")
        obj = JSON.parse("""{ "x": {"a": 1, "b": "2"}}""", Wrapper)
        @test obj == Wrapper((a=1, b="2"))
        obj = JSON.parse!("""{ "id": 1, "name": "2"}""", UndefGuy)
        @test obj.id == 1 && obj.name == "2"
        obj = JSON.parse!("""{ "id": 1}""", UndefGuy)
        @test obj.id == 1 && !isdefined(obj, :name)
        obj = JSON.parse("""{ "id": 1, "a": {"a": 1, "b": 2, "c": 3, "d": 4}}""", E)
        @test obj == E(1, A(1, 2, 3, 4))
        obj = JSON.parse("""{ "id": 1, "rate": 2.0, "name": "3"}""", F)
        @test obj == F(1, 2.0, "3")
        obj = JSON.parse("""{ "id": 1, "rate": 2.0, "name": "3", "f": {"id": 1, "rate": 2.0, "name": "3"}}""", G)
        @test obj == G(1, 2.0, "3", F(1, 2.0, "3"))
        # Dict/Array fields
        obj = JSON.parse("""{ "id": 1, "name": "2", "properties": {"a": 1, "b": 2}, "addresses": ["a", "b"]}""", H)
        @test obj.id == 1 && obj.name == "2" && obj.properties == Dict("a" => 1, "b" => 2) && obj.addresses == ["a", "b"]
        # Enum
        @test JSON.parse("\"apple\"", Fruit) == apple
        @test JSON.parse("""{"id": 1, "name": "2", "fruit": "banana"}  """, I) == I(1, "2", banana)
        # abstract type
        @test JSON.parse("""{"id": 1, "name": "2", "fruit": "banana"}  """, Any) == JSON.Object("id" => 1, "name" => "2", "fruit" => "banana")
        @test JSON.parse("""{"id": 1, "f": {"id": 1, "rate": 2.0, "ints": [1, 2, 3]}}""", @NamedTuple{id::Int, f::Any}) == (id = 1, f = JSON.Object("id" => 1, "rate" => 2.0, "ints" => [1, 2, 3]))

        JSON.@choosetype Vehicle x -> x.type[] == "car" ? Car : x.type[] == "truck" ? Truck : throw(ArgumentError("Unknown vehicle type: $(x.type[])"))

        @test JSON.parse("""{"type": "car","make": "Mercedes-Benz","model": "S500","seatingCapacity": 5,"topSpeed": 250.1}""", Vehicle) == Car("car", "Mercedes-Benz", "S500", 5, 250.1)
        @test JSON.parse("""{"type": "truck","make": "Isuzu","model": "NQR","payloadCapacity": 7500.5}""", Vehicle) == Truck("truck", "Isuzu", "NQR", 7500.5)
        # union
        @test JSON.parse("""{"id": 1, "name": "2", "rate": 3}""", J) == J(1, "2", Int64(3))
        @test JSON.parse("""{"id": null, "name": null, "rate": 3.14}""", J) == J(nothing, nothing, 3.14)
        # test K
        @test JSON.parse("""{"id": 1, "value": null}""", K) == K(1, missing)
        # Real
        @test JSON.parse("""{"duration": 3600.0}""", System) == System(duration=3600.0)
        # struct + jsonlines
        for raw in [
            """
            { "a": 1,  "b": 3.14,  "c": "hey" }
            { "a": 2,  "b": 6.28,  "c": "hi"  }
            """,
            # No newline at end
            """
            { "a": 1,  "b": 3.14,  "c": "hey" }
            { "a": 2,  "b": 6.28,  "c": "hi"  }""",
            # No newline, extra whitespace at end
            """
            { "a": 1,  "b": 3.14,  "c": "hey" }
            { "a": 2,  "b": 6.28,  "c": "hi"  }   """,
            # Whitespace at start of line
            """
              { "a": 1,  "b": 3.14,  "c": "hey" }
              { "a": 2,  "b": 6.28,  "c": "hi"  }
            """,
            # Extra whitespace at beginning, end of lines, end of string
            " { \"a\": 1,  \"b\": 3.14,  \"c\": \"hey\" }  \n" *
            "  { \"a\": 2,  \"b\": 6.28,  \"c\": \"hi\"  }  \n  ",
        ]
            for nl in ("\n", "\r", "\r\n")
                jsonl = replace(raw, "\n" => nl)
                dss = JSON.parse(jsonl, Vector{D}, jsonlines=true)
                @test length(dss) == 2
                @test dss[1].a == 1
                @test dss[1].b == 3.14
                @test dss[1].c == "hey"
                @test dss[2].a == 2
                @test dss[2].b == 6.28
                @test dss[2].c == "hi"
            end
        end
        # test L
        @test JSON.parse("""{"id": 1, "firstName": "george", "first_name": "harry"}""", L) == L(1, "george", 33.3)
        # test Char
        @test JSON.parse("\"a\"", Char) == 'a'
        @test JSON.parse("\"\u2200\"", Char) == '∀'
        @test_throws ArgumentError JSON.parse("\"ab\"", Char)
        # test UUID
        @test JSON.parse("\"ffffffff-ffff-ffff-ffff-ffffffffffff\"", UUID) == UUID(typemax(UInt128))
        # test Symbol
        @test JSON.parse("\"a\"", Symbol) == :a
        # test VersionNumber
        @test JSON.parse("\"1.2.3\"", VersionNumber) == v"1.2.3"
        # test Regex
        @test JSON.parse("\"1.2.3\"", Regex) == r"1.2.3"
        # test Dates
        @test JSON.parse("\"2023-02-23T22:39:02\"", DateTime) == DateTime(2023, 2, 23, 22, 39, 2)
        @test JSON.parse("\"2023-02-23\"", Date) == Date(2023, 2, 23)
        @test JSON.parse("\"22:39:02\"", Time) == Time(22, 39, 2)
        @test JSON.parse("{\"date\":\"2023_02_23\",\"datetime\":\"2023/02/23 12:34:56\",\"time\":\"12/34/56\"}", ThreeDates) ==
            ThreeDates(Date(2023, 2, 23), DateTime(2023, 2, 23, 12, 34, 56), Time(12, 34, 56))
        # test Array w/ lifted value
        @test isequal(JSON.parse("[null,null]", Vector{Missing}), [missing, missing])
        # test Matrix
        @test JSON.parse("[[1,3],[2,4]]", Matrix{Int}) == [1 2; 3 4]
        @test JSON.parse("{\"a\": [[1,3],[2,4]]}", NamedTuple{(:a,),Tuple{Matrix{Int}}}) == (a=[1 2; 3 4],)
        # test Matrix w/ lifted value
        @test isequal(JSON.parse("[[null,null],[null,null]]", Matrix{Missing}), [missing missing; missing missing])
        # test lift on Dict values
        obj = JSON.parse("""{\"ffffffff-ffff-ffff-ffff-ffffffffffff\": null,\"ffffffff-ffff-ffff-ffff-fffffffffffe\": null}""", Dict{UUID,Missing})
        @test obj[UUID(typemax(UInt128))] === missing
        @test obj[UUID(typemax(UInt128) - 0x01)] === missing
        # parse! with custom dicttype
        obj = Dict{String, Any}()
        JSON.parse!("""{"a": {"a": 1, "b": 2}, "b": {"a": 3, "b": 4}}""", obj; dicttype=Dict{String, Any})
        @test obj["a"] == Dict("a" => 1, "b" => 2)
        @test obj["b"] == Dict("a" => 3, "b" => 4)
        # nested union struct field
        @test JSON.parse("""{"id": 1, "value": {"id": 1, "value": null}}""", M) == M(1, K(1, missing))
        # recusrive field materialization
        x = JSON.parse("""{ "id": 1, "value": { "id": 2 } }""", Recurs)
        @test x == Recurs(1, Recurs(2, nothing))
        # multidimensional arrays
        # "[[1.0],[2.0]]" => (1, 2)
        m = Matrix{Float64}(undef, 1, 2)
        m[1] = 1
        m[2] = 2
        @test JSON.parse("[[1.0],[2.0]]", Matrix{Float64}) == m
        # "[[1.0,2.0]]" => (2, 1)
        m = Matrix{Float64}(undef, 2, 1)
        m[1] = 1
        m[2] = 2
        @test JSON.parse("[[1.0,2.0]]", Matrix{Float64}) == m
        # "[[[1.0]],[[2.0]]]" => (1, 1, 2)
        m = Array{Float64}(undef, 1, 1, 2)
        m[1] = 1
        m[2] = 2
        @test JSON.parse("[[[1.0]],[[2.0]]]", Array{Float64, 3}) == m
        # "[[[1.0],[2.0]]]" => (1, 2, 1)
        m = Array{Float64}(undef, 1, 2, 1)
        m[1] = 1
        m[2] = 2
        @test JSON.parse("[[[1.0],[2.0]]]", Array{Float64, 3}) == m
        # "[[[1.0,2.0]]]" => (2, 1, 1)
        m = Array{Float64}(undef, 2, 1, 1)
        m[1] = 1
        m[2] = 2
        @test JSON.parse("[[[1.0,2.0]]]", Array{Float64, 3}) == m
        m = Array{Float64}(undef, 1, 2, 3)
        m[1] = 1
        m[2] = 2
        m[3] = 3
        m[4] = 4
        m[5] = 5
        m[6] = 6
        @test JSON.parse("[[[1.0],[2.0]],[[3.0],[4.0]],[[5.0],[6.0]]]", Array{Float64, 3}) == m
        # 0-dimensional array
        m = Array{Float64,0}(undef)
        m[1] = 1.0
        @test JSON.parse("1.0", Array{Float64,0}) == m
        # test custom JSONStyle
        # StructUtils.lift(::CustomJSONStyle, ::Type{UUID}, x) = UUID(UInt128(x))
        # @test JSON.parse("340282366920938463463374607431768211455", UUID; style=CustomJSONStyle()) == UUID(typemax(UInt128))
        # @test JSON.parse("{\"id\": 0, \"uuid\": 340282366920938463463374607431768211455}", N; style=CustomJSONStyle()) == N(0, UUID(typemax(UInt128)))
        # tricky unions
        @test JSON.parse("{\"id\":0}", O) == O(0, nothing)
        @test JSON.parse("{\"id\":0,\"name\":null}", O) == O(0, missing)
        # StructUtils.choosetype(::CustomJSONStyle, ::Type{Union{I,L,Missing,Nothing}}, val) = JSON.gettype(val) == JSON.JSONTypes.NULL ? Missing : hasproperty(val, :fruit) ? I : L
        # @test JSON.parse("{\"id\":0,\"name\":{\"id\":1,\"name\":\"jim\",\"fruit\":\"apple\"}}", O; style=CustomJSONStyle()) == O(0, I(1, "jim", apple))
        # @test JSON.parse("{\"id\":0,\"name\":{\"id\":1,\"firstName\":\"jim\",\"rate\":3.14}}", O; style=CustomJSONStyle()) == O(0, L(1, "jim", 3.14))

        StructUtils.liftkey(::JSON.JSONStyle, ::Type{Point}, x::String) = Point(parse(Int, split(x, "_")[1]), parse(Int, split(x, "_")[2]))
        @test JSON.parse("{\"1_2\":\"hi\"}", Dict{Point, String}) == Dict(Point(1, 2) => "hi")
        # https://github.com/quinnj/JSON3.jl/issues/138
        @test JSON.parse("""{"num": 42}""", P) == P(42, "bar")
    end
    x = JSON.parse("[1,2,3]", JSONText)
    @test x == JSONText("[1,2,3]")
    # frankenstruct
    json = """
        {
            "id": 1,
            "address": "123 Main St",
            "rate": null,
            "franken_type": "b",
            "notsure": {"key": "value"},
            "monster": {
                "monster_type": "vampire",
                "num_victims": 10
            },
            "percent": 0.1,
            "birthdate": "2023/10/01",
            "percentages": {
                "0.1": 1,
                "0.2": 2
            },
            "json_properties": {"key": "value"},
            "matrix": [[1.0, 2.0], [3.0, 4.0]],
            "extra_key": "extra_value"
        }
        """
    fr = JSON.parse(json, FrankenStruct)
    # FrankenStruct(1, "Jim", "123 Main St", missing, :b, JSON.Object{String, Any}("key" => "value"), Dracula(10), Percent(0.1), Date("2023-10-01"), Dict{Percent, Int64}(Percent(0.2) => 2, Percent(0.1) => 1), JSONText("{\"key\": \"value\"}"), [1.0 3.0; 2.0 4.0])
    @test fr.id == 1
    @test fr.name == "Jim"
    @test fr.address == "123 Main St"
    @test fr.rate === missing
    @test fr.type == :b
    @test fr.notsure == JSON.Object{String, Any}("key" => "value")
    @test fr.monster == Dracula(10)
    @test fr.percent == Percent(0.1)
    @test fr.birthdate == Date("2023-10-01")
    @test fr.percentages == Dict(Percent(0.2) => 2, Percent(0.1) => 1)
    @test fr.json_properties == JSONText("{\"key\": \"value\"}")
    @test fr.matrix == [1.0 3.0; 2.0 4.0]
    # test custom JSONStyle overload
    JSON.lift(::CustomJSONStyle, ::Type{Rational}, x) = Rational(x.num[], x.den[])
    @test JSON.parse("{\"num\": 1,\"den\":3}", Rational; style=CustomJSONStyle()) == 1//3
    @test isequal(JSON.parse("{\"num\": 1,\"den\":null}", @NamedTuple{num::Int, den::Union{Int, Missing}}; null=missing, style=StructUtils.DefaultStyle()), (num=1, den=missing))
    # choosetype field tag on Any struct field
    @test JSON.parse("{\"id\":1,\"any\":{\"type\":\"int\",\"value\":10}}", Q) == Q(1, (type="int", value=10))
    @test JSON.parse("{\"id\":1,\"any\":{\"type\":\"float\",\"value\":3.14}}", Q) == Q(1, (type="float", value=3.14))
    @test JSON.parse("{\"id\":1,\"any\":{\"type\":\"string\",\"value\":\"hi\"}}", Q) == Q(1, (type="string", value="hi"))
    # extra tests for tuples since we have a custom implementation
    @test JSON.parse("[1,2,3]", Tuple{Int, Int, Int}) == (1, 2, 3)
    @test JSON.parse("[1,2,3, 4]", Tuple{Int, Int, Int}) == (1, 2, 3)
    @test_throws ArgumentError JSON.parse("[]", Tuple{Int, Int, Int})
    @test_throws ArgumentError JSON.parse("[1,2]", Tuple{Int, Int, Int})
    @test JSON.parse("{\"a\":1,\"b\":2,\"c\":3}", Tuple{Int, Int, Int}) == (1, 2, 3)
    @test JSON.parse("{\"a\":1,\"b\":2,\"c\":3,\"d\":4}", Tuple{Int, Int, Int}) == (1, 2, 3)
    @test_throws ArgumentError JSON.parse("{}", Tuple{Int, Int, Int})
    @test_throws ArgumentError JSON.parse("{\"a\":1,\"b\":2}", Tuple{Int, Int, Int})
end
