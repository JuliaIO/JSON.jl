require("JSON")

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
                    @assert typeof(j["menu"]["items"]) == Array{Any,1}
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

@assert JSON.parse(a) != nothing
@assert JSON.parse(IOBuffer(a)) != nothing

@assert JSON.parse(b) != nothing
@assert JSON.parse(IOBuffer(b)) != nothing

validate_c(c)
validate_c(IOBuffer(c))

@assert JSON.parse(d) != nothing
@assert JSON.parse(IOBuffer(d)) != nothing

validate_e(e)
validate_e(IOBuffer(e))


@assert JSON.parse(gmaps) != nothing
@assert JSON.parse(IOBuffer(gmaps)) != nothing

@assert JSON.parse(colors1) != nothing
@assert JSON.parse(IOBuffer(colors1)) != nothing

@assert JSON.parse(colors2) != nothing
@assert JSON.parse(IOBuffer(colors2)) != nothing

@assert JSON.parse(colors3) != nothing
@assert JSON.parse(IOBuffer(colors3)) != nothing

@assert JSON.parse(twitter) != nothing
@assert JSON.parse(IOBuffer(twitter)) != nothing

@assert JSON.parse(facebook) != nothing
@assert JSON.parse(IOBuffer(facebook)) != nothing

validate_flickr(flickr)
validate_flickr(IOBuffer(flickr))

@assert JSON.parse(youtube) != nothing
@assert JSON.parse(IOBuffer(youtube)) != nothing

@assert JSON.parse(iphone) != nothing
@assert JSON.parse(IOBuffer(iphone)) != nothing

@assert JSON.parse(customer) != nothing
@assert JSON.parse(IOBuffer(customer)) != nothing

@assert JSON.parse(product) != nothing
@assert JSON.parse(IOBuffer(product)) != nothing

@assert JSON.parse(interop) != nothing
@assert JSON.parse(IOBuffer(interop)) != nothing

validate_unicode(unicode)
validate_unicode(IOBuffer(unicode))


#Issue 5 on Github
issue5 = "[\"A\",\"B\",\"C\\n\"]"
JSON.parse(issue5)
JSON.parse(IOBuffer(issue5))


#Uncomment while doing timing tests
#@time for i=1:100 ; JSON.parse(d) ; end


# Printing an empty array or Dict shouldn't cause a BoundsError
@assert JSON.to_json(ASCIIString[]) == "[]"
@assert JSON.to_json(Dict()) == "{}"
