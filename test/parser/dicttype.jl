MissingDict() = DataStructures.DefaultDict{String,Any}(Missing)

@testset for T in [
    DataStructures.OrderedDict,
    Dict{Symbol, Int32},
    MissingDict
]
    val = JSON.parse("{\"x\": 3}", dicttype=T)
    @test isa(val, T)
    @test length(val) == 1
    key = collect(keys(val))[1]
    @test string(key) == "x"
    @test val[key] == 3

    if T == MissingDict
        @test val["y"] === missing
    else
        @test_throws KeyError val["y"]
    end
end

