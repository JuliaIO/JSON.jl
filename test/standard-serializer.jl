@testset "Symbol" begin
    symtest = Dict(:symbolarray => [:apple, :pear], :symbolsingleton => :hello)
    @test (JSON.json(symtest) == "{\"symbolarray\":[\"apple\",\"pear\"],\"symbolsingleton\":\"hello\"}"
             || JSON.json(symtest) == "{\"symbolsingleton\":\"hello\",\"symbolarray\":[\"apple\",\"pear\"]}")
end

@testset "Floats" begin
    @test sprint(JSON.print, [NaN]) == "[null]"
    @test sprint(JSON.print, [Inf]) == "[null]"
end

@testset "Nullable" begin
    @test sprint(JSON.print, [Nullable()]) == "[null]"
    @test sprint(JSON.print, [Nullable{Int64}()]) == "[null]"
    @test sprint(JSON.print, [Nullable{Int64}(Int64(1))]) == "[1]"
end

@testset "Char" begin
    @test json('a') == "\"a\""
    @test json('\\') == "\"\\\\\""
    @test json('\n') == "\"\\n\""
    @test json('🍩') =="\"🍩\""
end

@testset "Enum" begin
    include("enum.jl")
end

@testset "Type" begin
    @test sprint(JSON.print, Float64) == string("\"Float64\"")
end

@testset "Module" begin
    @test_throws ArgumentError sprint(JSON.print, JSON)
end

@testset "Dates" begin
    @test json(Date("2016-04-13")) == "\"2016-04-13\""
    @test json([Date("2016-04-13"), Date("2016-04-12")]) == "[\"2016-04-13\",\"2016-04-12\"]"
    @test json(DateTime("2016-04-13T00:00:00")) == "\"2016-04-13T00:00:00\""
    @test json([DateTime("2016-04-13T00:00:00"), DateTime("2016-04-12T00:00:00")]) == "[\"2016-04-13T00:00:00\",\"2016-04-12T00:00:00\"]"
end

@testset "Null bytes" begin
    zeros = Dict("\0" => "\0")
    json_zeros = json(zeros)
    @test contains(json_zeros,"\\u0000")
    @test !contains(json_zeros,"\\0")
    @test JSON.parse(json_zeros) == zeros
end

@testset "Arrays" begin
    # Printing an empty array or Dict shouldn't cause a BoundsError
    @test json(String[]) == "[]"
    @test json(Dict()) == "{}"

    #Multidimensional arrays
    @test json([0 1; 2 0]) == "[[0,2],[1,0]]"
end

@testset "Sets" begin
    @test json(Set()) == "[]"
    @test json(Set([1, 2])) in ["[1,2]", "[2,1]"]
end
