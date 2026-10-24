using Test, JSON, Arrow

obj1 = JSON.parse("""
{
    "int": 1,
    "float": 2.1
}
""")

obj2 = JSON.parse("""
{
    "int": 1,
    "float": 2.1,
    "bool1": true,
    "bool2": false,
    "none": null,
    "str": "\\"hey there sailor\\"",
    "arr": [null, 1, "hey"],
    "arr2": [1.2, 3.4, 5.6]
}
""")

obj3 = JSON.parse("""
{
    "int": 1,
    "float": 2.1,
    "bool1": true,
    "bool2": false,
    "none": null,
    "str": "\\"hey there sailor\\"",
    "obj": {
                "a": 1,
                "b": null,
                "c": [null, 1, "hey"],
                "d": [1.2, 3.4, 5.6]
            },
    "arr": [null, 1, "hey"],
    "arr2": [1.2, 3.4, 5.6]
}
""")

tbl = (; json=[obj1, obj2, obj3])

arrow = Arrow.Table(Arrow.tobuffer(tbl))
@test arrow.json[1].int == 1
@test arrow.json[1].float == 2.1

@test arrow.json[2].int == 1
@test arrow.json[2].float == 2.1
@test arrow.json[2].bool1 == true
@test arrow.json[2].bool2 == false
@test arrow.json[2].none === missing
@test arrow.json[2].str == "\"hey there sailor\""
@test isequal(arrow.json[2].arr, [missing, 1, "hey"])
@test arrow.json[2].arr2 == [1.2, 3.4, 5.6]

@test arrow.json[3].int == 1
@test arrow.json[3].float == 2.1
@test arrow.json[3].bool1 == true
@test arrow.json[3].bool2 == false
@test arrow.json[3].none === missing
@test arrow.json[3].str == "\"hey there sailor\""
@test arrow.json[3].obj.a == 1
# a nested null reads back as missing, as a top-level one does
@test arrow.json[3].obj.b === missing
@test isequal(arrow.json[3].obj.c, [missing, 1, "hey"])
@test arrow.json[3].obj.d == [1.2, 3.4, 5.6]
@test isequal(arrow.json[3].arr, [missing, 1, "hey"])
@test arrow.json[3].arr2 == [1.2, 3.4, 5.6]

@testset "JSON.Object and JSONText columns" begin
    rt(col) = collect(Arrow.Table(Arrow.tobuffer((; c=col))).c)
    O = JSON.Object{String,Any}
    o(s) = JSON.parse(s)
    # missing rows stay missing
    @test isequal(rt(Union{Missing,O}[o("{\"a\":1}"), missing]), [JSON.Object(:a => 1), missing])
    @test isequal(rt(Union{Missing,O}[missing, o("{\"a\":1}")]), [missing, JSON.Object(:a => 1)])
    @test isequal(rt(Union{Missing,O}[missing, missing]), [missing, missing])
    # nested objects with different keys, and non-Any value types
    r = rt([o("{\"a\":{\"b\":1}}"), o("{\"a\":{\"b\":2,\"c\":3}}")])
    @test r[1].a.b == 1 && r[2].a.b == 2 && r[2].a.c == 3
    @test rt([JSON.parse("{\"a\":1}", JSON.Object{String,Int})])[1].a == 1
    # JSONText round-trips as its text
    @test rt([JSONText("{\"a\":1}"), JSONText("[1]")]) == [JSONText("{\"a\":1}"), JSONText("[1]")]
    @test isequal(rt(Union{Missing,JSONText}[JSONText("1"), missing]), [JSONText("1"), missing])
end
