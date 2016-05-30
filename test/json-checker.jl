# Run JSON checker tests

const JSON_DATA_DIR = joinpath(dirname(dirname(@__FILE__)), "data")
const ALLOWED_CHECK_FAILURES = [1, 2, 7, 8, 10, 18, 25, 27, 32]
const ALLOWED_RT_FAILURES = [13, 14, 17, 18, 19]

for i in 1:33
    file = "fail$(lpad(i, 2, 0)).json"
    filepath = joinpath(JSON_DATA_DIR, "jsonchecker", file)

    # FIXME: This is a convoluted way of allowing certain tests to fail. Once
    # ALLOWED_CHECK_FAILURES is empty, we can eliminate the extra code.

    if i in ALLOWED_CHECK_FAILURES
        try
            JSON.parsefile(filepath)

            print_with_color(:red, " [Fail (Allowed)] ")
            println("Test $file parsed successfully; should throw ErrorException.")
        catch ex
            if isa(ex, ErrorException)
                print_with_color(:green, " [Pass] ")
                println("Test $file now fails as expected.")
                println("It can be removed from ALLOWED_CHECK_FAILURES now.")
            else
                print_with_color(:red, " [Fail (Allowed)] ")
                println("Test $file throws unexpected error; should throw ErrorException:")
                println(ex)
            end
        end
    else
        @test_throws ErrorException JSON.parsefile(filepath)
    end
end

for i in 1:3
    tf = joinpath(JSON_DATA_DIR, "jsonchecker", "pass$(lpad(i, 2, 0)).json")
    @test (JSON.parsefile(tf); true)
end

# Run JSON roundtrip tests (check consistency of .json)

roundtrip(data) = JSON.json(JSON.Parser.parse(data))

for i in 1:27
    file = "roundtrip$(lpad(i, 2, 0)).json"
    filepath = joinpath(JSON_DATA_DIR, "roundtrip", file)

    try
        rt = roundtrip(readstring(filepath))
        @test rt == roundtrip(rt)
    catch ex
        # FIXME: this is temporary, until int overflow issues fixed
        @test i in ALLOWED_RT_FAILURES

        print_with_color(:red, " [Fail] ")
        println("Failed to successfully roundtrip $file; error thrown")
        println(ex)
    end
end
