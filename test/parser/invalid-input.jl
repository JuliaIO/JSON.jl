const FAILURES = [
    # Unexpected character in array
    "[1,2,3/4,5,6,7]",
    # Unexpected character in object
    "{\"1\":2, \"2\":3 _ \"4\":5}",
    # Invalid escaped character
    "[\"alpha\\α\"]",
    "[\"\\u05AG\"]",
    # Invalid 'simple' and 'unknown value'
    "[tXXe]",
    "[fail]",
    "∞",
    # Invalid number
    "[5,2,-]",
    "[5,2,+β]",
    # Incomplete escape
    "\"\\",
    # Control character
    "\"\0\"",
    # Issue #99
    "[\"🍕\"_\"🍕\"",
    "-0-5"
]

@testset for fail in FAILURES
    @test_throws ErrorException JSON.parse(Typ(fail))
end
