using JSON
using Base.Test
using Compat
import DataStructures

include(joinpath(dirname(@__FILE__),"json_samples.jl"))

@test JSON.parse("{\"x\": 3}"; ordered = true) == DataStructures.OrderedDict{String,Any}([("x",3)])

# Test definitions -------
validate_c(c) = begin
                    j = JSON.parse(c);
                    @test j != nothing
                    @test typeof(j["widget"]["image"]["hOffset"]) == Int
                    @test j["widget"]["image"]["hOffset"] == 250
                    @test typeof(j["widget"]["text"]["size"]) == Float64
                    @test j["widget"]["text"]["size"] == 36.5
                end

validate_e(e) = begin
                    j=JSON.parse(e)
                    @test j != nothing
                    @test typeof(j) == Dict{AbstractString, Any}
                    @test length(j) == 1
                    @test typeof(j["menu"]) == Dict{AbstractString, Any}
                    @test length(j["menu"]) == 2
                    @test j["menu"]["header"] == "SVG\tViewerα"
                    @test isa(j["menu"]["items"], Array)
                    @test length(j["menu"]["items"]) == 22
                    @test j["menu"]["items"][3] == nothing
                    @test j["menu"]["items"][2]["id"] == "OpenNew"
                    @test j["menu"]["items"][2]["label"] == "Open New"
                end

validate_flickr(flickr) = begin
                              k = JSON.parse(flickr)
                              @test k != nothing
                              @test k["totalItems"] == 222
                              @test k["items"][1]["description"][12] == '\"'
                          end

validate_unicode(unicode) = begin
                                u = JSON.parse(unicode)
                                @test u != nothing
                                @test u["অলিম্পিকস"]["রেকর্ড"][2]["Marathon"] == "জনি হেইস"
                            end
# -------

finished_async_tests = RemoteRef()

@async begin
    s = listen(7777)
    s = accept(s)

    s.line_buffered = false
    Base.start_reading(s)

    @test JSON.parse(s) != nothing  # a
    @test JSON.parse(s) != nothing  # b
    validate_c(s)                     # c
    @test JSON.parse(s) != nothing  # d
    validate_e(s)                     # e
    @test JSON.parse(s) != nothing  # gmaps
    @test JSON.parse(s) != nothing  # colors1
    @test JSON.parse(s) != nothing  # colors2
    @test JSON.parse(s) != nothing  # colors3
    @test JSON.parse(s) != nothing  # twitter
    @test JSON.parse(s) != nothing  # facebook
    validate_flickr(s)                # flickr
    @test JSON.parse(s) != nothing  # youtube
    @test JSON.parse(s) != nothing  # iphone
    @test JSON.parse(s) != nothing  # customer
    @test JSON.parse(s) != nothing  # product
    @test JSON.parse(s) != nothing  # interop
    validate_unicode(s)               # unicode
    @test JSON.parse(s) != nothing  # issue5
    @test JSON.parse(s) != nothing  # dollars
    @test JSON.parse(s) != nothing  # brackets

    put!(finished_async_tests, nothing)
end

w = connect("localhost", 7777)

@test JSON.parse(a) != nothing
write(w, a)

@test JSON.parse(b) != nothing
write(w, b)

validate_c(c)
write(w, c)

@test JSON.parse(d) != nothing
write(w, d)

validate_e(e)
write(w, e)

@test JSON.parse(gmaps) != nothing
write(w, gmaps)

@test JSON.parse(colors1) != nothing
write(w, colors1)

@test JSON.parse(colors2) != nothing
write(w, colors2)

@test JSON.parse(colors3) != nothing
write(w, colors3)

@test JSON.parse(twitter) != nothing
write(w, twitter)

@test JSON.parse(facebook) != nothing
write(w, facebook)

validate_flickr(flickr)
write(w, flickr)

@test JSON.parse(youtube) != nothing
write(w, youtube)

@test JSON.parse(iphone) != nothing
write(w, iphone)

@test JSON.parse(customer) != nothing
write(w, customer)

@test JSON.parse(product) != nothing
write(w, product)

@test JSON.parse(interop) != nothing
write(w, interop)

validate_unicode(unicode)
write(w, unicode)


#Issue 5 on Github
issue5 = "[\"A\",\"B\",\"C\\n\"]"
JSON.parse(issue5)
write(w, issue5)

# $ escaping issue
dollars = ["all of the \$s", "µniçø∂\$"]
json_dollars = json(dollars)
@test JSON.parse(json_dollars) != nothing
write(w, json_dollars)

# unmatched brackets
brackets = @compat Dict("foo"=>"ba}r", "be}e]p"=>"boo{p")
json_brackets = json(brackets)
@test JSON.parse(json_brackets) != nothing
write(w, json_dollars)

fetch(finished_async_tests)

zeros = @compat Dict("\0"=>"\0")
json_zeros = json(zeros)
@test contains(json_zeros,"\\u0000")
@test !contains(json_zeros,"\\0")
@test JSON.parse(json_zeros) == zeros

#Uncomment while doing timing tests
#@time for i=1:100 ; JSON.parse(d) ; end


# Printing an empty array or Dict shouldn't cause a BoundsError
@test json(ASCIIString[]) == "[]"
@test json(Dict()) == "{}"

#test for issue 26
obj = JSON.parse("{\"a\":2e10}")
@test(obj["a"] == 2e10)

#test for issue 21
a=JSON.parse(test21)
@test isa(a, Array{Any})
@test length(a) == 2
#Multidimensional arrays
@test json([0 1; 2 0]) == "[[0,2],[1,0]]"


# ::Nothing values should be encoded as null
testDict = @compat Dict("a" => nothing)
nothingJson = JSON.json(testDict)
nothingDict = JSON.parse(nothingJson)
@test testDict == nothingDict


# test for issue #57
obj = JSON.parse("{\"\U0001d712\":\"\\ud835\\udf12\"}")
@test(obj["𝜒"] == "𝜒")

# test for single values
@test JSON.parse("true") == true
@test JSON.parse("null") == nothing
@test JSON.parse("\"hello\"") == "hello"
@test JSON.parse("\"a\"") == "a"
@test JSON.parse("1") == 1
@test JSON.parse("1.5") == 1.5

# test parsefile
tmppath, io = mktemp()
write(io, facebook)
close(io)
@unix_only @test haskey(JSON.parsefile(tmppath), "data")
# don't use mmap on Windows, to avoid ERROR: unlink: operation not permitted (EPERM)
@windows_only @test haskey(JSON.parsefile(tmppath; use_mmap=false), "data")
rm(tmppath)

# check indented json has same final value as non indented

fb = JSON.parse(facebook)
fbjson1 = json(fb, 2)
fbjson2 = json(fb)
@test JSON.parse(fbjson1) == JSON.parse(fbjson2)

ev = JSON.parse(e)
ejson1 = json(ev, 2)
ejson2 = json(ev)
@test JSON.parse(ejson1) == JSON.parse(ejson2)

# test symbols are treated as strings
symtest = @compat Dict(:symbolarray => [:apple, :pear], :symbolsingleton => :hello)
@test (JSON.json(symtest) == "{\"symbolarray\":[\"apple\",\"pear\"],\"symbolsingleton\":\"hello\"}"
         || JSON.json(symtest) == "{\"symbolsingleton\":\"hello\",\"symbolarray\":[\"apple\",\"pear\"]}")

# test for issue #109
type t109
   i::Int
end
let iob = IOBuffer()
    JSON.print(iob, t109(1))
    @test get(JSON.parse(takebuf_string(iob)), "i", 0) == 1
end

# Tests for Macro strings

let mstr_test = @compat Dict("a" => 1)
    @test mstr_test == json"""{"a":1}"""
    @test mstr_test == json"{'a':1}"single
    @test json"""{"x": 3}"""ordered == DataStructures.OrderedDict{String,Any}([("x",3)])

    @test (@compat Dict("a_number" => 5, "an_array" => ["string"; 9]) ) == json"{'a_number' : 5, 'an_array' : ['string', 9] }"s!

    @test json"""
    {
      "a_number" : 5.0,
      "an_array" : ["string", 9]
    }
    """ == (@compat Dict("a_number" => 5, "an_array" => ["string"; 9]) )

end
