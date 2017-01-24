using JSON
using Base.Test
import Base.==

#Tests for various type of composite structures, including Nullables
input = "{ \"bar\": { \"baz\": 17 }, \"foo\": 3.14 }"

immutable Bar
    baz::Int
end

immutable Foo
    bar::Bar
end

immutable Baz
    foo::Nullable{Float64}
    bar::Bar
end

immutable Qux
    baz::Nullable{String}
    bar::Bar
end


@test unmarshal(Foo, JSON.parse(input)) == Foo(Bar(17))
@test unmarshal(Baz, JSON.parse(input)) == Baz(Nullable(3.14), Bar(17))
@test unmarshal(Qux, JSON.parse(input)) == Qux(Nullable{String}(),Bar(17))
@test_throws ErrorException unmarshal(Bar, JSON.parse(input)) 

#Test for structures of handling 1-D arrays
type StructOfArrays
        a1 :: Array{Float32, 1}
        a2 :: Array{Int, 1}
    end

function ==(A :: StructOfArrays, B :: StructOfArrays)
    A.a1 == B.a1 && A.a2 == B.a2
end

tmp = StructOfArrays([0,1,2], [1,2,3])
jstring = JSON.json(tmp)
@test unmarshal(StructOfArrays, JSON.parse(jstring)) == tmp

#Test for handling 2-D arrays
type StructOfArrays2D
        a3 :: Array{Float64, 2}
        a4 :: Array{Int, 2}
    end

function ==(A :: StructOfArrays2D, B :: StructOfArrays2D)
    A.a3 == B.a3 && A.a4 == B.a4
end


tmp2 = StructOfArrays2D(ones(Float64, 2, 3), eye(Int, 2, 3))
jstring = JSON.json(tmp2)
@test unmarshal(StructOfArrays2D, JSON.parse(jstring))  == tmp2

#Test for handling N-D arrays
tmp3 = randn(Float64, 2, 3, 4)
jstring = JSON.json(tmp3)
@test unmarshal(Array{Float64, 3}, JSON.parse(jstring))  == tmp3

#Test for handling arrays of composite entities
tmp4 = Array{Array{Int,2}}(2)

tmp4[1] = ones(Int, 3, 4)
tmp4[2] = zeros(Int, 1, 2)
tmp4
jstring = JSON.json(tmp4)
@test unmarshal(Array{Array{Int,2}}, JSON.parse(jstring)) == tmp4

# Test to check handling of complex numbers
tmp5 = zeros(Float32, 2) + 1im * ones(Float32, 2)
jstring = JSON.json(tmp5)
@test unmarshal(Array{Complex{Float32}}, JSON.parse(jstring)) == tmp5

tmp6 = zeros(Float32, 2, 2) + 1im * ones(Float32, 2, 2)
jstring = JSON.json(tmp6)
@test unmarshal(Array{Complex{Float32},2}, JSON.parse(jstring)) == tmp6

# Test to see handling of abstract types
type reconfigurable{T}
    x :: T
    y :: T
    z :: Int
end

type higherlayer
    val :: reconfigurable
end

val = reconfigurable(1.0, 2.0, 3)
jstring = JSON.json(val)
JSON.unmarshal(reconfigurable{Float64}, JSON.parse(jstring))

higher = higherlayer(val)
jstring = JSON.json(higher)
@test_throws ErrorException JSON.unmarshal(higherlayer, JSON.parse(jstring))


