@test JSON.parse(IOBuffer("123")) == 123
@test JSON.parse(IOBuffer("1.5")) == 1.5
