using JSON

require("JSON/test/json_samples")

# Test definitions -------
validate_c(c) = begin
                    j = JSON.parse(c);
                    @assert j != nothing
                    @assert typeof(j["widget"]["image"]["hOffset"]) == Int
                    @assert j["widget"]["image"]["hOffset"] == 250
                    @assert typeof(j["widget"]["text"]["size"]) == Float64
                    @assert j["widget"]["text"]["size"] == 36.5
                end

validate_e(e) = begin
                    j=JSON.parse(e)
                    @assert j != nothing
                    typeof(j) == Dict{String, Any}
                    @assert length(j) == 1
                    typeof(j["menu"]) == Dict{String, Any}
                    @assert length(j["menu"]) == 2
                    @assert j["menu"]["header"] == "SVG\tViewerα"
                    @assert isa(j["menu"]["items"], Array) 
                    @assert length(j["menu"]["items"]) == 22
                    @assert j["menu"]["items"][3] == nothing
                    @assert j["menu"]["items"][2]["id"] == "OpenNew"
                    @assert j["menu"]["items"][2]["label"] == "Open New"
                end

validate_flickr(flickr) = begin
                              k = JSON.parse(flickr)
                              @assert k != nothing
                              @assert k["totalItems"] == 222
                              @assert k["items"][1]["description"][12] == '\"'
                          end

validate_unicode(unicode) = begin
                                u = JSON.parse(unicode)
                                @assert u != nothing
                                @assert u["অলিম্পিকস"]["রেকর্ড"][2]["Marathon"] == "জনি হেইস"
                            end
# -------

finished_async_tests = RemoteRef()

@async begin
    s = listen(7777)
    s = accept(s)

    s.line_buffered = false
    start_reading(s)

    @assert JSON.parse(s) != nothing  # a
    @assert JSON.parse(s) != nothing  # b
    validate_c(s)                     # c
    @assert JSON.parse(s) != nothing  # d
    validate_e(s)                     # e
    @assert JSON.parse(s) != nothing  # gmaps
    @assert JSON.parse(s) != nothing  # colors1
    @assert JSON.parse(s) != nothing  # colors2
    @assert JSON.parse(s) != nothing  # colors3
    @assert JSON.parse(s) != nothing  # twitter
    @assert JSON.parse(s) != nothing  # facebook
    validate_flickr(s)                # flickr
    @assert JSON.parse(s) != nothing  # youtube
    @assert JSON.parse(s) != nothing  # iphone
    @assert JSON.parse(s) != nothing  # customer
    @assert JSON.parse(s) != nothing  # product
    @assert JSON.parse(s) != nothing  # interop
    validate_unicode(s)               # unicode
    @assert JSON.parse(s) != nothing  # issue5
    @assert JSON.parse(s) != nothing  # dollars
    @assert JSON.parse(s) != nothing  # brackets

    put(finished_async_tests, nothing)
end

w = TcpSocket()
connect(w, "localhost", 7777)

@assert JSON.parse(a) != nothing
write(w, a)

@assert JSON.parse(b) != nothing
write(w, b)

validate_c(c)
write(w, c)

@assert JSON.parse(d) != nothing
write(w, d)

validate_e(e)
write(w, e)

@assert JSON.parse(gmaps) != nothing
write(w, gmaps)

@assert JSON.parse(colors1) != nothing
write(w, colors1)

@assert JSON.parse(colors2) != nothing
write(w, colors2)

@assert JSON.parse(colors3) != nothing
write(w, colors3)

@assert JSON.parse(twitter) != nothing
write(w, twitter)

@assert JSON.parse(facebook) != nothing
write(w, facebook)

validate_flickr(flickr)
write(w, flickr)

@assert JSON.parse(youtube) != nothing
write(w, youtube)

@assert JSON.parse(iphone) != nothing
write(w, iphone)

@assert JSON.parse(customer) != nothing
write(w, customer)

@assert JSON.parse(product) != nothing
write(w, product)

@assert JSON.parse(interop) != nothing
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
@assert JSON.parse(json_dollars) != nothing
write(w, json_dollars)

# unmatched brackets
brackets = {"foo"=>"ba}r", "be}e]p"=>"boo{p"}
json_brackets = json(brackets)
@assert JSON.parse(json_brackets) != nothing
write(w, json_dollars)

fetch(finished_async_tests)

#Uncomment while doing timing tests
#@time for i=1:100 ; JSON.parse(d) ; end


# Printing an empty array or Dict shouldn't cause a BoundsError
@assert json(ASCIIString[]) == "[]"
@assert json(Dict()) == "{}"

#test for issue 26
obj = JSON.parse("{\"a\":2e10}")
@assert(obj["a"] == 2e10)

#test for issue 21
a=JSON.parse(test21)
@assert isa(a, Array{Any})
@assert length(a) == 2
