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
        
        # Test that mixed types require explicit Any type specification
        mixed = [:a => 1, :b => "hello", :c => 3.14]
        @test_throws MethodError JSON.Object(mixed)
        
        # But works with explicit Any type
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