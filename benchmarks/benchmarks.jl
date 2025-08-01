using JSON, Chairmarks

include(joinpath(dirname(pathof(JSON)), "../benchmarks/structs.jl"))
# test that compile time isn't unreasonable
@time JSON.parse(root_json, Root)

struct A
  a::Int
  b::Int
  c::Int
  d::Int
end

@b JSON.parse("""{ "a": 1,"b": 2,"c": 3,"d": 4}""")
@b JSON.json(A(1, 2, 3, 4))
@b JSON.parse("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", A)
@b JSON.parse("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", Tuple{Int, Int, Int, Int})
@b JSON.parse("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", NamedTuple{(:a, :b, :c, :d), Tuple{Int, Int, Int, Int}})
@b JSON.parse("""[1, 2, 3, 4]""", Tuple{Int, Int, Int, Int})
@b JSON.parse("""[["1", 1], ["2", 2]]""", Vector{Tuple{String, Int}})
@b JSON.parse("""[["1", 1], ["1", 2], ["1", 3], ["1", 4], ["1", 5], ["1", 6], ["1", 7], ["1", 8], ["1", 9], ["1", 10], ["1", 11], ["1", 12], ["1", 13], ["1", 14], ["1", 15], ["1", 16], ["1", 17], ["1", 18], ["1", 19], ["1", 20]]""", Vector{Tuple{String, Int}})

# integers with varying number of digits
@b JSON.parse("""[1,2234,323423423,4234234234234,23232,456454545,56767676,6767,6767,6767676,6767,6767,1,0,-123,-3333]""")
@b JSON.json([1,2234,323423423,4234234234234,23232,456454545,56767676,6767,6767,6767676,6767,6767,1,0,-123,-3333])

# floats
@b JSON.parse("""[1.123,2.345,3e21,-4e-5,5.1234567890123456789,6.1234567890123456789,7.1234567890123456789,8.1234567890123456789,9.1234567890123456789,1.23,3.14,3.43,34.32,-0.001,0.000023,0.123]""")
@b JSON.json([1.123,2.345,3e21,-4e-5,5.1234567890123456789,6.1234567890123456789,7.1234567890123456789,8.1234567890123456789,9.1234567890123456789,1.23,3.14,3.43,34.32,-0.001,0.000023,0.123])

# bools
@b JSON.parse("""[true,false,true,false,true,false,true,false,true,false,true,false,true,false,true,false]""")
@b JSON.json([true,false,true,false,true,false,true,false,true,false,true,false,true,false,true,false])

# nulls
@b JSON.parse("""[null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null]""")
@b JSON.json([nothing,nothing,nothing,nothing,nothing,nothing,nothing,nothing,nothing,nothing,nothing,nothing,nothing,nothing,nothing,nothing])

# strings
@b JSON.parse("""["1","ab","abc","abcd","abcde","abcdef","abcdef","abcdefg","abcdefgh","abcdefghi","abcdefghij","abcdefghijk","abcdefghijkl","abcdefghijklm","abcdefghijklmn","abcdefghijklmno"]""")
@b JSON.json(["1","ab","abc","abcd","abcde","abcdef","abcdef","abcdefg","abcdefgh","abcdefghi","abcdefghij","abcdefghijk","abcdefghijkl","abcdefghijklm","abcdefghijklmn","abcdefghijklmno"])

# strings with json-encoded unicode and escape sequences
@b JSON.parse("""["\\n","\\r","\\t","\\b","\\f","\\\\","\\\"","\\u1234","\\u5678","\\u9abc","\\u9abc","\\uABCD","\\u9abc","\\u1234","\\u5678","\\u9abc"]""")
@b JSON.json(["\\n","\\r","\\t","\\b","\\f","\\\\","\\\"","\\u1234","\\u5678","\\u9abc","\\u9abc","\\uABCD","\\u9abc","\\u1234","\\u5678","\\u9abc"])

# arrays
@b JSON.parse("""[[1,2,3,4],[5,6,7,8],[9,10,11,12],[13,14,15,16],[17,18,19,20],[21,22,23,24],[25,26,27,28],[29,30,31,32],[33,34,35,36],[37,38,39,40],[41,42,43,44],[45,46,47,48],[49,50,51,52],[53,54,55,56],[57,58,59,60],[61,62,63,64]]""")
@b JSON.json([[1,2,3,4],[5,6,7,8],[9,10,11,12],[13,14,15,16],[17,18,19,20],[21,22,23,24],[25,26,27,28],[29,30,31,32],[33,34,35,36],[37,38,39,40],[41,42,43,44],[45,46,47,48],[49,50,51,52],[53,54,55,56],[57,58,59,60],[61,62,63,64]])

# objects
@b JSON.parse("""{ "a": {"a": 1,"b": 2,"c": 3,"d": 4},"b": {"a": 5,"b": 6,"c": 7,"d": 8},"c": {"a": 9,"b": 10,"c": 11,"d": 12},"d": {"a": 13,"b": 14,"c": 15,"d": 16}}""")
@b JSON.json(Dict("a" => Dict("a" => 1,"b" => 2,"c" => 3,"d" => 4),"b" => Dict("a" => 5,"b" => 6,"c" => 7,"d" => 8),"c" => Dict("a" => 9,"b" => 10,"c" => 11,"d" => 12),"d" => Dict("a" => 13,"b" => 14,"c" => 15,"d" => 16)))

# objects with more than 32 keys
@b JSON.parse("""{"a":1,"b":2,"c":3,"d":4,"e":5,"f":6,"g":7,"h":8,"i":9,"j":10,"k":11,"l":12,"m":13,"n":14,"o":15,"p":16,"q":17,"r":18,"s":19,"t":20,"u":21,"v":22,"w":23,"x":24,"y":25,"z":26,"aa":27,"ab":28,"ac":29,"ad":30,"ae":31,"af":32,"ag":33,"ah":34,"ai":35,"aj":36,"ak":37,"al":38,"am":39,"an":40,"ao":41,"ap":42,"aq":43,"ar":44,"as":45,"at":46,"au":47,"av":48,"aw":49,"ax":50,"ay":51,"az":52}""")
@b JSON.json(Dict("a" => 1,"b" => 2,"c" => 3,"d" => 4,"e" => 5,"f" => 6,"g" => 7,"h" => 8,"i" => 9,"j" => 10,"k" => 11,"l" => 12,"m" => 13,"n" => 14,"o" => 15,"p" => 16,"q" => 17,"r" => 18,"s" => 19,"t" => 20,"u" => 21,"v" => 22,"w" => 23,"x" => 24,"y" => 25,"z" => 26,"aa" => 27,"ab" => 28,"ac" => 29,"ad" => 30,"ae" => 31,"af" => 32,"ag" => 33,"ah" => 34,"ai" => 35,"aj" => 36,"ak" => 37,"al" => 38,"am" => 39,"an" => 40,"ao" => 41,"ap" => 42,"aq" => 43,"ar" => 44,"as" => 45,"at" =>46, "au"=>47, "av"=>48, "aw"=>49, "ax"=>50, "ay"=>51, "az"=>52))

# JSON.parse! with mutable struct
@noarg mutable struct B
    a::Int
    b::Int
    c::Int
    d::Int
end

const b = B()
@b JSON.parse!("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", b)

const dict = Dict{String, Any}()
@b JSON.parse!("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", dict)

const ticketjson="{\"topic\":\"trade.BTCUSDT\",\"data\":[{\"symbol\":\"BTCUSDT\",\"tick_direction\":\"PlusTick\",\"price\":\"19431.00\",\"size\":0.2,\"timestamp\":\"2022-10-18T14:50:20.000Z\",\"trade_time_ms\":\"1666104620275\",\"side\":\"Buy\",\"trade_id\":\"e6be9409-2886-5eb6-bec9-de01e1ec6bf6\",\"is_block_trade\":\"false\"},{\"symbol\":\"BTCUSDT\",\"tick_direction\":\"MinusTick\",\"price\":\"19430.50\",\"size\":1.989,\"timestamp\":\"2022-10-18T14:50:20.000Z\",\"trade_time_ms\":\"1666104620299\",\"side\":\"Sell\",\"trade_id\":\"bb706542-5d3b-5e34-8767-c05ab4df7556\",\"is_block_trade\":\"false\"},{\"symbol\":\"BTCUSDT\",\"tick_direction\":\"ZeroMinusTick\",\"price\":\"19430.50\",\"size\":0.007,\"timestamp\":\"2022-10-18T14:50:20.000Z\",\"trade_time_ms\":\"1666104620314\",\"side\":\"Sell\",\"trade_id\":\"a143da10-3409-5383-b557-b93ceeba4ca8\",\"is_block_trade\":\"false\"},{\"symbol\":\"BTCUSDT\",\"tick_direction\":\"PlusTick\",\"price\":\"19431.00\",\"size\":0.001,\"timestamp\":\"2022-10-18T14:50:20.000Z\",\"trade_time_ms\":\"1666104620327\",\"side\":\"Buy\",\"trade_id\":\"7bae9053-e42b-52bd-92c5-6be8a4283525\",\"is_block_trade\":\"false\"}]}"

struct Ticket
  symbol::String
  tick_direction::String
  price::String
  size::Float64
  timestamp::String
  trade_time_ms::String
  side::String
  trade_id::String
  is_block_trade::String
end

struct Tape
  topic::String
  data::Vector{Ticket}
end

@b JSON.parse(ticketjson)
@b JSON.parse(ticketjson, Tape)

const ticket_obj = JSON.parse(ticketjson)
const ticket_struct = JSON.parse(ticketjson, Tape)
@b JSON.json(ticket_obj)
@b JSON.json(ticket_struct)