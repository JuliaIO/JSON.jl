using Compat # for RemoteChannel, moved to Distributed
using Distributed

finished_async_tests = RemoteChannel()

@async begin
    s = listen(7777)
    s = accept(s)

    Base.start_reading(s)

    @test JSON.parse(s) != nothing  # sample_a
    @test JSON.parse(s) != nothing  # sample_b
    validate_c(s)                   # sample_c
    @test JSON.parse(s) != nothing  # sample_d
    validate_svg_tviewer_menu(s)    # svg_tviewer_menu
    @test JSON.parse(s) != nothing  # gmaps
    @test JSON.parse(s) != nothing  # colors1
    @test JSON.parse(s) != nothing  # colors2
    @test JSON.parse(s) != nothing  # colors3
    @test JSON.parse(s) != nothing  # twitter
    @test JSON.parse(s) != nothing  # facebook
    validate_flickr(s)              # flickr
    @test JSON.parse(s) != nothing  # youtube
    @test JSON.parse(s) != nothing  # iphone
    @test JSON.parse(s) != nothing  # customer
    @test JSON.parse(s) != nothing  # product
    @test JSON.parse(s) != nothing  # interop
    validate_unicode(s)             # unicode
    @test JSON.parse(s) != nothing  # issue5
    @test JSON.parse(s) != nothing  # dollars
    @test JSON.parse(s) != nothing  # brackets

    put!(finished_async_tests, nothing)
end

w = connect("localhost", 7777)

@test JSON.parse(sample_a) != nothing
write(w, sample_a)

@test JSON.parse(sample_b) != nothing
write(w, sample_b)

validate_c(sample_c)
write(w, sample_c)

@test JSON.parse(sample_d) != nothing
write(w, sample_d)

validate_svg_tviewer_menu(svg_tviewer_menu)
write(w, svg_tviewer_menu)

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

# issue #5
issue5 = "[\"A\",\"B\",\"C\\n\"]"
JSON.parse(issue5)
write(w, issue5)

# $ escaping issue
dollars = ["all of the \$s", "µniçø∂\$"]
json_dollars = json(dollars)
@test JSON.parse(json_dollars) != nothing
write(w, json_dollars)

# unmatched brackets
brackets = Dict("foo"=>"ba}r", "be}e]p"=>"boo{p")
json_brackets = json(brackets)
@test JSON.parse(json_brackets) != nothing
write(w, json_dollars)

fetch(finished_async_tests)
