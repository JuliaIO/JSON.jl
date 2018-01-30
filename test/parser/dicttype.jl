@testset for T in [
    DataStructures.OrderedDict,
    Dict{Symbol, Int32}
]
    val = JSON.parse(Typ("{\"x\": 3}"), dicttype=T)
    @test isa(val, T)
    @test length(val) == 1
    key = collect(keys(val))[1]
    @test string(key) == "x"
    @test val[key] == 3
end
