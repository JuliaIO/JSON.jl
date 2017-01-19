if isdefined(Base, :Dates)
    @test JSON.json(Date(2016, 8, 3)) == "\"2016-08-03\""
end

@test JSON.json(:x) == "\"x\""
@test_throws ArgumentError JSON.json(Base)

immutable Type151{T}
    x::T
end

@test JSON.parse(JSON.json(Type151)) == string(Type151)

JSON.lower{T}(v::Type151{T}) = Dict(:type => T, :value => v.x)
@test JSON.parse(JSON.json(Type151(1.0))) == Dict(
    "type" => "Float64",
    "value" => 1.0)

fixednum = Fixed{Int16, 15}(0.1234)
@test JSON.parse(JSON.json(fixednum)) == Float64(fixednum)
