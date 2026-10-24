using JSON, Test

@testset "JSON.Object Tests" begin
    # Test empty JSON.Object
    @testset "Empty Object" begin
        obj = JSON.Object{String, Int}()
        @test isempty(obj)
        @test length(obj) == 0
        @test collect(obj) == []
        @test propertynames(obj) == ()
        @test get(obj, "key", nothing) === nothing
        @test get(() -> 42, obj, "key") == 42
        @test_throws KeyError obj["key"]
        @test isempty(empty(obj))
        @test_throws KeyError obj.key
        @test !haskey(obj, "key")
        @test length(obj) == length(delete!(obj, "key"))
        @test isempty(JSON.Object())
    end

    # Test JSON.Object with one entry
    @testset "Single Entry Object" begin
        obj = JSON.Object{String, Int}()
        # internal way to add a key-value pair
        JSON.Object{String, Int}(obj, "key", 42)
        @test !isempty(obj)
        @test length(obj) == 1
        @test collect(obj) == ["key" => 42]
        @test propertynames(obj) == (:key,)
        @test get(obj, "key", nothing) == 42
        @test obj["key"] == 42
        @test get(() -> 0, obj, "key") == 42
        @test_throws KeyError obj["nonexistent_key"]
        # Object with String or Symbol key supports getproperty
        @test obj.key == 42
        @test haskey(obj, "key")
        @test !haskey(obj, "nonexistent_key")
        # test setindex! and delete!
        obj["key"] = 100
        @test obj["key"] == 100
        delete!(obj, "key")
        @test isempty(obj)
        obj.key = 200
        @test obj.key == 200
    end

    # Test JSON.Object with multiple entries
    @testset "Multiple Entry Object" begin
        obj = JSON.Object{String, Int}()
        ch = JSON.Object{String, Int}(obj, "key1", 1)
        ch = JSON.Object{String, Int}(ch, "key2", 2)
        ch = JSON.Object{String, Int}(ch, "key3", 3)
        @test !isempty(obj)
        @test length(obj) == 3
        @test propertynames(obj) == (:key1, :key2, :key3)
        @test collect(obj) == ["key1" => 1, "key2" => 2, "key3" => 3]
        @test get(obj, "key2", nothing) == 2
        @test obj["key3"] == 3
        obj["key3"] = 100
        @test obj["key3"] == 100
        delete!(obj, "key2")
        @test length(obj) == 2
        @test collect(obj) == ["key1" => 1, "key3" => 100]
    end

    # Test iteration over keys, values, and pairs
    @testset "Iteration" begin
        obj = JSON.Object{String, Int}()
        obj["a"] = 1
        obj["b"] = 2
        obj["c"] = 3

        @test collect(keys(obj)) == ["a", "b", "c"]
        @test collect(values(obj)) == [1, 2, 3]
        @test collect(pairs(obj)) == ["a" => 1, "b" => 2, "c" => 3]
    end

    # Test membership
    @testset "Membership" begin
        obj = JSON.Object{String, Int}()
        obj["x"] = 10
        @test haskey(obj, "x")
        @test !haskey(obj, "y")
        @test "x" in keys(obj)
        @test 10 in values(obj)
    end

    # Test modification
    @testset "Modification" begin
        obj = JSON.Object{String, Int}()
        obj["key1"] = 100
        obj["key2"] = 200
        merge!(obj, Dict("key3" => 300, "key4" => 400))
        @test length(obj) == 4
        @test obj["key3"] == 300
        empty!(obj)
        @test isempty(obj)
    end

    # Test copying
    @testset "Copying" begin
        obj = JSON.Object{String, Int}()
        obj["a"] = 1
        obj["b"] = 2
        obj_copy = copy(obj)
        @test obj == obj_copy
        obj["a"] = 10
        @test obj != obj_copy
    end

    # Test equality
    @testset "Equality" begin
        obj1 = JSON.Object{String, Int}()
        obj2 = JSON.Object{String, Int}()
        obj1["key"] = 42
        obj2["key"] = 42
        @test obj1 == obj2
        obj2["key"] = 100
        @test obj1 != obj2
    end

    # Test edge cases
    @testset "Edge Cases" begin
        obj = JSON.Object{Union{String, Nothing}, Int}()
        obj["key"] = 1
        obj[nothing] = 2
        @test obj["key"] == 1
        @test obj[nothing] == 2
        obj["key"] = 100
        @test obj["key"] == 100
    end

    # Test serialization
    @testset "Serialization" begin
        obj = JSON.Object{String, Int}()
        obj["a"] = 1
        obj["b"] = 2
        dict = Dict(obj)
        @test dict == Dict("a" => 1, "b" => 2)
        obj2 = JSON.Object{String, Int}(dict)
        @test obj == obj2
    end

    # constructors
    @testset "Constructors" begin
        obj = JSON.Object(Dict("a" => 1, "b" => 2))
        @test obj["a"] == 1
        @test obj["b"] == 2
        obj2 = JSON.Object("a" => 1, "b" => 2)
        @test obj2["a"] == 1
        @test obj2["b"] == 2
        obj3 = JSON.Object(:a => 1, :b => 2)
        @test obj3[:a] == 1
        @test obj3[:b] == 2
        obj = JSON.Object{Symbol, Int}()
        obj[:a] = 1
        @test obj.a == 1
        obj.a = 2
        @test obj[:a] == 2
    end

    # Test performance (basic check for large dictionaries)
    @testset "Performance" begin
        obj = JSON.Object{Int, Int}()
        for i in 1:10_000
            obj[i] = i
        end
        @test length(obj) == 10_000
        @test obj[5_000] == 5_000
    end

    # Test new iterator constructors
    @testset "Iterator Constructors" begin
        # Test generic Object(itr) constructor with Pairs
        pairs = ["a" => 1, "b" => 2, "c" => 3]
        obj1 = JSON.Object(pairs)
        @test obj1["a"] == 1
        @test obj1["b"] == 2
        @test obj1["c"] == 3
        @test length(obj1) == 3

        # Test generic Object(itr) constructor with Tuples
        tuples = [("x", 10), ("y", 20), ("z", 30)]
        obj2 = JSON.Object(tuples)
        @test obj2["x"] == 10
        @test obj2["y"] == 20
        @test obj2["z"] == 30
        @test length(obj2) == 3

        # Test generic Object(itr) constructor with consistent types
        symbols = [:a => 1, :b => 2, :c => 3]
        obj3 = JSON.Object(symbols)
        @test obj3[:a] == 1
        @test obj3[:b] == 2
        @test obj3[:c] == 3
        @test length(obj3) == 3
        
        # mixed value types widen the value type, as for `Dict(itr)`
        mixed = [:a => 1, :b => "hello", :c => 3.14]
        @test JSON.Object(mixed) isa JSON.Object{Symbol,Any}
        @test collect(JSON.Object(mixed)) == mixed

        # or give it explicitly
        obj3_any = JSON.Object{Symbol,Any}(mixed)
        @test obj3_any[:a] == 1
        @test obj3_any[:b] == "hello"
        @test obj3_any[:c] == 3.14
        @test length(obj3_any) == 3

        # Test empty iterator
        empty_iter = Pair{String, Int}[]
        obj4 = JSON.Object(empty_iter)
        @test isempty(obj4)
        @test length(obj4) == 0

        # Test typed Object{K,V}(itr) constructor
        typed_pairs = ["key1" => 100, "key2" => 200]
        obj5 = JSON.Object{String, Int}(typed_pairs)
        @test obj5["key1"] == 100
        @test obj5["key2"] == 200
        @test length(obj5) == 2

        # Test typed constructor with tuples
        typed_tuples = [("a", 1), ("b", 2)]
        obj6 = JSON.Object{String, Int}(typed_tuples)
        @test obj6["a"] == 1
        @test obj6["b"] == 2
        @test length(obj6) == 2

        # Test error handling for invalid iterator elements
        invalid_iter = [1, 2, 3]  # Not pairs or tuples
        @test_throws ArgumentError JSON.Object(invalid_iter)
        @test_throws ArgumentError JSON.Object{String, Int}(invalid_iter)

        # Test with generator expression
        gen_pairs = (string(i) => i^2 for i in 1:5)
        obj7 = JSON.Object(gen_pairs)
        @test obj7["1"] == 1
        @test obj7["3"] == 9
        @test obj7["5"] == 25
        @test length(obj7) == 5

        # Test with Dict as iterator
        dict_input = Dict("foo" => 42, "bar" => 24)
        obj8 = JSON.Object(dict_input)
        @test obj8["foo"] == 42
        @test obj8["bar"] == 24
        @test length(obj8) == 2
    end

    # Test enhanced haskey for String objects with Symbol keys
    @testset "Enhanced haskey for String Objects" begin
        obj = JSON.Object{String, Any}()
        obj["hello"] = "world"
        obj["count"] = 42

        # Test basic string key lookup
        @test haskey(obj, "hello")
        @test haskey(obj, "count")
        @test !haskey(obj, "missing")

        # Test Symbol key lookup (should convert to String)
        @test haskey(obj, :hello)
        @test haskey(obj, :count)
        @test !haskey(obj, :missing)

        # Test that Symbol keys work for both existing and non-existing keys
        obj["symbol_test"] = "value"
        @test haskey(obj, :symbol_test)
        @test !haskey(obj, :nonexistent_symbol)

        # Test that indexing with both String and Symbol keys work
        @test obj[:symbol_test] == obj["symbol_test"]
        
        # Test overwriting with Symbol key 
        obj[:symbol_test] = "newvalue"
        @test obj[:symbol_test] == obj["symbol_test"] == "newvalue"

        # Test deletion with Symbol key
        delete!(obj, :symbol_test)
        @test !haskey(obj, :symbol_test)
        @test !haskey(obj, "symbol_test")

        # Test get with Symbol key (should convert to String)
        obj["get_test"] = "got it"
        @test get(obj, :get_test, "default") == "got it"
        @test get(obj, :nonexistent, "default") == "default"
        @test get(() -> "fallback", obj, :get_test) == "got it"
        @test get(() -> "fallback", obj, :nonexistent) == "fallback"

        # Test with empty object
        empty_obj = JSON.Object{String, Any}()
        @test !haskey(empty_obj, :anything)
        @test !haskey(empty_obj, "anything")
    end

    @testset "AbstractString key support for parsed String objects" begin
        obj = JSON.parse("{\"foo\": \"bar\"}")
        s = "abc.foo.xyz"
        k = split(s, ".")[2]

        @test k isa SubString{String}
        @test haskey(obj, k)
        @test get(obj, k, nothing) == "bar"
        @test obj[k] == "bar"

        obj[k] = "baz"
        @test obj["foo"] == "baz"

        delete!(obj, k)
        @test !haskey(obj, "foo")
        @test get(obj, k, "default") == "default"
        @test_throws KeyError obj[k]
    end

    # Test enhanced haskey for Symbol objects with String keys
    @testset "Enhanced haskey for Symbol Objects" begin
        obj = JSON.Object{Symbol, Any}()
        obj[:hello] = "world"
        obj[:count] = 42

        # Test basic string key lookup
        @test haskey(obj, :hello)
        @test haskey(obj, :count)
        @test !haskey(obj, :missing)
        
        # Test String key lookup (should convert to Symbol)
        @test haskey(obj, "hello")
        @test haskey(obj, "count")
        @test !haskey(obj, "missing")

        # Test that String keys work for both existing and non-existing keys
        obj[:symbol_test] = "value"
        @test haskey(obj, "symbol_test")
        @test !haskey(obj, "nonexistent_symbol")

        # Test that indexing with both String and Symbol keys work
        @test obj[:symbol_test] == obj["symbol_test"]

        # Test overwriting with String key 
        obj["symbol_test"] = "newvalue"
        @test obj[:symbol_test] == obj["symbol_test"] == "newvalue"

        # Test deletion with String key
        delete!(obj, "symbol_test")
        @test !haskey(obj, :symbol_test)
        @test !haskey(obj, "symbol_test")

        # Test get with String key (should convert to Symbol)
        obj[:get_test] = "got it"
        @test get(obj, "get_test", "default") == "got it"
        @test get(obj, "nonexistent", "default") == "default"
        @test get(() -> "fallback", obj, "get_test") == "got it"
        @test get(() -> "fallback", obj, "nonexistent") == "fallback"

        # Test with empty object
        empty_obj = JSON.Object{Symbol, Any}()
        @test !haskey(empty_obj, :anything)
        @test !haskey(empty_obj, "anything")
    end

    # Test merge functionality with NamedTuple
    @testset "NamedTuple Merge" begin
        # Test basic merge
        nt = (a = 1, b = 2, c = 3)
        obj = JSON.Object{String, Any}()
        obj["x"] = 10
        obj["y"] = 20

        merged = merge(nt, obj)
        @test merged.a == 1
        @test merged.b == 2
        @test merged.c == 3
        @test merged.x == 10
        @test merged.y == 20

        # Test merge with overlapping keys (Object values should override NamedTuple)
        nt2 = (a = 100, d = 400)
        obj2 = JSON.Object{String, Any}()
        obj2["a"] = 999  # This should override the NamedTuple value
        obj2["b"] = 200

        merged2 = merge(nt2, obj2)
        @test merged2.a == 999  # Object value overrides NamedTuple
        @test merged2.d == 400  # NamedTuple value preserved
        @test merged2.b == 200  # Object value added

        # Test merge with empty NamedTuple
        empty_nt = NamedTuple()
        obj3 = JSON.Object{String, Any}()
        obj3["key"] = "value"

        merged3 = merge(empty_nt, obj3)
        @test merged3.key == "value"
        @test length(merged3) == 1

        # Test merge with empty Object
        nt4 = (x = 1, y = 2)
        empty_obj = JSON.Object{String, Any}()

        merged4 = merge(nt4, empty_obj)
        @test merged4.x == 1
        @test merged4.y == 2
        @test length(merged4) == 2

        # Test that the result is a NamedTuple
        result = merge((a = 1,), JSON.Object{String, Any}("b" => 2))
        @test result isa NamedTuple
        @test haskey(result, :a)
        @test haskey(result, :b)

        # Test with various value types
        obj_mixed = JSON.Object{String, Any}()
        obj_mixed["string"] = "hello"
        obj_mixed["number"] = 42
        obj_mixed["float"] = 3.14
        obj_mixed["bool"] = true

        nt_mixed = (existing = "original",)
        merged_mixed = merge(nt_mixed, obj_mixed)
        @test merged_mixed.existing == "original"
        @test merged_mixed.string == "hello"
        @test merged_mixed.number == 42
        @test merged_mixed.float == 3.14
        @test merged_mixed.bool == true
    end
end

@testset "Popping JSON.Object entries" begin
    for ks in (("a", "b", "c"), (:a, :b, :c), (1, 2, 3), (1, :b, "c")), index in 1:3, with_default in (false, true)
        entries = [ks[i] => 10i for i in 1:3]
        obj = JSON.Object(entries...)
        value = with_default ? pop!(obj, ks[index], nothing) : pop!(obj, ks[index])
        @test value === 10index
        @test collect(obj) == entries[setdiff(1:3, index)]
        @test !haskey(obj, ks[index])
    end

    obj = JSON.Object("a" => 1, "b" => 2)
    fallback = Ref(:absent)
    @test pop!(obj, "absent", fallback) === fallback
    @test pop!(obj, 1, fallback) === fallback
    @test_throws KeyError pop!(obj, "absent")
    @test collect(obj) == ["a" => 1, "b" => 2]
    @test pop!(obj, :a) == 1
    @test pop!(obj, SubString("_b", 2), nothing) == 2
    @test isempty(obj)
    @test pop!(obj, "absent", fallback) === fallback
    @test_throws KeyError pop!(obj, "absent")

    obj = JSON.Object(:a => 1, :b => 2)
    @test pop!(obj, "a") == 1
    @test pop!(obj, "b", nothing) == 2
    @test isempty(obj)

    for value in (nothing, missing, JSON.notset, Ref(1))
        obj = JSON.Object{String,Any}("a" => value)
        @test pop!(obj, "a", value) === value
        @test isempty(obj)
    end

    obj = JSON.Object(1 => :value)
    @test pop!(obj, 1.0) === :value
    @test isempty(obj)
    obj = JSON.Object(NaN => 1, -0.0 => 2, 0.0 => 3)
    @test pop!(obj, NaN) == 1
    @test pop!(obj, 0.0) == 3
    @test pop!(obj, -0.0) == 2
    @test isempty(obj)

    obj = JSON.Object("a" => 1, "a" => 2, "b" => 3)
    @test pop!(obj, "a") == 1
    @test collect(obj) == ["a" => 2, "b" => 3]
    @test pop!(obj, "a") == 2
    @test collect(obj) == ["b" => 3]

    obj = JSON.parse("{\"a\":1,\"b\":null,\"c\":3}")
    @test pop!(obj) == ("c" => 3)
    @test popfirst!(obj) == ("a" => 1)
    @test JSON.json(obj) == "{\"b\":null}"
    @test pop!(obj) == ("b" => nothing)
    @test isempty(obj)
    @test isempty(propertynames(obj))
    @test_throws ArgumentError pop!(obj)
    @test_throws ArgumentError popfirst!(obj)
    obj["d"] = 4
    @test popfirst!(obj) == ("d" => 4)
    @test isempty(obj)
end


@testset "JSON.Object mutation contracts" begin
    for (K, ks) in ((String, ("a", "b")), (Symbol, (:a, :b)), (Int, (1, 2)), (Any, (1, "b")))
        obj = JSON.Object{K,Int}()
        @test setindex!(obj, 1.0, ks[1]) === obj
        @test setindex!(obj, 2.0, ks[2]) === obj
        @test setindex!(obj, 3.0, ks[1]) === obj
        @test collect(obj) == [ks[1] => 3, ks[2] => 2]
    end

    obj = JSON.Object{String,Int}()
    @test setindex!(obj, 1, :a) === obj
    @test setindex!(obj, 2, SubString("_b", 2)) === obj
    @test setindex!(obj, 3, :a) === obj
    @test collect(obj) == ["a" => 3, "b" => 2]
    obj = JSON.Object{Symbol,Int}()
    @test setindex!(obj, 1, "a") === obj
    @test setindex!(obj, 2, "a") === obj
    @test collect(obj) == [:a => 2]

    for make in (() -> JSON.Object{Int,Int}(1.0 => 2.0), () -> JSON.Object{Int,Int}([1.0 => 2.0]), () -> JSON.Object{Int,Int}([(1.0, 2.0)]), () -> JSON.Object{Int,Int}(Dict(1.0 => 2.0)))
        @test collect(make()) == [1 => 2]
    end
    @test collect(JSON.Object{String,Int}(SubString("_a", 2) => 1.0)) == ["a" => 1]
    obj = JSON.Object{String,Int}()
    @test_throws InexactError setindex!(obj, 1.5, "a")
    @test isempty(obj)
    @test setindex!(obj, 1.0, "a") === obj
    @test_throws InexactError setindex!(obj, 2.5, "a")
    @test obj["a"] == 1

    layouts = ((), (1,), (1, 1), (1, 1, 2), (2, 1, 1), (1, 2, 1), (2, 1, 1, 3, 1), (1, 1, 1), (2, 3))
    for ks in (("a", "b", "c"), (:a, :b, :c), (1, 2, 3)), layout in layouts
        entries = [ks[i] => n for (n, i) in enumerate(layout)]
        obj = JSON.Object{eltype(ks),Int}(entries)
        expected = filter(p -> !isequal(first(p), ks[1]), entries)
        @test delete!(obj, ks[1]) === obj
        @test collect(obj) == expected
        @test !haskey(obj, ks[1])
        @test length(obj) == length(expected)
    end

    obj = JSON.Object("a" => 1, "a" => 2, "b" => 3)
    @test delete!(obj, :a) === obj
    @test JSON.json(obj) == "{\"b\":3}"
    @test delete!(obj, SubString("_b", 2)) === obj
    @test isempty(obj)
    @test setindex!(obj, 4, :c) === obj
    @test JSON.json(obj) == "{\"c\":4}"
    obj = JSON.Object(:a => 1, :a => 2, :b => 3)
    @test delete!(obj, "a") === obj
    @test collect(obj) == [:b => 3]

    obj = JSON.Object(NaN => 1, NaN => 2, -0.0 => 3, 0.0 => 4)
    @test delete!(obj, NaN) === obj
    @test !haskey(obj, NaN)
    @test collect(obj) == [-0.0 => 3, 0.0 => 4]
    @test delete!(obj, 0.0) === obj
    @test collect(obj) == [-0.0 => 3]
end

@testset "JSON.Object property names" begin
    for K in (String, Symbol), V in (Int, Any)
        key = K === String ? identity : Symbol
        obj = JSON.Object{K,V}(key("first") => 1, key("first") => 2, key("second") => 3)
        @test propertynames(obj) == (:first, :first, :second)
        @test propertynames(obj, true) == (:first, :first, :second)
        @test obj.first == 1
        delete!(obj, key("first"))
        @test propertynames(obj) == (:second,)
        obj.third = 4
        @test propertynames(obj) == (:second, :third)
        @test popfirst!(obj) == (key("second") => 3)
        @test propertynames(obj) == (:third,)
        empty!(obj)
        @test propertynames(obj) === ()
    end
    obj = JSON.Object("" => 1, "two words" => 2, "a/b" => 3, "λ" => 4, "key" => 5, "value" => 6, "child" => 7)
    @test propertynames(obj) == (Symbol(""), Symbol("two words"), Symbol("a/b"), :λ, :key, :value, :child)
    @test obj.key == 5
    @test obj.value == 6
    @test obj.child == 7
    @test propertynames(JSON.Object()) === ()

    obj = JSON.Object{String,Int}(string(i) => i for i in 1:100)
    expected = Tuple(Symbol(string(i)) for i in 1:100)
    @test propertynames(obj) == expected
    @test @allocated(propertynames(obj)) <= 20_000

    @testset "large object" begin
        large = JSON.Object{String,Int}(string(i) => i for i in 1:10_000)
        names = propertynames(large)
        @test names == Tuple(Symbol(string(i)) for i in 1:10_000)
        @test first(names) == Symbol("1")
        @test last(names) == Symbol("10000")
        @test length(names) == length(large)
    end
end

# Reference for the `Object` writer: an `AbstractDict` that is neither an `Object` nor a `Dict`,
# so it takes the generic `applyeach(::JSONStyle, f, ::AbstractDict{<:Any,Any})` path and is not
# key-sorted. Nested objects are wrapped too, so the whole document goes through that path.
struct _GenericPathDict{K} <: AbstractDict{K,Any}
    obj::JSON.Object{K,Any}
end
_generic_path(x) = x
_generic_path(x::JSON.Object{K,Any}) where {K} = _GenericPathDict{K}(x)
_generic_path(x::Vector{Any}) = Any[_generic_path(v) for v in x]
Base.length(d::_GenericPathDict) = length(d.obj)
function Base.iterate(d::_GenericPathDict{K}, st...) where {K}
    r = iterate(d.obj, st...)
    r === nothing && return nothing
    p, s = r
    return Pair{K,Any}(p.first, _generic_path(p.second)), s
end

@testset "Writing JSON.Object without iterating it" begin
    # the comparison only means something if the two values take different methods
    objsig = which(JSON.StructUtils.applyeach, Tuple{JSON.JSONWriteStyle, Function, JSON.Object{String,Any}}).sig
    gensig = which(JSON.StructUtils.applyeach, Tuple{JSON.JSONWriteStyle, Function, _GenericPathDict{String}}).sig
    @test objsig <: Tuple{Any, Any, Any, JSON.Object}
    @test !(gensig <: Tuple{Any, Any, Any, JSON.Object})

    @testset "byte-identical to the generic path on a nested document" begin
        src = """{"z":1,"a":{"c":[1,{"d":null,"e":"x\\"y\\u00e9"},[],{}],"b":2.5,"empty":{}},
                  "list":[true,false,-0.0,1e300,"s"],"k":"","nested":{"x":{"y":{"z":[{"w":1}]}}}}"""
        obj = JSON.parse(src)
        @test obj isa JSON.Object{String,Any}
        ref = _generic_path(obj)
        @test JSON.json(obj) == JSON.json(ref)
        @test JSON.json(obj; pretty=2) == JSON.json(ref; pretty=2)
        @test JSON.json(obj; omit_null=true) == JSON.json(ref; omit_null=true)
        # insertion order is kept, not sorted
        @test startswith(JSON.json(obj), "{\"z\":1,\"a\":")
        # an Object holding nothing but the root node
        @test JSON.json(JSON.Object{String,Any}()) == "{}"
        # a document whose root is an array of objects
        arr = JSON.parse("""[{"b":1,"a":2},{"c":{"d":[]}}]""")
        @test JSON.json(arr) == JSON.json(_generic_path(arr))
    end

    @testset "keys other than String go through lowerkey" begin
        sym = JSON.Object{Symbol,Any}(:b => 1, :a => JSON.Object{Symbol,Any}(:c => Any[1, "x"]))
        @test JSON.json(sym) == JSON.json(_generic_path(sym)) == """{"b":1,"a":{"c":[1,"x"]}}"""
        int = JSON.Object{Int,Any}(2 => "two", 1 => 1.5, 10 => nothing)
        @test JSON.json(int) == JSON.json(_generic_path(int)) == """{"2":"two","1":1.5,"10":null}"""
    end

    @testset "EarlyReturn stops the walk" begin
        obj = JSON.parse("""{"a":1,"b":2,"c":3}""")
        seen = String[]
        f = (k, v) -> (push!(seen, k); k == "b" ? JSON.StructUtils.EarlyReturn(v) : nothing)
        ret = JSON.StructUtils.applyeach(JSON.JSONWriteStyle(), f, obj)
        @test ret isa JSON.StructUtils.EarlyReturn
        @test ret.value == 2
        @test seen == ["a", "b"]
    end
end

# a key that counts its `isequal` calls, to check that whole-object operations do not
# compare every key with every other key
struct CountedKey
    k::Int
end
const KEY_COMPARISONS = Ref(0)
Base.isequal(a::CountedKey, b::CountedKey) = (KEY_COMPARISONS[] += 1; a.k == b.k)
Base.hash(a::CountedKey, h::UInt) = hash(a.k, h)
JSON.StructUtils.liftkey(::JSON.JSONReadStyle, ::Type{CountedKey}, x::String) = CountedKey(parse(Int, x))
function comparisons(f)
    KEY_COMPARISONS[] = 0
    f()
    return KEY_COMPARISONS[]
end

@testset "JSON.Object whole-object operations" begin
    # the results Base's generic `AbstractDict` methods give, which insert with `setindex!`
    setindex_all!(obj, kvs) = (for (k, v) in kvs; obj[k] = v; end; obj)
    same(a, b) = typeof(a) == typeof(b) && isequal(collect(a), collect(b))
    generic_eq(l, r) = invoke(==, Tuple{AbstractDict,AbstractDict}, l, r)
    generic_isequal(l, r) = invoke(isequal, Tuple{AbstractDict,AbstractDict}, l, r)

    # few distinct keys, so objects repeat keys; sizes cross the 5-key set and 16-key table thresholds
    pool = [string(c) for c in 'a':'x']
    vals = Any[1, 2, missing, NaN]
    for seed in 1:300
        n = mod(seed, 41)
        kvs = Pair{String,Any}[pool[mod(seed * 7 + 3i, 24) + 1] => vals[mod(seed + i * i, 4) + 1] for i in 1:n]
        o = JSON.Object{String,Any}(kvs)
        @test same(copy(o), setindex_all!(JSON.Object{String,Any}(), o))
        @test same(copy!(JSON.Object{String,Any}("zz" => 0), o), setindex_all!(JSON.Object{String,Any}(), o))
        @test same(merge!(copy(o), o, Dict("b" => 7, "zz" => 8)), setindex_all!(setindex_all!(copy(o), o), Dict("b" => 7, "zz" => 8)))
        other = JSON.Object{String,Any}(reverse(kvs[1:2:end]))
        generic_mergewith!(t) = invoke(mergewith!, Tuple{Any,AbstractDict,AbstractDict}, tuple, t, other)
        @test same(mergewith!(tuple, JSON.Object{String,Any}(kvs), other), generic_mergewith!(JSON.Object{String,Any}(kvs)))
        keep = p -> isodd(length(p.first) + hash(p.first) % 3)
        @test same(filter(keep, o), setindex_all!(JSON.Object{String,Any}(), Iterators.filter(keep, o)))
        for r in (o, copy(o), JSON.Object{String,Any}(reverse(kvs)), JSON.Object{String,Any}(kvs[1:end-1]), JSON.Object{String,Any}(push!(kvs[2:end], "a" => 1)))
            @test isequal(o == r, generic_eq(o, r))
            @test isequal(r == o, generic_eq(r, o))
            @test isequal(o, r) === generic_isequal(o, r)
        end
        # parse! into an object that may already repeat keys updates as `setindex!` does
        new = Pair{String,Any}[pool[mod(seed * 5 + 2i, 24) + 1] => Any[1, 2.5, nothing][mod(seed + i, 3) + 1] for i in 1:mod(seed, 13)]
        json = "{" * join(("\"$k\":$(JSON.json(v))" for (k, v) in new), ",") * "}"
        target = JSON.Object{String,Any}(kvs)
        JSON.parse!(json, target)
        @test same(target, setindex_all!(JSON.Object{String,Any}(kvs), new))
    end
    sym = JSON.Object{String,Any}("a" => 1, "b" => 2)
    @test same(merge!(sym, Dict(:a => 5, :c => 6)), JSON.Object{String,Any}("a" => 5, "b" => 2, "c" => 6))
    @test_throws MethodError merge!(JSON.Object{String,Any}(), Dict(1 => 2))
    # other keys convert to the key type, as `merge!` into a `Dict` does
    @test same(merge!(JSON.Object{Float64,Int}(1.0 => 1), Dict(2 => 3)), JSON.Object{Float64,Int}(1.0 => 1, 2.0 => 3))
    @test same(mergewith!(+, JSON.Object{Float64,Int}(1.0 => 1), Dict(1 => 5)), JSON.Object{Float64,Int}(1.0 => 6))
    @test JSON.Object{Symbol,Any}(:a => 1) == JSON.Object{String,Any}("a" => 1)
    @test_throws MethodError JSON.parse!("[1]", JSON.Object{String,Any}()) # not an object: the generic path

    n = 2_000
    o = JSON.Object{CountedKey,Int}(CountedKey(i) => i for i in 1:n)
    @test comparisons(() -> @test(length(copy(o)) == n)) < 5n
    @test comparisons(() -> @test(length(filter(p -> iseven(p.second), o)) == n ÷ 2)) < 5n
    @test comparisons(() -> merge!(copy(o), o)) < 10n
    @test comparisons(() -> mergewith!(+, copy(o), o)) < 10n
    r = JSON.Object{CountedKey,Int}(CountedKey(i) => i for i in n:-1:1)
    @test comparisons(() -> @test(o == r && isequal(o, r))) < 10n
    json = JSON.json(JSON.Object{String,Int}(string(i) => i for i in 1:n))
    target = JSON.Object{CountedKey,Int}()
    @test comparisons(() -> JSON.parse!(json, target)) < 5n
    @test target == o
    @test comparisons(() -> JSON.parse!(json, target)) < 5n
    @test target == o
end

using Serialization

@testset "JSON.Object deepcopy and Serialization" begin
    @test Base.get_extension(JSON, :JSONSerializationExt) !== nothing
    roundtrip(x) = (io = IOBuffer(); serialize(io, x); seekstart(io); deserialize(io))
    shared = JSON.Object{String,Any}("s" => [1])
    objs = (
        JSON.Object{String,Any}("b" => 1, "a" => shared, "b" => 2, "c" => shared, "d" => JSON.Object{String,Any}()),
        JSON.Object{Symbol,Int}(:z => 1, :y => 2, :z => 3),
        JSON.Object(1 => "x", :k => nothing, "k" => 2.5),
        JSON.Object{String,Int}(),
    )
    for o in objs, f in (deepcopy, roundtrip)
        c = f(o)
        @test typeof(c) == typeof(o)
        @test isequal(collect(c), collect(o))
        @test c !== o
    end
    c = deepcopy(objs[1])
    @test c["a"] === c["c"] !== shared
    push!(c["a"]["s"], 2)
    @test shared["s"] == [1]
    c = roundtrip(objs[1])
    @test c["a"] === c["c"]
    cyclic = JSON.Object{String,Any}("x" => 1)
    cyclic["self"] = cyclic
    for f in (deepcopy, roundtrip)
        c = f(cyclic)
        @test c["self"] === c
        @test c["x"] == 1
    end

    # long enough to overflow the stack if each entry is copied by a recursive call
    n = 200_000
    big = JSON.parse("{" * join(("\"k$i\":$i" for i in 1:n), ",") * "}")
    for f in (deepcopy, roundtrip)
        c = f(big)
        @test length(c) == n
        @test first(c) == ("k1" => 1)
        @test c == big
    end
end

@testset "JSON.Object dot access and iterators for other key types" begin
    o = JSON.Object("a" => 1, "b" => "x")
    @test o isa JSON.Object{Any,Any}
    @test o.a == 1
    @test o.b == "x"
    @test_throws KeyError o.c
    @test_throws KeyError o.key # not the internal field
    p = JSON.Object()
    p.a = 1
    @test p.a == 1
    p["a"] = 2 # a String key is found only when the Symbol key is absent
    @test p.a == 1
    @test_throws KeyError JSON.Object(1 => 2).a
    @test JSON.Object{Symbol,Any}(:a => 1).a == 1
    @test JSON.Object{String,Any}("a" => 1).a == 1

    # key and value types widen as for `Dict(itr)`; order and repeated keys are kept
    for itr in (Any["a" => 1, "b" => "x"], ("a" => 1, "b" => "x"), ((k, v) for (k, v) in [("a", 1), ("b", "x")]),
                ("a" => 1, "b" => nothing, "a" => 2), Any[:a => 1, "b" => 2, :a => 3.5])
        obj = JSON.Object(itr)
        d = Dict(itr)
        @test obj isa JSON.Object{keytype(d),valtype(d)}
        @test collect(obj) == [k => v for (k, v) in itr]
    end
    @test JSON.Object(["a" => 1, "b" => 2]) isa JSON.Object{String,Int}
    @test JSON.Object(Pair{String,Any}["a" => 1, "b" => 2]) isa JSON.Object{String,Int} # types of the pairs, not the eltype
end
