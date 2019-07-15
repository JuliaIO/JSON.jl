@testset "Custom null values" begin
    s = "{\"x\": null}"
    for null in (nothing, missing)
        val = JSON.parse(s, null=null)
        @test val["x"] === null
    end
end
