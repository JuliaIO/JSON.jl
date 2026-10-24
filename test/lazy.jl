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
    # printing a long array finds its elements once, not once per element (20,000: 70 s before)
    long = JSON.lazy("[" * join(fill("1", 20_000), ",") * "]")
    t = @elapsed(shown = sprint(show, long))
    @test count(==('\n'), shown) == 20_000
    @test t < 5
    # displaying it records a position per element, not a LazyValue (~80 bytes) per element
    long = JSON.lazy("[" * join(fill("1", 100_000), ",") * "]")
    io = IOContext(IOBuffer(), :limit => true, :displaysize => (24, 80))
    show(io, MIME"text/plain"(), long)
    @test @allocated(show(io, MIME"text/plain"(), long)) < 48 * 100_000
    # the lines of a jsonlines array display as ordinary values
    @test sprint(show, JSON.lazy("[1]\n{}"; jsonlines=true)) == "2-element LazyArray{String}:\n LazyValue[JSON.LazyValue(1)]\n LazyObject{String}()"
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

    str = JSON.lazy("\"alpha\"")
    key, _ = JSON.parsestring(str)
    @test key == "alpha"
    @test "alpha" == key
    @test isequal(key, "alpha")
    @test isequal("alpha", key)
    @test hash(key) == hash("alpha")
    @test haskey(Dict{Any,Int}(key => 1), "alpha")
    @test "alpha" in Set{Any}([key])
    # strings with no `pointer`
    @test key == Test.GenericString("alpha")
    @test key != Test.GenericString("alph")
    @test JSON.lazy("{\"a\":1}")[lazy"a"][] == 1

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

# byte vectors that are not a stride-1, 1-based block of memory
struct OffsetBytes <: AbstractVector{UInt8}
    data::Vector{UInt8}
end
Base.axes(b::OffsetBytes) = (Base.IdentityUnitRange(6:5 + length(b.data)),)
Base.size(b::OffsetBytes) = size(b.data)
Base.getindex(b::OffsetBytes, i::Int) = b.data[i - 5]

struct PlainBytes <: AbstractVector{UInt8}
    data::Vector{UInt8}
end
Base.size(b::PlainBytes) = size(b.data)
Base.getindex(b::PlainBytes, i::Int) = b.data[i]

@testset "byte vector layouts" begin
    bytes = Vector{UInt8}("x[1,2]")
    # offset axes used to be read from position 1: wrong values or reads outside the array
    @test JSON.parse(OffsetBytes(Vector{UInt8}("[1,2]"))) == [1, 2]
    @test JSON.isvalidjson(OffsetBytes(Vector{UInt8}("[1,2]")))
    @test_throws ArgumentError JSON.parse(OffsetBytes(Vector{UInt8}("[1,")))
    # these used to throw from `strides`
    @test JSON.parse(view(bytes, [2, 3, 4, 5, 6])) == [1, 2]
    @test JSON.parse(UInt8('1'):UInt8('3')) == 123
    @test JSON.parse(PlainBytes(Vector{UInt8}("{\"a\":[1]}"))) == Dict("a" => [1])
    # stride-1 layouts are still parsed in place
    @test JSON.parse(view(Vector{UInt8}("[ 1 , 2 ]"), 1:2:9)) == [1, 2]
    @test JSON.lazy(view(bytes, 2:6)) isa JSON.LazyValue{<:SubArray}
    @test JSON.lazy(view(bytes, 2:1:6)) isa JSON.LazyValue{<:SubArray}
    @test JSON.parse(view(reshape(Vector{UInt8}("[1][2]"), 3, 2), :, 2)) == [2]
    @test JSON.parse(codeunits("[3]")) == [3]
end

@testset "lazy callbacks and keys" begin
    # foreach ignores what `f` returns (an Int used to be read as the next parse position)
    seen = Int[]
    foreach(v -> (push!(seen, v[]); v[]), JSON.lazy("[5,6,7,8,9]"))
    @test seen == [5, 6, 7, 8, 9]
    total = 0
    foreach(v -> (total += v[]), JSON.lazy("[1,2,3,4,5,6,7,8,9,10]"))
    @test total == 55
    ks = String[]
    foreach(((k, v),) -> (push!(ks, k); 12), JSON.lazy("{\"a\":1,\"b\":2,\"c\":3}"))
    @test ks == ["a", "b", "c"]
    # selector predicates get `String` keys
    x = JSON.lazy("{\"alpha\": 1, \"beta\": {\"apple\": 2}}")
    @test [v[] for v in x[~, (k, v) -> startswith(k, "a")]] == [1, 2]
    @test [v[] for v in x[:, (k, v) -> occursin("lph", k)]] == [1]
    keytypes = Set{Type}()
    x[~, (k, v) -> (push!(keytypes, typeof(k)); false)]
    @test keytypes == Set{Type}([String])
    # a key holding an escaped NUL doesn't break property access to other keys
    y = JSON.lazy("{\"a\\u0000b\": 1, \"x\": 2, \"c\\u00e9\": 3}")
    @test y.x[] == 2
    @test getproperty(y, Symbol("cé"))[] == 3
    @test_throws KeyError y.ab
end

# a string type with UTF-16 code units that has a `pointer`, like LegacyStrings.UTF16String
struct PointerUTF16 <: AbstractString
    units::Vector{UInt16}
end
PointerUTF16(s::String) = PointerUTF16(transcode(UInt16, s))
Base.ncodeunits(s::PointerUTF16) = length(s.units)
Base.codeunit(::PointerUTF16) = UInt16
Base.codeunit(s::PointerUTF16, i::Integer) = s.units[i]
Base.pointer(s::PointerUTF16, i::Integer=1) = pointer(s.units, i)
Base.isvalid(s::PointerUTF16, i::Int) = checkbounds(Bool, s.units, i) && !(0xdc00 <= s.units[i] <= 0xdfff)
function Base.iterate(s::PointerUTF16, i::Int=1)
    i > length(s.units) && return nothing
    c = s.units[i]
    0xd800 <= c <= 0xdbff && return Char(0x10000 + ((UInt32(c) - 0xd800) << 10) + (s.units[i + 1] - 0xdc00)), i + 2
    return Char(c), i + 1
end

@testset "strings with wider code units" begin
    s = PointerUTF16("{\"a\":[1,\"é€😀\"]}")
    @test JSON.parse(s) == Dict("a" => [1, "é€😀"])
    @test JSON.isvalidjson(s)
    @test JSON.lazy(s) isa JSON.LazyValue{String}
end
