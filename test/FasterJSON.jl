require("JSON/src/FasterJSON")

require("JSON/test/JSON_samples")


@assert FasterJSON.parse(a) != nothing
@assert FasterJSON.parse(b) != nothing
@assert FasterJSON.parse(c) != nothing
@assert FasterJSON.parse(d) != nothing

cj=FasterJSON.parse(c);
@assert typeof(cj["widget"]["image"]["hOffset"]) == Int
@assert cj["widget"]["image"]["hOffset"] == 250
@assert typeof(cj["widget"]["text"]["size"]) == Float64
@assert cj["widget"]["text"]["size"] == 36.5

j=FasterJSON.parse(e) 
@assert  j!= nothing
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



@assert FasterJSON.parse(gmaps) != nothing
@assert FasterJSON.parse(colors1) != nothing
@assert FasterJSON.parse(colors2) != nothing
@assert FasterJSON.parse(colors3) != nothing
@assert FasterJSON.parse(twitter) != nothing
@assert FasterJSON.parse(facebook) != nothing

k=FasterJSON.parse(flickr)
@assert k!= nothing
@assert k["totalItems"] == 222
@assert k["items"][1]["description"][12] == '\"'
@assert FasterJSON.parse(youtube) != nothing
@assert FasterJSON.parse(iphone) != nothing
@assert FasterJSON.parse(customer) != nothing
@assert FasterJSON.parse(product) != nothing
@assert FasterJSON.parse(interop) != nothing

u=FasterJSON.parse(unicode) 
@assert u!=nothing
@assert u["অলিম্পিকস"]["রেকর্ড"][2]["Marathon"] == "জনি হেইস"

#Issue 5 on Github
issue5 = "[\"A\",\"B\",\"C\\n\"]"
FasterJSON.parse(issue5)

#Uncomment while doing timing tests
#@time for i=1:100 ; FasterJSON.parse(d) ; end
