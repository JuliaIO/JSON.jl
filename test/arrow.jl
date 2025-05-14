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
@test arrow.json[3].obj.b === nothing
@test isequal(arrow.json[3].obj.c, [missing, 1, "hey"])
@test arrow.json[3].obj.d == [1.2, 3.4, 5.6]
@test isequal(arrow.json[3].arr, [missing, 1, "hey"])
@test arrow.json[3].arr2 == [1.2, 3.4, 5.6]
