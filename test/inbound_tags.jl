using JSON, Test

JSON.StructUtils.@defaults struct JSONIgnoredField
    id::Int = 1
    secret::Int = 99 &(json=(ignore=true,),)
end

JSON.StructUtils.@noarg mutable struct JSONMutableIgnoredField
    id::Int = 1
    secret::Int = 99 &(json=(ignore=true,),)
end

@testset "JSON inbound field tags" begin
    @test JSON.parse(
        "{\"id\":2,\"secret\":200}",
        JSONIgnoredField;
        unknown_fields=:error,
    ) == JSONIgnoredField(2, 99)
    @test_throws ArgumentError JSON.parse(
        "{\"id\":2,\"extra\":200}",
        JSONIgnoredField;
        unknown_fields=:error,
    )

    value = JSONMutableIgnoredField()
    value.secret = 55
    JSON.parse!(
        "{\"id\":2,\"secret\":200}",
        value;
        unknown_fields=:error,
    )
    @test value.id == 2
    @test value.secret == 55
end
