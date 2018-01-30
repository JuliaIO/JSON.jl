const explist = ("0", "00030", "60", "123", "12341231234123412")

makeexplist() = [string(pre, ex) for pre in ("e", "e-", "e+", "E", "E-", "E+") for ex in explist]

for T in [Float16, Float32, Float64, BigFloat]
    @testset "$T" begin
        for pref in ("0", "-0", "1234234", "-1234234", "999999999999999999999"),
            frac in ("", ".123", ".000000000000000000000555", ".999"),
            expo in vcat("", makeexplist()),
            post in ("", "    ", "   \t", "\t", "\r", "\n", "    \r", "    \n")

            str = string(pref, frac, expo)
            isnull(tryparse(T, str)) && continue
            val = JSON.parse(InputType[]("{\"x\": $str$post}"), floattype=T)
            @test isa(val, Dict{String, Any})
            @test length(val) == 1
            key = collect(keys(val))[1]
            @test string(key) == "x"
            value = val[key]
            VT = typeof(value) <: Integer ? Int64 : T
            @test value == parse(VT, str)
            @test typeof(value) == VT
        end
    end
end

@testset begin
    teststr = """{"201736327611975630": 18005722827070440994}"""
    val = JSON.parse(InputType[](teststr), inttype=Int128)
    @test val == Dict{String,Any}("201736327611975630" => 18005722827070440994)
end
