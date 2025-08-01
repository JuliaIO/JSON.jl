using JSON, Test

# helper struct for testing reading json from files
struct File end

make(::Type{String}, x) = x
make(::Type{SubString{String}}, x) = SubString(x)
make(::Type{Vector{UInt8}}, x) = Vector{UInt8}(x)
make(::Type{IOBuffer}, x) = IOBuffer(x)
function make(::Type{File}, x)
    _, io = mktemp()
    write(io, x)
    seekstart(io)
    return io
end

function makefile(nm, x)
    dir = mktempdir()
    file = joinpath(dir, nm)
    open(file, "w") do io
        write(io, x)
    end
    return file
end

@testset "JSON.lazy" begin
    for T in (String, SubString{String}, IOBuffer, Vector{UInt8}, File)
        @test JSON.gettype(JSON.lazy(make(T, "1"))) == JSON.JSONTypes.NUMBER
        @test JSON.gettype(JSON.lazy(make(T, "true"))) == JSON.JSONTypes.TRUE
        @test JSON.gettype(JSON.lazy(make(T, "false"))) == JSON.JSONTypes.FALSE
        @test JSON.gettype(JSON.lazy(make(T, "null"))) == JSON.JSONTypes.NULL
        @test JSON.gettype(JSON.lazy(make(T, "[]"))) == JSON.JSONTypes.ARRAY
        @test JSON.gettype(JSON.lazy(make(T, "{}"))) == JSON.JSONTypes.OBJECT
        @test JSON.gettype(JSON.lazy(make(T, "\"\""))) == JSON.JSONTypes.STRING
        @test_throws ArgumentError JSON.lazy(make(T, "a"))
    end
    # lazyfile
    x = JSON.lazyfile(makefile("empty_object.json", "{}"))
    @test JSON.gettype(x) == JSON.JSONTypes.OBJECT
    @test length(x) == 0
    # LazyObject with all possible JSON types
    x = JSON.lazy("{\"a\": 1, \"b\": null, \"c\": true, \"d\": false, \"e\": \"\", \"f\": [], \"g\": {}}")
    @test length(x) == 7
    if VERSION >= v"1.7"
        @test sprint(show, x) == "LazyObject{String} with 7 entries:\n  \"a\" => JSON.LazyValue(1)\n  \"b\" => JSON.LazyValue(nothing)\n  \"c\" => JSON.LazyValue(true)\n  \"d\" => JSON.LazyValue(false)\n  \"e\" => JSON.LazyValue(\"\")\n  \"f\" => LazyValue[]\n  \"g\" => LazyObject{String}()"
    end
    i = 0
    foreach(x) do (k, v)
        i += 1
        @test k isa String
        @test v isa JSON.LazyValue
    end
    @test i == 7
    # LazyArray with all possible JSON types
    x = JSON.lazy("[1, null, true, false, \"\", [], {}]")
    @test length(x) == 7
    @test JSON.gettype(x[end]) == JSON.JSONTypes.OBJECT
    if VERSION >= v"1.7"
        @test sprint(show, x) == "7-element LazyArray{String}:\n JSON.LazyValue(1)\n JSON.LazyValue(nothing)\n JSON.LazyValue(true)\n JSON.LazyValue(false)\n JSON.LazyValue(\"\")\n LazyValue[]\n LazyObject{String}()"
    end
    i = 0
    foreach(x) do v
        i += 1
        @test v isa JSON.LazyValue
    end
    @test i == 7
    # error cases
    x = JSON.lazy("{}")
    @test_throws ArgumentError JSON.applyarray((i, v) -> nothing, x)
    @test_throws ArgumentError JSON.parsestring(x)
    x = JSON.lazy("{}"; allownan=true)
    @test_throws ArgumentError JSON.parsenumber(x)

    # lazy indexing selection support
    # examples from https://support.smartbear.com/alertsite/docs/monitors/api/endpoint/jsonpath.html
    json = """
    {
    "store": {
        "book": [
        {
            "category": "reference",
            "author": "Nigel Rees",
            "title": "Sayings of the Century",
            "price": 8.95
        },
        {
            "category": "fiction",
            "author": "Herman Melville",
            "title": "Moby Dick",
            "isbn": "0-553-21311-3",
            "price": 8.99
        },
        {
            "category": "fiction",
            "author": "J.R.R. Tolkien",
            "title": "The Lord of the Rings",
            "isbn": "0-395-19395-8",
            "price": 22.99
        }
        ],
        "bicycle": {
        "color": "red",
        "price": 19.95
        }
    },
    "expensive": 10
    }
    """
    x = JSON.lazy(json)
    @test propertynames(x) == [:store, :expensive]
    y = x.store[:][] # All direct properties of store (not recursive).
    @test length(y) == 2 && y[1] isa Vector{Any} && y[2] isa JSON.Object{String, Any}
    y = x.store.bicycle.color[] # The color of the bicycle in the store.
    @test y == "red"
    y = x[~, "price"][] # The prices of all items in the store.
    @test y == [8.95, 8.99, 22.99, 19.95]
    y = x.store.book[:][] # All books in the store.
    @test length(y) == 3 && eltype(y) == JSON.Object{String, Any}
    y = x[~, "book"][1].title[] # The titles of all books in the store.
    @test y == ["Sayings of the Century", "Moby Dick", "The Lord of the Rings"]
    y = x[~, "book"][1][1][] # The first book in the store.
    @test y == Dict("category" => "reference", "author" => "Nigel Rees", "title" => "Sayings of the Century", "price" => 8.95)
    y = x[~, "book"][1][1].author[] # The author of the first book in the store.
    @test y == "Nigel Rees"
    # @test_throws ArgumentError x[~, "book"][1].author[~]
    y = x[~, "book"][1][:, (i, z) -> z.author[] == "J.R.R. Tolkien"].title[] # The titles of all books by J.R.R. Tolkien
    @test y == ["The Lord of the Rings"]
    y = x[~, :][] # All properties of the root object flattened in one list/array
    @test length(y) == 17
    @test_throws KeyError x.foo
    @test_throws KeyError x.store.book[100]
    list = x.store.book[:]
    @test eltype(list) == Any
    @test isassigned(list, 1)
    @test list[:] === list
    @test length(list[[1, 3]]) == 2
    # test that we correctly skip over all kinds of values
    json = """
    {
        "a": 1,
        "a1": 3.14,
        "a2": 100000000000000000000000,
        "a3": 170141183460469231731687303715884105728,
        "a4": 1.7976931348623157e310,
        "b": null,
        "c": true,
        "d": false,
        "e": "hey there sailor",
        "f": [],
        "g": {},
        "h": [1, 2, 3],
        "i": {"a": 1, "b": 2},
        "j": [1, {"a": 1, "b": 2}, 3],
        "k": {"a": 1, "b": [1, 2, 3]},
        "l": [1, {"a": 1, "b": [1, 2, 3]}, 3],
        "m": {"a": 1, "b": {"a": 1, "b": 2}},
        "n": [1, {"a": 1, "b": {"a": 1, "b": 2}}, 3],
        "o": {"a": 1, "b": {"a": 1, "b": [1, 2, 3]}},
        "p": [1, {"a": 1, "b": {"a": 1, "b": [1, 2, 3]}}, 3],
        "q": {"a": 1, "b": {"a": 1, "b": {"a": 1, "b": 2}}},
        "r": [1, {"a": 1, "b": {"a": 1, "b": {"a": 1, "b": 2}}}, 3],
        "s": {"a": 1, "b": {"a": 1, "b": {"a": 1, "b": [1, 2, 3]}}},
        "t": [1, {"a": 1, "b": {"a": 1, "b": {"a": 1, "b": [1, 2, 3]}}}, 3],
        "z": 602
    }
    """
    x = JSON.lazy(json)
    @test x.z[] == 602
    @test JSON.isvalidjson(x)
    json = """
    [
        {
            "a": [1, 2, 3]
        },
        {
            "a": [1, 2, 3]
        }
    ]
    """
    x = JSON.lazy(json)
    @test x[~, "a"][] == [[1, 2, 3], [1, 2, 3]]
    @test x[:].a[] == [[1, 2, 3], [1, 2, 3]]
    @test JSON.isvalidjson(x)
end
