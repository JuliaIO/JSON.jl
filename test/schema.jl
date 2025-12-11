using Test, JSON, Dates, StructUtils

@testset "JSON Schema Generation" begin
    @testset "Primitive Types" begin
        # Integer
        @defaults struct SimpleInt
            value::Int = 0
        end
        schema = JSON.schema(SimpleInt)
        @test schema["\$schema"] == "https://json-schema.org/draft-07/schema#"
        @test schema["type"] == "object"
        @test schema["properties"]["value"]["type"] == "integer"
        @test schema["required"] == ["value"]

        # Float
        @defaults struct SimpleFloat
            value::Float64 = 0.0
        end
        schema = JSON.schema(SimpleFloat)
        @test schema["properties"]["value"]["type"] == "number"

        # String
        @defaults struct SimpleString
            value::String = ""
        end
        schema = JSON.schema(SimpleString)
        @test schema["properties"]["value"]["type"] == "string"

        # Boolean
        @defaults struct SimpleBool
            value::Bool = false
        end
        schema = JSON.schema(SimpleBool)
        @test schema["properties"]["value"]["type"] == "boolean"
    end

    @testset "Optional Fields (Union{T, Nothing})" begin
        @defaults struct OptionalFields
            required_field::String = ""
            optional_field::Union{String, Nothing} = nothing
            another_optional::Union{Int, Nothing} = nothing
        end

        schema = JSON.schema(OptionalFields)
        @test "required_field" in schema["required"]
        @test !("optional_field" in schema["required"])
        @test !("another_optional" in schema["required"])

        # Optional field should allow null type
        @test schema["properties"]["optional_field"]["type"] == ["string", "null"]
        @test schema["properties"]["another_optional"]["type"] == ["integer", "null"]
    end

    @testset "String Validation Tags" begin
        @defaults struct StringValidation
            email::String = "" &(json=(
                description="Email address",
                format="email",
                minLength=5,
                maxLength=100
            ),)
            username::String = "" &(json=(
                pattern="^[a-zA-Z0-9_]+\$",
                minLength=3,
                maxLength=20
            ),)
            website::Union{String, Nothing} = nothing &(json=(
                format="uri",
                description="Personal website URL"
            ),)
        end

        schema = JSON.schema(StringValidation)

        # Email field
        @test schema["properties"]["email"]["type"] == "string"
        @test schema["properties"]["email"]["format"] == "email"
        @test schema["properties"]["email"]["minLength"] == 5
        @test schema["properties"]["email"]["maxLength"] == 100
        @test schema["properties"]["email"]["description"] == "Email address"

        # Username field
        @test schema["properties"]["username"]["pattern"] == "^[a-zA-Z0-9_]+\$"
        @test schema["properties"]["username"]["minLength"] == 3
        @test schema["properties"]["username"]["maxLength"] == 20

        # Website field (optional)
        @test schema["properties"]["website"]["format"] == "uri"
        @test !("website" in schema["required"])
    end

    @testset "Numeric Validation Tags" begin
        @defaults struct NumericValidation
            age::Int = 0 &(json=(
                minimum=0,
                maximum=150,
                description="Age in years"
            ),)
            price::Float64 = 0.0 &(json=(
                minimum=0.0,
                exclusiveMinimum=true,
                description="Price must be positive"
            ),)
            percentage::Float64 = 0.0 &(json=(
                minimum=0.0,
                maximum=100.0,
                multipleOf=0.1
            ),)
        end

        schema = JSON.schema(NumericValidation)

        # Age
        @test schema["properties"]["age"]["minimum"] == 0
        @test schema["properties"]["age"]["maximum"] == 150

        # Price
        @test schema["properties"]["price"]["minimum"] == 0.0
        @test schema["properties"]["price"]["exclusiveMinimum"] == true

        # Percentage
        @test schema["properties"]["percentage"]["multipleOf"] == 0.1
    end

    @testset "Array Types" begin
        @defaults struct ArrayTypes
            tags::Vector{String} = String[]
            numbers::Vector{Int} = Int[]
            matrix::Vector{Vector{Float64}} = Vector{Vector{Float64}}()
        end

        schema = JSON.schema(ArrayTypes)

        # Tags
        @test schema["properties"]["tags"]["type"] == "array"
        @test schema["properties"]["tags"]["items"]["type"] == "string"

        # Numbers
        @test schema["properties"]["numbers"]["type"] == "array"
        @test schema["properties"]["numbers"]["items"]["type"] == "integer"

        # Matrix (nested arrays)
        @test schema["properties"]["matrix"]["type"] == "array"
        @test schema["properties"]["matrix"]["items"]["type"] == "array"
        @test schema["properties"]["matrix"]["items"]["items"]["type"] == "number"
    end

    @testset "Array Validation Tags" begin
        @defaults struct ArrayValidation
            tags::Vector{String} = String[] &(json=(
                minItems=1,
                maxItems=10,
                description="List of tags"
            ),)
            unique_ids::Vector{Int} = Int[] &(json=(
                uniqueItems=true,
                minItems=1
            ),)
        end

        schema = JSON.schema(ArrayValidation)

        @test schema["properties"]["tags"]["minItems"] == 1
        @test schema["properties"]["tags"]["maxItems"] == 10
        @test schema["properties"]["unique_ids"]["uniqueItems"] == true
    end

    @testset "Nested Structs" begin
        @defaults struct Address
            street::String = ""
            city::String = ""
            zipcode::String = "" &(json=(pattern="^[0-9]{5}\$",),)
        end

        @defaults struct Person
            name::String = ""
            age::Int = 0
            address::Address = Address()
        end

        schema = JSON.schema(Person)

        @test schema["properties"]["address"]["type"] == "object"
        @test haskey(schema["properties"]["address"], "properties")
        @test schema["properties"]["address"]["properties"]["street"]["type"] == "string"
        @test schema["properties"]["address"]["properties"]["city"]["type"] == "string"
        @test schema["properties"]["address"]["properties"]["zipcode"]["pattern"] == "^[0-9]{5}\$"
    end

    @testset "Field Renaming" begin
        @defaults struct RenamedFields
            internal_id::Int = 0 &(json=(name="id",),)
            first_name::String = "" &(json=(name="firstName",),)
            last_name::String = "" &(json=(name="lastName",),)
        end

        schema = JSON.schema(RenamedFields)

        @test haskey(schema["properties"], "id")
        @test haskey(schema["properties"], "firstName")
        @test haskey(schema["properties"], "lastName")
        @test !haskey(schema["properties"], "internal_id")
        @test !haskey(schema["properties"], "first_name")
        @test !haskey(schema["properties"], "last_name")
    end

    @testset "Ignored Fields" begin
        @defaults struct WithIgnored
            public_field::String = ""
            private_field::String = "" &(json=(ignore=true,),)
            another_public::Int = 0
        end

        schema = JSON.schema(WithIgnored)

        @test haskey(schema["properties"], "public_field")
        @test haskey(schema["properties"], "another_public")
        @test !haskey(schema["properties"], "private_field")
        @test length(schema["properties"]) == 2
    end

    @testset "Enum and Const" begin
        @defaults struct WithEnum
            status::String = "pending" &(json=(
                enum=["pending", "active", "inactive"],
                description="Account status"
            ),)
            api_version::String = "v1" &(json=(
                _const="v1",
                description="API version (fixed)"
            ),)
        end

        schema = JSON.schema(WithEnum)

        @test schema["properties"]["status"]["enum"] == ["pending", "active", "inactive"]
        @test schema["properties"]["api_version"]["const"] == "v1"
    end

    @testset "Examples and Default" begin
        @defaults struct WithExamples
            color::String = "blue" &(json=(
                examples=["red", "green", "blue"],
                description="Favorite color"
            ),)
            count::Int = 10 &(json=(
                default=10,
                description="Default count"
            ),)
        end

        schema = JSON.schema(WithExamples)

        @test schema["properties"]["color"]["examples"] == ["red", "green", "blue"]
        @test schema["properties"]["count"]["default"] == 10
    end

    @testset "Dict and Set Types" begin
        @defaults struct CollectionTypes
            metadata::Dict{String, Any} = Dict{String, Any}()
            string_map::Dict{String, String} = Dict{String, String}()
            unique_tags::Set{String} = Set{String}()
        end

        schema = JSON.schema(CollectionTypes)

        # Dict with Any values
        @test schema["properties"]["metadata"]["type"] == "object"
        @test haskey(schema["properties"]["metadata"], "additionalProperties")

        # Dict with String values
        @test schema["properties"]["string_map"]["type"] == "object"
        @test schema["properties"]["string_map"]["additionalProperties"]["type"] == "string"

        # Set
        @test schema["properties"]["unique_tags"]["type"] == "array"
        @test schema["properties"]["unique_tags"]["uniqueItems"] == true
        @test schema["properties"]["unique_tags"]["items"]["type"] == "string"
    end

    @testset "Tuple Types" begin
        @defaults struct WithTuple
            coordinates::Tuple{Float64, Float64} = (0.0, 0.0)
            rgb::Tuple{Int, Int, Int} = (0, 0, 0)
        end

        schema = JSON.schema(WithTuple)

        # Coordinates (2-tuple of floats)
        @test schema["properties"]["coordinates"]["type"] == "array"
        @test schema["properties"]["coordinates"]["minItems"] == 2
        @test schema["properties"]["coordinates"]["maxItems"] == 2
        @test length(schema["properties"]["coordinates"]["items"]) == 2
        @test all(item["type"] == "number" for item in schema["properties"]["coordinates"]["items"])

        # RGB (3-tuple of ints)
        @test schema["properties"]["rgb"]["minItems"] == 3
        @test schema["properties"]["rgb"]["maxItems"] == 3
        @test all(item["type"] == "integer" for item in schema["properties"]["rgb"]["items"])
    end

    @testset "Complex Union Types" begin
        @defaults struct ComplexUnion
            value::Union{Int, String, Nothing} = nothing
        end

        schema = JSON.schema(ComplexUnion)

        # Should use oneOf for complex unions (Julia Union means exactly one type)
        @test haskey(schema["properties"]["value"], "oneOf")
        @test length(schema["properties"]["value"]["oneOf"]) == 3
    end

    @testset "Explicit Required Override" begin
        @defaults struct RequiredOverride
            # Explicitly mark as required even though it's Union{T, Nothing}
            must_provide::Union{String, Nothing} = nothing &(json=(required=true,),)
            # Explicitly mark as optional even though it's not a union
            can_skip::String = "" &(json=(required=false,),)
        end

        schema = JSON.schema(RequiredOverride)

        @test "must_provide" in schema["required"]
        @test !("can_skip" in schema["required"])
    end

    @testset "Top-level Schema Options" begin
        @defaults struct MyType
            value::Int = 0
        end

        schema = JSON.schema(MyType,
            title="Custom Title",
            description="Custom description for the schema",
            id="https://example.com/schemas/my-type.json"
        )

        @test schema["title"] == "Custom Title"
        @test schema["description"] == "Custom description for the schema"
        @test schema["\$id"] == "https://example.com/schemas/my-type.json"
    end

    @testset "Schema Type" begin
        @defaults struct SchemaTypeTest
            value::Int = 0
        end

        schema = JSON.schema(SchemaTypeTest)

        # Test that we get a Schema{T} object
        @test schema isa JSON.Schema{SchemaTypeTest}
        @test schema.type === SchemaTypeTest

        # Test that we can access properties via indexing
        @test schema["type"] == "object"
        @test haskey(schema, "properties")

        # Test JSON serialization
        json_str = JSON.json(schema)
        @test occursin("object", json_str)
        @test occursin("value", json_str)
    end

    @testset "Comprehensive Example - User Registration" begin
        @defaults struct UserRegistration
            # Required fields with validation
            username::String = "" &(json=(
                description="Unique username for the account",
                pattern="^[a-zA-Z0-9_]{3,20}\$",
                minLength=3,
                maxLength=20
            ),)

            email::String = "" &(json=(
                description="User's email address",
                format="email",
                maxLength=255
            ),)

            password::String = "" &(json=(
                description="Account password",
                minLength=8,
                maxLength=128,
                pattern="^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).*\$"
            ),)

            age::Int = 0 &(json=(
                description="User's age",
                minimum=13,
                maximum=150
            ),)

            # Optional fields
            phone::Union{String, Nothing} = nothing &(json=(
                description="Phone number",
                pattern="^\\+?[1-9]\\d{1,14}\$"
            ),)

            website::Union{String, Nothing} = nothing &(json=(
                description="Personal website",
                format="uri"
            ),)

            # Array with validation
            interests::Vector{String} = String[] &(json=(
                description="List of interests",
                minItems=1,
                maxItems=10,
                uniqueItems=true
            ),)

            # Enum field
            account_type::String = "free" &(json=(
                description="Type of account",
                enum=["free", "premium", "enterprise"],
                default="free"
            ),)

            # Boolean field
            newsletter::Bool = false &(json=(
                description="Subscribe to newsletter",
                default=false
            ),)
        end

        schema = JSON.schema(UserRegistration,
            title="User Registration Schema",
            description="Schema for user registration endpoint",
            id="https://api.example.com/schemas/user-registration.json"
        )

        # Verify structure
        @test schema["\$schema"] == "https://json-schema.org/draft-07/schema#"
        @test schema["\$id"] == "https://api.example.com/schemas/user-registration.json"
        @test schema["title"] == "User Registration Schema"
        @test schema["type"] == "object"

        # Verify required fields
        @test "username" in schema["required"]
        @test "email" in schema["required"]
        @test "password" in schema["required"]
        @test "age" in schema["required"]
        @test !("phone" in schema["required"])
        @test !("website" in schema["required"])

        # Verify username constraints
        @test schema["properties"]["username"]["minLength"] == 3
        @test schema["properties"]["username"]["maxLength"] == 20
        @test schema["properties"]["username"]["pattern"] == "^[a-zA-Z0-9_]{3,20}\$"

        # Verify email format
        @test schema["properties"]["email"]["format"] == "email"

        # Verify password validation
        @test schema["properties"]["password"]["minLength"] == 8

        # Verify age range
        @test schema["properties"]["age"]["minimum"] == 13
        @test schema["properties"]["age"]["maximum"] == 150

        # Verify interests array
        @test schema["properties"]["interests"]["type"] == "array"
        @test schema["properties"]["interests"]["minItems"] == 1
        @test schema["properties"]["interests"]["maxItems"] == 10
        @test schema["properties"]["interests"]["uniqueItems"] == true

        # Verify enum
        @test schema["properties"]["account_type"]["enum"] == ["free", "premium", "enterprise"]

        # Output the schema as JSON for inspection
        json_output = JSON.json(schema, pretty=true)
        @test occursin("User Registration Schema", json_output)
        @test occursin("email", json_output)
    end

    @testset "Nested Complex Example - E-commerce Product" begin
        @defaults struct Price
            amount::Float64 = 0.0 &(json=(
                description="Price amount",
                minimum=0.0,
                exclusiveMinimum=true
            ),)
            currency::String = "USD" &(json=(
                description="Currency code",
                pattern="^[A-Z]{3}\$",
                default="USD"
            ),)
        end

        @defaults struct Dimensions
            length::Float64 = 0.0 &(json=(minimum=0.0,),)
            width::Float64 = 0.0 &(json=(minimum=0.0,),)
            height::Float64 = 0.0 &(json=(minimum=0.0,),)
            unit::String = "cm" &(json=(enum=["cm", "in", "m"],),)
        end

        @defaults struct Product
            id::String = "" &(json=(
                description="Unique product identifier",
                format="uuid"
            ),)
            name::String = "" &(json=(
                description="Product name",
                minLength=1,
                maxLength=200
            ),)
            description::String = "" &(json=(
                description="Product description",
                maxLength=2000
            ),)
            price::Price = Price()
            dimensions::Union{Dimensions, Nothing} = nothing &(json=(
                description="Product dimensions (optional)"
            ),)
            tags::Vector{String} = String[] &(json=(
                description="Product tags",
                uniqueItems=true,
                maxItems=20
            ),)
            in_stock::Bool = true &(json=(
                description="Whether the product is in stock"
            ),)
            quantity::Int = 0 &(json=(
                description="Available quantity",
                minimum=0
            ),)
        end

        schema = JSON.schema(Product, title="Product Schema")

        # Verify nested Price object
        @test schema["properties"]["price"]["type"] == "object"
        @test schema["properties"]["price"]["properties"]["amount"]["minimum"] == 0.0
        @test schema["properties"]["price"]["properties"]["amount"]["exclusiveMinimum"] == true
        @test schema["properties"]["price"]["properties"]["currency"]["pattern"] == "^[A-Z]{3}\$"

        # Verify optional Dimensions
        @test schema["properties"]["dimensions"]["type"] == ["object", "null"]
        @test !("dimensions" in schema["required"])

        # Test full JSON serialization
        json_output = JSON.json(schema, pretty=true)
        @test occursin("Product Schema", json_output)
        @test occursin("uuid", json_output)
        @test occursin("currency", json_output)
    end

    @testset "Schema Validation - Roundtrip" begin
        # Generate schema, serialize to JSON, parse back
        @defaults struct SimpleType
            id::Int = 0
            name::String = ""
        end

        schema = JSON.schema(SimpleType)
        json_str = JSON.json(schema)
        parsed = JSON.parse(json_str)

        @test parsed["type"] == "object"
        @test haskey(parsed, "properties")
        @test parsed["properties"]["id"]["type"] == "integer"
        @test parsed["properties"]["name"]["type"] == "string"
    end

    @testset "Empty Struct" begin
        struct EmptyStruct end

        schema = JSON.schema(EmptyStruct)
        @test schema["type"] == "object"
        @test haskey(schema, "properties")
        @test length(schema["properties"]) == 0
        @test !haskey(schema, "required") || length(schema["required"]) == 0
    end

    @testset "Empty NamedTuple" begin
        schema = JSON.schema(@NamedTuple{}; all_fields_required=true, additionalProperties=false)
        @test schema["type"] == "object"
        @test haskey(schema, "properties")
        @test length(schema["properties"]) == 0
        @test schema["additionalProperties"] == false
        @test !haskey(schema, "required") || length(schema["required"]) == 0
    end

    @testset "Title and Description from Tags" begin
        @defaults struct WithTitleDesc
            value::Int = 0 &(json=(
                title="Value Field",
                description="An important value"
            ),)
        end

        schema = JSON.schema(WithTitleDesc)
        @test schema["properties"]["value"]["title"] == "Value Field"
        @test schema["properties"]["value"]["description"] == "An important value"
    end

    @testset "Validation - String Constraints" begin
        @defaults struct StringValidated
            name::String = "" &(json=(minLength=3, maxLength=10),)
            email::String = "" &(json=(format="email",),)
            username::String = "" &(json=(pattern="^[a-z]+\$",),)
        end

        schema = JSON.schema(StringValidated)

        # Valid instances
        @test JSON.isvalid(schema, StringValidated("abc", "test@example.com", "hello"))
        @test JSON.isvalid(schema, StringValidated("abcdefghij", "a@b.c", "abc"))

        # Invalid: name too short
        @test !JSON.isvalid(schema, StringValidated("ab", "test@example.com", "hello"))

        # Invalid: name too long
        @test !JSON.isvalid(schema, StringValidated("abcdefghijk", "test@example.com", "hello"))

        # Invalid: bad email
        @test !JSON.isvalid(schema, StringValidated("abc", "not-an-email", "hello"))

        # Invalid: pattern mismatch (contains uppercase)
        @test !JSON.isvalid(schema, StringValidated("abc", "test@example.com", "Hello"))
    end

    @testset "Validation - Numeric Constraints" begin
        @defaults struct NumericValidated
            age::Int = 0 &(json=(minimum=0, maximum=150),)
            price::Float64 = 0.0 &(json=(minimum=0.0, exclusiveMinimum=true),)
            percentage::Float64 = 0.0 &(json=(multipleOf=0.5,),)
        end

        schema = JSON.schema(NumericValidated)

        # Valid instances
        @test JSON.isvalid(schema, NumericValidated(25, 10.0, 5.0))
        @test JSON.isvalid(schema, NumericValidated(0, 0.1, 0.5))

        # Invalid: age too high
        @test !JSON.isvalid(schema, NumericValidated(200, 10.0, 5.0))

        # Invalid: age negative
        @test !JSON.isvalid(schema, NumericValidated(-5, 10.0, 5.0))

        # Invalid: price must be > 0 (exclusive)
        @test !JSON.isvalid(schema, NumericValidated(25, 0.0, 5.0))

        # Invalid: not a multiple of 0.5
        @test !JSON.isvalid(schema, NumericValidated(25, 10.0, 5.3))
    end

    @testset "Validation - Array Constraints" begin
        @defaults struct ArrayValidated
            tags::Vector{String} = String[] &(json=(minItems=1, maxItems=5, uniqueItems=true),)
            numbers::Vector{Int} = Int[] &(json=(minItems=2,),)
        end

        schema = JSON.schema(ArrayValidated)

        # Valid instances
        @test JSON.isvalid(schema, ArrayValidated(["a", "b"], [1, 2]))
        @test JSON.isvalid(schema, ArrayValidated(["a"], [1, 2, 3]))

        # Invalid: tags empty (minItems=1)
        @test !JSON.isvalid(schema, ArrayValidated(String[], [1, 2]))

        # Invalid: tags too many (maxItems=5)
        @test !JSON.isvalid(schema, ArrayValidated(["a", "b", "c", "d", "e", "f"], [1, 2]))

        # Invalid: tags not unique
        @test !JSON.isvalid(schema, ArrayValidated(["a", "a"], [1, 2]))

        # Invalid: numbers too few (minItems=2)
        @test !JSON.isvalid(schema, ArrayValidated(["a"], [1]))
    end

    @testset "Validation - Enum and Const" begin
        @defaults struct EnumValidated
            status::String = "active" &(json=(enum=["active", "inactive", "pending"],),)
            version::String = "v1" &(json=(_const="v1",),)
        end

        schema = JSON.schema(EnumValidated)

        # Valid instances
        @test JSON.isvalid(schema, EnumValidated("active", "v1"))
        @test JSON.isvalid(schema, EnumValidated("inactive", "v1"))
        @test JSON.isvalid(schema, EnumValidated("pending", "v1"))

        # Invalid: status not in enum
        @test !JSON.isvalid(schema, EnumValidated("deleted", "v1"))

        # Invalid: version doesn't match const
        @test !JSON.isvalid(schema, EnumValidated("active", "v2"))
    end

    @testset "Validation - Optional Fields" begin
        @defaults struct OptionalValidated
            required_field::String = "" &(json=(minLength=1,),)
            optional_field::Union{String, Nothing} = nothing &(json=(minLength=5,),)
        end

        schema = JSON.schema(OptionalValidated)

        # Valid: required field present, optional omitted
        @test JSON.isvalid(schema, OptionalValidated("test", nothing))

        # Valid: both fields present and valid
        @test JSON.isvalid(schema, OptionalValidated("test", "hello"))

        # Invalid: required field empty
        @test !JSON.isvalid(schema, OptionalValidated("", nothing))

        # Invalid: optional field present but too short
        @test !JSON.isvalid(schema, OptionalValidated("test", "hi"))
    end

    @testset "Validation - Nested Structs" begin
        @defaults struct InnerValidated
            value::Int = 0 &(json=(minimum=1, maximum=10),)
        end

        @defaults struct OuterValidated
            name::String = "" &(json=(minLength=1,),)
            inner::InnerValidated = InnerValidated()
        end

        schema = JSON.schema(OuterValidated)

        # Valid instance
        @test JSON.isvalid(schema, OuterValidated("test", InnerValidated(5)))

        # Invalid: outer field fails
        @test !JSON.isvalid(schema, OuterValidated("", InnerValidated(5)))

        # Invalid: inner field fails
        @test !JSON.isvalid(schema, OuterValidated("test", InnerValidated(0)))
        @test !JSON.isvalid(schema, OuterValidated("test", InnerValidated(11)))
    end

    @testset "Validation - Format Checks" begin
        @defaults struct FormatValidated
            email::String = "" &(json=(format="email",),)
            website::String = "" &(json=(format="uri",),)
            uuid::String = "" &(json=(format="uuid",),)
            timestamp::String = "" &(json=(format="date-time",),)
        end

        schema = JSON.schema(FormatValidated)

        # Valid instance
        @test JSON.isvalid(schema, FormatValidated(
            "user@example.com",
            "https://example.com",
            "550e8400-e29b-41d4-a716-446655440000",
            "2023-01-01T12:00:00Z"
        ))

        # Invalid: bad email
        @test !JSON.isvalid(schema, FormatValidated(
            "not-an-email",
            "https://example.com",
            "550e8400-e29b-41d4-a716-446655440000",
            "2023-01-01T12:00:00Z"
        ))

        # Invalid: bad URI
        @test !JSON.isvalid(schema, FormatValidated(
            "user@example.com",
            "not-a-uri",
            "550e8400-e29b-41d4-a716-446655440000",
            "2023-01-01T12:00:00Z"
        ))

        # Invalid: bad UUID
        @test !JSON.isvalid(schema, FormatValidated(
            "user@example.com",
            "https://example.com",
            "not-a-uuid",
            "2023-01-01T12:00:00Z"
        ))

        # Invalid: bad date-time
        @test !JSON.isvalid(schema, FormatValidated(
            "user@example.com",
            "https://example.com",
            "550e8400-e29b-41d4-a716-446655440000",
            "not-a-date"
        ))
    end

    @testset "Validation - Verbose Mode" begin
        @defaults struct VerboseTest
            name::String = "" &(json=(minLength=3,),)
            age::Int = 0 &(json=(minimum=0, maximum=150),)
        end

        schema = JSON.schema(VerboseTest)
        invalid = VerboseTest("ab", 200)

        # Test verbose=false (default)
        @test !JSON.isvalid(schema, invalid)

        # Test verbose=true (should print errors but we can't easily capture them)
        # Just verify it still returns false
        @test !JSON.isvalid(schema, invalid, verbose=true)
    end

    @testset "Validation - Complex Real-World Example" begin
        @defaults struct ValidatedProduct
            id::String = "" &(json=(format="uuid",),)
            name::String = "" &(json=(minLength=1, maxLength=200),)
            price::Float64 = 0.0 &(json=(minimum=0.0, exclusiveMinimum=true),)
            tags::Vector{String} = String[] &(json=(uniqueItems=true, maxItems=10),)
            in_stock::Bool = true
            quantity::Int = 0 &(json=(minimum=0,),)
        end

        schema = JSON.schema(ValidatedProduct)

        # Valid product
        valid_product = ValidatedProduct(
            "550e8400-e29b-41d4-a716-446655440000",
            "Test Product",
            19.99,
            ["electronics", "sale"],
            true,
            100
        )
        @test JSON.isvalid(schema, valid_product)

        # Invalid: bad UUID
        @test !JSON.isvalid(schema, ValidatedProduct("not-uuid", "Test", 19.99, ["tag"], true, 100))

        # Invalid: name too long
        @test !JSON.isvalid(schema, ValidatedProduct(
            "550e8400-e29b-41d4-a716-446655440000",
            repeat("a", 201),
            19.99,
            ["tag"],
            true,
            100
        ))

        # Invalid: price must be > 0
        @test !JSON.isvalid(schema, ValidatedProduct(
            "550e8400-e29b-41d4-a716-446655440000",
            "Test",
            0.0,
            ["tag"],
            true,
            100
        ))

        # Invalid: duplicate tags
        @test !JSON.isvalid(schema, ValidatedProduct(
            "550e8400-e29b-41d4-a716-446655440000",
            "Test",
            19.99,
            ["tag", "tag"],
            true,
            100
        ))

        # Invalid: negative quantity
        @test !JSON.isvalid(schema, ValidatedProduct(
            "550e8400-e29b-41d4-a716-446655440000",
            "Test",
            19.99,
            ["tag"],
            true,
            -5
        ))
    end
end

    @testset "Composition - Union Types (oneOf)" begin
        # Julia Union types automatically generate oneOf schemas
        @defaults struct UnionType
            value::Union{Int, String} = 0
        end

        schema = JSON.schema(UnionType)

        # Check that oneOf was generated
        @test haskey(schema["properties"]["value"], "oneOf")
        @test length(schema["properties"]["value"]["oneOf"]) == 2

        # Validate integer value
        @test JSON.isvalid(schema, UnionType(42))

        # Validate string value
        @test JSON.isvalid(schema, UnionType("hello"))
    end

    @testset "Composition - oneOf Manual" begin
        # You can also manually specify oneOf with field tags
        @defaults struct ManualOneOf
            value::Int = 0 &(json=(
                oneOf=[
                    Dict("type" => "integer", "minimum" => 0, "maximum" => 10),
                    Dict("type" => "integer", "minimum" => 100, "maximum" => 110)
                ],
            ),)
        end

        schema = JSON.schema(ManualOneOf)

        # Valid: matches first schema (0-10)
        @test JSON.isvalid(schema, ManualOneOf(5))

        # Valid: matches second schema (100-110)
        @test JSON.isvalid(schema, ManualOneOf(105))

        # Invalid: matches neither schema (in the gap)
        @test !JSON.isvalid(schema, ManualOneOf(50))

        # Invalid: matches both schemas (if we had overlap, this would fail)
        # The value must match EXACTLY one schema
    end

    @testset "Composition - anyOf" begin
        @defaults struct AnyOfExample
            value::String = "" &(json=(
                anyOf=[
                    Dict("minLength" => 5),      # At least 5 chars
                    Dict("pattern" => "^[A-Z]")  # OR starts with uppercase
                ],
            ),)
        end

        schema = JSON.schema(AnyOfExample)

        # Valid: matches first constraint (>= 5 chars)
        @test JSON.isvalid(schema, AnyOfExample("hello"))

        # Valid: matches second constraint (starts with uppercase)
        @test JSON.isvalid(schema, AnyOfExample("Hi"))

        # Valid: matches both constraints
        @test JSON.isvalid(schema, AnyOfExample("Hello"))

        # Invalid: matches neither constraint
        @test !JSON.isvalid(schema, AnyOfExample("hi"))
    end

    @testset "Composition - allOf" begin
        @defaults struct AllOfExample
            value::String = "" &(json=(
                allOf=[
                    Dict("minLength" => 5),      # At least 5 chars
                    Dict("pattern" => "^[A-Z]")  # AND starts with uppercase
                ],
            ),)
        end

        schema = JSON.schema(AllOfExample)

        # Valid: matches both constraints
        @test JSON.isvalid(schema, AllOfExample("Hello"))
        @test JSON.isvalid(schema, AllOfExample("WORLD"))

        # Invalid: doesn't match first constraint (too short)
        @test !JSON.isvalid(schema, AllOfExample("Hi"))

        # Invalid: doesn't match second constraint (lowercase start)
        @test !JSON.isvalid(schema, AllOfExample("hello"))
    end

    @testset "Composition - Complex Union Types" begin
        @defaults struct ComplexUnion3Types
            # Union of three types
            value::Union{Int, String, Bool} = 0
        end

        schema = JSON.schema(ComplexUnion3Types)

        # Check oneOf was generated with 3 options
        @test haskey(schema["properties"]["value"], "oneOf")
        @test length(schema["properties"]["value"]["oneOf"]) == 3

        # Validate each type
        @test JSON.isvalid(schema, ComplexUnion3Types(42))
        @test JSON.isvalid(schema, ComplexUnion3Types("hello"))
        @test JSON.isvalid(schema, ComplexUnion3Types(true))
    end

    @testset "Composition - Nested Composition" begin
        @defaults struct NestedComposition
            value::Int = 0 &(json=(
                anyOf=[
                    Dict("allOf" => [
                        Dict("minimum" => 0),
                        Dict("maximum" => 10)
                    ]),
                    Dict("allOf" => [
                        Dict("minimum" => 100),
                        Dict("maximum" => 110)
                    ])
                ],
            ),)
        end

        schema = JSON.schema(NestedComposition)

        # Valid: in first range (0-10)
        @test JSON.isvalid(schema, NestedComposition(5))

        # Valid: in second range (100-110)
        @test JSON.isvalid(schema, NestedComposition(105))

        # Invalid: in neither range
        @test !JSON.isvalid(schema, NestedComposition(50))
    end

@testset "Negation - not Combinator" begin
    # Test 1: not with enum
    @defaults struct ExcludedStatus
        status::String = "" &(json=(
            not=Dict("enum" => ["deleted", "archived"]),
        ),)
    end

    schema = JSON.schema(ExcludedStatus)
    @test haskey(schema["properties"]["status"], "not")

    # Valid: status is not in the excluded list
    @test JSON.isvalid(schema, ExcludedStatus("active"))
    @test JSON.isvalid(schema, ExcludedStatus("pending"))

    # Invalid: status is in the excluded list
    @test !JSON.isvalid(schema, ExcludedStatus("deleted"))
    @test !JSON.isvalid(schema, ExcludedStatus("archived"))

    # Test 2: not with type constraint
    @defaults struct NotStringValue
        value::Union{Int, Bool, Nothing} = nothing &(json=(
            not=Dict("type" => "string"),
        ),)
    end

    schema2 = JSON.schema(NotStringValue)

    # Valid: not a string
    @test JSON.isvalid(schema2, NotStringValue(42))
    @test JSON.isvalid(schema2, NotStringValue(true))
    @test JSON.isvalid(schema2, NotStringValue(nothing))

    # Test 3: not with numeric constraint
    @defaults struct ExcludedRange
        value::Int = 0 &(json=(
            not=Dict("minimum" => 10, "maximum" => 20),
        ),)
    end

    schema3 = JSON.schema(ExcludedRange)

    # Valid: outside the excluded range
    @test JSON.isvalid(schema3, ExcludedRange(5))
    @test JSON.isvalid(schema3, ExcludedRange(25))

    # Invalid: inside the excluded range
    @test !JSON.isvalid(schema3, ExcludedRange(10))
    @test !JSON.isvalid(schema3, ExcludedRange(15))
    @test !JSON.isvalid(schema3, ExcludedRange(20))
end

@testset "Array Contains" begin
    # Test 1: contains with enum - must have at least one priority tag
    @defaults struct TaskWithPriority
        tags::Vector{String} = String[] &(json=(
            contains=Dict("enum" => ["urgent", "important", "critical"]),
        ),)
    end

    schema = JSON.schema(TaskWithPriority)
    @test haskey(schema["properties"]["tags"], "contains")

    # Valid: contains at least one priority tag
    @test JSON.isvalid(schema, TaskWithPriority(["urgent", "bug"]))
    @test JSON.isvalid(schema, TaskWithPriority(["feature", "important"]))
    @test JSON.isvalid(schema, TaskWithPriority(["critical"]))
    @test JSON.isvalid(schema, TaskWithPriority(["urgent", "important", "critical"]))

    # Invalid: no priority tags
    @test !JSON.isvalid(schema, TaskWithPriority(["bug", "feature"]))
    @test !JSON.isvalid(schema, TaskWithPriority(["normal"]))
    @test !JSON.isvalid(schema, TaskWithPriority(String[]))

    # Test 2: contains with pattern
    @defaults struct EmailList
        emails::Vector{String} = String[] &(json=(
            contains=Dict("pattern" => "^admin@"),
        ),)
    end

    schema2 = JSON.schema(EmailList)

    # Valid: contains at least one admin email
    @test JSON.isvalid(schema2, EmailList(["admin@example.com", "user@example.com"]))
    @test JSON.isvalid(schema2, EmailList(["admin@test.com"]))

    # Invalid: no admin emails
    @test !JSON.isvalid(schema2, EmailList(["user@example.com"]))

    # Test 3: contains with numeric constraint
    @defaults struct NumberList
        numbers::Vector{Int} = Int[] &(json=(
            contains=Dict("minimum" => 100),
        ),)
    end

    schema3 = JSON.schema(NumberList)

    # Valid: contains at least one number >= 100
    @test JSON.isvalid(schema3, NumberList([50, 100, 150]))
    @test JSON.isvalid(schema3, NumberList([200]))

    # Invalid: all numbers < 100
    @test !JSON.isvalid(schema3, NumberList([50, 75, 99]))
end

@testset "Tuple Validation - Automatic" begin
    # Test 1: Simple tuple
    @defaults struct Point2D
        coords::Tuple{Float64, Float64} = (0.0, 0.0)
    end

    schema = JSON.schema(Point2D)
    @test haskey(schema["properties"]["coords"], "items")
    @test schema["properties"]["coords"]["items"] isa Vector
    @test length(schema["properties"]["coords"]["items"]) == 2

    # Valid tuples
    @test JSON.isvalid(schema, Point2D((1.0, 2.0)))
    @test JSON.isvalid(schema, Point2D((0.0, 0.0)))
    @test JSON.isvalid(schema, Point2D((-5.5, 10.7)))

    # Test 2: Tuple with constraints via items tag
    @defaults struct LatLon
        location::Tuple{Float64, Float64} = (0.0, 0.0) &(json=(
            items=[
                Dict("type" => "number", "minimum" => -90, "maximum" => 90),   # latitude
                Dict("type" => "number", "minimum" => -180, "maximum" => 180)  # longitude
            ],
        ),)
    end

    schema2 = JSON.schema(LatLon)
    @test haskey(schema2["properties"]["location"], "items")
    @test schema2["properties"]["location"]["items"] isa Vector
    @test length(schema2["properties"]["location"]["items"]) == 2

    # Valid: within lat/lon ranges
    @test JSON.isvalid(schema2, LatLon((45.0, -122.0)))
    @test JSON.isvalid(schema2, LatLon((0.0, 0.0)))
    @test JSON.isvalid(schema2, LatLon((90.0, 180.0)))
    @test JSON.isvalid(schema2, LatLon((-90.0, -180.0)))

    # Invalid: latitude out of range
    @test !JSON.isvalid(schema2, LatLon((95.0, 0.0)))
    @test !JSON.isvalid(schema2, LatLon((-95.0, 0.0)))

    # Invalid: longitude out of range
    @test !JSON.isvalid(schema2, LatLon((0.0, 190.0)))
    @test !JSON.isvalid(schema2, LatLon((0.0, -190.0)))

    # Test 3: Mixed type tuple
    @defaults struct MixedTuple
        data::Tuple{String, Int, Bool} = ("", 0, false)
    end

    schema3 = JSON.schema(MixedTuple)
    @test haskey(schema3["properties"]["data"], "items")
    @test schema3["properties"]["data"]["items"] isa Vector
    @test length(schema3["properties"]["data"]["items"]) == 3
    @test schema3["properties"]["data"]["items"][1]["type"] == "string"
    @test schema3["properties"]["data"]["items"][2]["type"] == "integer"
    @test schema3["properties"]["data"]["items"][3]["type"] == "boolean"

    # Valid mixed tuple
    @test JSON.isvalid(schema3, MixedTuple(("hello", 42, true)))

    # Test 4: Tuple with specific constraints per position
    @defaults struct RGB
        color::Tuple{Int, Int, Int} = (0, 0, 0) &(json=(
            items=[
                Dict("minimum" => 0, "maximum" => 255),  # R
                Dict("minimum" => 0, "maximum" => 255),  # G
                Dict("minimum" => 0, "maximum" => 255)   # B
            ],
        ),)
    end

    schema4 = JSON.schema(RGB)

    # Valid RGB values
    @test JSON.isvalid(schema4, RGB((255, 0, 0)))     # Red
    @test JSON.isvalid(schema4, RGB((0, 255, 0)))     # Green
    @test JSON.isvalid(schema4, RGB((0, 0, 255)))     # Blue
    @test JSON.isvalid(schema4, RGB((128, 128, 128))) # Gray

    # Invalid: values out of range
    @test !JSON.isvalid(schema4, RGB((256, 0, 0)))
    @test !JSON.isvalid(schema4, RGB((0, -1, 0)))
    @test !JSON.isvalid(schema4, RGB((0, 0, 300)))
end

@testset "Combined Advanced Features" begin
    # Test combining not, contains, and tuple validation
    @defaults struct AdvancedValidation
        # Array that must contain a priority tag but not contain "spam"
        tags::Vector{String} = String[] &(json=(
            contains=Dict("enum" => ["urgent", "important"]),
            not=Dict("contains" => Dict("const" => "spam")),
        ),)

        # Tuple with coordinate that must not be at origin
        location::Tuple{Float64, Float64} = (0.0, 0.0) &(json=(
            items=[
                Dict("type" => "number"),
                Dict("type" => "number")
            ],
            not=Dict("enum" => [(0.0, 0.0)]),
        ),)
    end

    schema = JSON.schema(AdvancedValidation)

    # Valid: has priority tag, no spam, not at origin
    @test JSON.isvalid(schema, AdvancedValidation(["urgent", "bug"], (1.0, 2.0)))

    # Invalid: no priority tag
    @test !JSON.isvalid(schema, AdvancedValidation(["bug"], (1.0, 2.0)))

    # Test 2: Nested not with composition
    @defaults struct ComplexNot
        value::Int = 0 &(json=(
            # Must be positive but not in the range 10-20
            minimum=0,
            not=Dict("allOf" => [
                Dict("minimum" => 10),
                Dict("maximum" => 20)
            ]),
        ),)
    end

    schema2 = JSON.schema(ComplexNot)

    # Valid: positive and outside 10-20 range
    @test JSON.isvalid(schema2, ComplexNot(5))
    @test JSON.isvalid(schema2, ComplexNot(25))
    @test JSON.isvalid(schema2, ComplexNot(100))

    # Invalid: in the excluded range
    @test !JSON.isvalid(schema2, ComplexNot(10))
    @test !JSON.isvalid(schema2, ComplexNot(15))
    @test !JSON.isvalid(schema2, ComplexNot(20))

    # Invalid: negative (violates minimum)
    @test !JSON.isvalid(schema2, ComplexNot(-5))
end

@testset "Schema References (\$ref)" begin
    @testset "Simple Refs - Basic Usage" begin
        # Define nested types with unique names
        JSON.@defaults struct RefAddress
            street::String = ""
            city::String = ""
            zip::String = ""
        end

        JSON.@defaults struct RefPerson
            name::String = ""
            address::RefAddress = RefAddress()
        end

        # Test without refs (default behavior - inlined)
        schema_inline = JSON.schema(RefPerson)
        @test !haskey(schema_inline.spec, "definitions")
        @test !haskey(schema_inline.spec, "\$defs")
        @test schema_inline.spec["properties"]["address"]["type"] == "object"
        @test haskey(schema_inline.spec["properties"]["address"], "properties")

        # Test with refs=true (uses definitions)
        schema_refs = JSON.schema(RefPerson, refs=true)
        @test haskey(schema_refs.spec, "definitions")
        @test haskey(schema_refs.spec["definitions"], "RefAddress")
        @test haskey(schema_refs.spec["definitions"], "RefPerson")

        # Verify RefPerson definition references RefAddress
        person_def = schema_refs.spec["definitions"]["RefPerson"]
        @test person_def["properties"]["address"]["\$ref"] == "#/definitions/RefAddress"

        # Verify RefAddress definition is complete
        addr_def = schema_refs.spec["definitions"]["RefAddress"]
        @test addr_def["type"] == "object"
        @test haskey(addr_def, "properties")
        @test haskey(addr_def["properties"], "street")
        @test haskey(addr_def["properties"], "city")
        @test haskey(addr_def["properties"], "zip")

        # Test with refs=:defs (Draft 2019+)
        schema_defs = JSON.schema(RefPerson, refs=:defs)
        @test haskey(schema_defs.spec, "\$defs")
        @test haskey(schema_defs.spec["\$defs"], "RefAddress")
        @test haskey(schema_defs.spec["\$defs"], "RefPerson")
    end

    @testset "Circular References" begin
        # Define circular types: RefUser ↔ RefComment
        # Note: We use Int for author_id to avoid forward reference issues
        JSON.@defaults struct RefComment
            id::Int = 0
            text::String = ""
            author_id::Int = 0  # Simplified to avoid circular definition issues
        end

        JSON.@defaults struct RefUser
            id::Int = 0
            name::String = ""
            comments::Vector{RefComment} = RefComment[]
        end

        # Without refs, this would inline and work
        schema_inline = JSON.schema(RefUser)
        @test schema_inline.spec["properties"]["comments"]["items"]["type"] == "object"

        # With refs, types should be deduplicated
        schema_refs = JSON.schema(RefUser, refs=true)

        # Verify both types are in definitions
        @test haskey(schema_refs.spec, "definitions")
        @test haskey(schema_refs.spec["definitions"], "RefUser")
        @test haskey(schema_refs.spec["definitions"], "RefComment")

        # Verify RefUser references RefComment
        user_def = schema_refs.spec["definitions"]["RefUser"]
        @test user_def["properties"]["comments"]["items"]["\$ref"] == "#/definitions/RefComment"

        # RefComment should have Int fields (no circular ref in this simplified version)
        comment_def = schema_refs.spec["definitions"]["RefComment"]
        @test comment_def["properties"]["id"]["type"] == "integer"
        @test comment_def["properties"]["text"]["type"] == "string"
        @test comment_def["properties"]["author_id"]["type"] == "integer"
    end

    @testset "Type Deduplication" begin
        JSON.@defaults struct RefTag
            name::String = ""
        end

        JSON.@defaults struct RefPost
            title::String = ""
            tags::Vector{RefTag} = RefTag[]
            featured_tag::Union{Nothing, RefTag} = nothing
        end

        schema = JSON.schema(RefPost, refs=true)

        # Both RefTag and RefPost should be in definitions
        @test haskey(schema.spec, "definitions")
        @test haskey(schema.spec["definitions"], "RefTag")
        @test haskey(schema.spec["definitions"], "RefPost")

        # Get the Post definition
        post_def = schema.spec["definitions"]["RefPost"]

        # Both tags and featured_tag should reference the same RefTag definition
        @test post_def["properties"]["tags"]["items"]["\$ref"] == "#/definitions/RefTag"
        @test post_def["properties"]["featured_tag"]["oneOf"][1]["\$ref"] == "#/definitions/RefTag"

        # Verify RefTag appears only once (deduplication works)
        @test length(keys(schema.spec["definitions"])) == 2  # RefPost and RefTag
    end

    @testset "Validation with Refs" begin
        JSON.@defaults struct RefContactInfo
            email::String = "" &(json=(format="email",),)
            phone::String = "" &(json=(pattern="^\\d{3}-\\d{3}-\\d{4}\$",),)
        end

        JSON.@defaults struct RefCustomer
            name::String = "" &(json=(minLength=3,),)
            contact::RefContactInfo = RefContactInfo()
        end

        schema = JSON.schema(RefCustomer, refs=true)

        # Valid customer
        valid_customer = RefCustomer("Alice", RefContactInfo("alice@example.com", "555-123-4567"))
        @test JSON.isvalid(schema, valid_customer)

        # Invalid email in nested RefContactInfo
        invalid_email = RefCustomer("Bob", RefContactInfo("not-an-email", "555-123-4567"))
        @test !JSON.isvalid(schema, invalid_email)

        # Invalid phone pattern in nested RefContactInfo
        invalid_phone = RefCustomer("Carol", RefContactInfo("carol@example.com", "1234567890"))
        @test !JSON.isvalid(schema, invalid_phone)

        # Invalid name length in RefCustomer
        invalid_name = RefCustomer("Al", RefContactInfo("al@example.com", "555-123-4567"))
        @test !JSON.isvalid(schema, invalid_name)

        # Multiple violations
        invalid_multi = RefCustomer("X", RefContactInfo("bad-email", "bad-phone"))
        @test !JSON.isvalid(schema, invalid_multi)
    end

    @testset "Shared Context Across Schemas" begin
        JSON.@defaults struct RefDepartment
            name::String = ""
        end

        JSON.@defaults struct RefEmployee
            name::String = ""
            dept::RefDepartment = RefDepartment()
        end

        JSON.@defaults struct RefProject
            title::String = ""
            lead_dept::RefDepartment = RefDepartment()
        end

        # Create shared context
        ctx = JSON.SchemaContext()

        # Generate multiple schemas sharing the same context
        employee_schema = JSON.schema(RefEmployee, context=ctx)
        project_schema = JSON.schema(RefProject, context=ctx)

        # Both schemas should have definitions
        @test haskey(employee_schema.spec, "definitions")
        @test haskey(project_schema.spec, "definitions")

        # Both should reference RefDepartment
        @test haskey(employee_schema.spec["definitions"], "RefDepartment")
        @test haskey(project_schema.spec["definitions"], "RefDepartment")

        # RefDepartment definition should be the same in both
        @test employee_schema.spec["definitions"]["RefDepartment"] == project_schema.spec["definitions"]["RefDepartment"]

        # Context should track all three types
        @test haskey(ctx.type_names, RefEmployee)
        @test haskey(ctx.type_names, RefDepartment)
        @test haskey(ctx.type_names, RefProject)
    end

    @testset "Primitives and Base Types Not Ref'd" begin
        JSON.@defaults struct RefData
            count::Int = 0
            values::Vector{Float64} = Float64[]
            metadata::Dict{String, String} = Dict{String, String}()
        end

        schema = JSON.schema(RefData, refs=true)

        # Root type itself should be in definitions
        @test haskey(schema.spec, "definitions")
        @test haskey(schema.spec["definitions"], "RefData")

        # Check the definition's properties - primitives should not use refs
        data_def = schema.spec["definitions"]["RefData"]
        @test data_def["properties"]["count"]["type"] == "integer"
        @test data_def["properties"]["values"]["type"] == "array"
        @test data_def["properties"]["values"]["items"]["type"] == "number"
        @test data_def["properties"]["metadata"]["type"] == "object"

        # Only RefData itself should be in definitions (no nested user types)
        @test length(keys(schema.spec["definitions"])) == 1
    end

    @testset "Nested Refs - Three Levels Deep" begin
        JSON.@defaults struct RefLevel3
            value::String = ""
        end

        JSON.@defaults struct RefLevel2
            data::RefLevel3 = RefLevel3()
        end

        JSON.@defaults struct RefLevel1
            nested::RefLevel2 = RefLevel2()
        end

        schema = JSON.schema(RefLevel1, refs=true)

        # All three levels should be in definitions
        @test haskey(schema.spec["definitions"], "RefLevel1")
        @test haskey(schema.spec["definitions"], "RefLevel2")
        @test haskey(schema.spec["definitions"], "RefLevel3")

        # Verify reference chain
        @test schema.spec["\$ref"] == "#/definitions/RefLevel1"
        level1_def = schema.spec["definitions"]["RefLevel1"]
        @test level1_def["properties"]["nested"]["\$ref"] == "#/definitions/RefLevel2"
        level2_def = schema.spec["definitions"]["RefLevel2"]
        @test level2_def["properties"]["data"]["\$ref"] == "#/definitions/RefLevel3"
    end

    @testset "Complex Circular - BlogPost Example" begin
        # RefBlogPost has author and comments

        JSON.@defaults struct RefBlogComment
            id::Int = 0
            text::String = ""
            author_id::Int = 0
        end

        JSON.@defaults struct RefBlogAuthor
            id::Int = 0
            name::String = ""
            posts::Vector{Int} = Int[]  # Just IDs to avoid deeper circular
        end

        JSON.@defaults struct RefBlogPost
            title::String = ""
            author::RefBlogAuthor = RefBlogAuthor()
            comments::Vector{RefBlogComment} = RefBlogComment[]
        end

        schema = JSON.schema(RefBlogPost, refs=true)

        # All types should be defined
        @test haskey(schema.spec["definitions"], "RefBlogPost")
        @test haskey(schema.spec["definitions"], "RefBlogAuthor")
        @test haskey(schema.spec["definitions"], "RefBlogComment")

        # Validate a complex instance
        author = RefBlogAuthor(1, "Alice", [1, 2])
        comments = [RefBlogComment(1, "Great post!", 2), RefBlogComment(2, "Thanks!", 1)]
        post = RefBlogPost("My Blog Post", author, comments)

        @test JSON.isvalid(schema, post)
    end

    @testset "Type Name Generation" begin
        # Test module-qualified names
        schema = JSON.schema(JSON.Object{String, Any}, refs=true)
        # Should handle parametric types
        @test schema.spec["type"] == "object"

        # Test Main module types (no module prefix)
        JSON.@defaults struct RefSimpleType
            x::Int = 0
        end

        JSON.@defaults struct RefContainer
            item::RefSimpleType = RefSimpleType()
        end

        schema2 = JSON.schema(RefContainer, refs=true)
        # Should use simple name for Main module types
        @test haskey(schema2.spec["definitions"], "RefSimpleType")
    end
end

@testset "Conditional Schemas (if/then/else)" begin
    @testset "Basic if/then" begin
        # Create a manual schema with if/then
        schema_obj = JSON.Object{String, Any}(
            "type" => "object",
            "properties" => JSON.Object{String, Any}(
                "country" => JSON.Object{String, Any}("type" => "string"),
                "postal_code" => JSON.Object{String, Any}("type" => "string")
            ),
            "if" => JSON.Object{String, Any}(
                "properties" => JSON.Object{String, Any}(
                    "country" => JSON.Object{String, Any}("const" => "US")
                )
            ),
            "then" => JSON.Object{String, Any}(
                "properties" => JSON.Object{String, Any}(
                    "postal_code" => JSON.Object{String, Any}("pattern" => "^[0-9]{5}\$")
                )
            )
        )

        schema = JSON.Schema{Any}(Any, schema_obj, nothing)

        # Test with US country - postal_code must match US format
        us_address = Dict("country" => "US", "postal_code" => "12345")
        @test JSON.isvalid(schema, us_address)

        us_address_invalid = Dict("country" => "US", "postal_code" => "ABC")
        @test !JSON.isvalid(schema, us_address_invalid)

        # Test with non-US country - postal_code not restricted
        uk_address = Dict("country" => "UK", "postal_code" => "ABC 123")
        @test JSON.isvalid(schema, uk_address)
    end

    @testset "if/then/else" begin
        schema_obj = JSON.Object{String, Any}(
            "type" => "object",
            "properties" => JSON.Object{String, Any}(
                "type" => JSON.Object{String, Any}("type" => "string"),
                "value" => JSON.Object{String, Any}()
            ),
            "if" => JSON.Object{String, Any}(
                "properties" => JSON.Object{String, Any}(
                    "type" => JSON.Object{String, Any}("const" => "number")
                )
            ),
            "then" => JSON.Object{String, Any}(
                "properties" => JSON.Object{String, Any}(
                    "value" => JSON.Object{String, Any}("type" => "number")
                )
            ),
            "else" => JSON.Object{String, Any}(
                "properties" => JSON.Object{String, Any}(
                    "value" => JSON.Object{String, Any}("type" => "string")
                )
            )
        )

        schema = JSON.Schema{Any}(Any, schema_obj, nothing)

        # If type is "number", value must be a number
        @test JSON.isvalid(schema, Dict("type" => "number", "value" => 42))
        @test !JSON.isvalid(schema, Dict("type" => "number", "value" => "hello"))

        # If type is not "number", value must be a string
        @test JSON.isvalid(schema, Dict("type" => "text", "value" => "hello"))
        @test !JSON.isvalid(schema, Dict("type" => "text", "value" => 42))
    end
end

@testset "Advanced Object Validation" begin
    @testset "propertyNames - struct" begin
        # Create a struct and validate property names
        JSON.@defaults struct PropNamesTest
            valid_name::String = ""
            another_valid::Int = 0
        end

        schema_obj = JSON.Object{String, Any}(
            "type" => "object",
            "properties" => JSON.Object{String, Any}(
                "valid_name" => JSON.Object{String, Any}("type" => "string"),
                "another_valid" => JSON.Object{String, Any}("type" => "integer")
            ),
            "propertyNames" => JSON.Object{String, Any}(
                "pattern" => "^[a-z_]+\$"
            )
        )

        schema = JSON.Schema{PropNamesTest}(PropNamesTest, schema_obj, nothing)

        # Valid: all property names match pattern
        valid_instance = PropNamesTest("test", 42)
        @test JSON.isvalid(schema, valid_instance)
    end

    @testset "propertyNames - Dict" begin
        schema_obj = JSON.Object{String, Any}(
            "type" => "object",
            "propertyNames" => JSON.Object{String, Any}(
                "pattern" => "^[A-Z]+\$"
            )
        )

        schema = JSON.Schema{Any}(Any, schema_obj, nothing)

        # Valid: all keys are uppercase
        @test JSON.isvalid(schema, Dict("FOO" => 1, "BAR" => 2))

        # Invalid: some keys have lowercase
        @test !JSON.isvalid(schema, Dict("FOO" => 1, "bar" => 2))
    end

    @testset "patternProperties - Dict" begin
        schema_obj = JSON.Object{String, Any}(
            "type" => "object",
            "patternProperties" => JSON.Object{String, Any}(
                "^str_" => JSON.Object{String, Any}("type" => "string"),
                "^num_" => JSON.Object{String, Any}("type" => "number")
            )
        )

        schema = JSON.Schema{Any}(Any, schema_obj, nothing)

        # Valid: keys match patterns with correct value types
        @test JSON.isvalid(schema, Dict("str_name" => "hello", "num_count" => 42))

        # Invalid: str_ key with number value
        @test !JSON.isvalid(schema, Dict("str_name" => 123))

        # Invalid: num_ key with string value
        @test !JSON.isvalid(schema, Dict("num_count" => "hello"))

        # Valid: non-matching keys are not validated
        @test JSON.isvalid(schema, Dict("other" => [1, 2, 3]))
    end

    @testset "dependencies - array form (struct)" begin
        JSON.@defaults struct DepsTest
            credit_card::Union{Nothing, String} = nothing
            billing_address::Union{Nothing, String} = nothing
            security_code::Union{Nothing, String} = nothing
        end

        schema_obj = JSON.Object{String, Any}(
            "type" => "object",
            "properties" => JSON.Object{String, Any}(
                "credit_card" => JSON.Object{String, Any}("type" => ["string", "null"]),
                "billing_address" => JSON.Object{String, Any}("type" => ["string", "null"]),
                "security_code" => JSON.Object{String, Any}("type" => ["string", "null"])
            ),
            "dependencies" => JSON.Object{String, Any}(
                "credit_card" => ["billing_address", "security_code"]
            )
        )

        schema = JSON.Schema{DepsTest}(DepsTest, schema_obj, nothing)

        # Valid: credit_card present with required dependencies
        @test JSON.isvalid(schema, DepsTest("1234", "123 Main St", "999"))

        # Valid: credit_card absent
        @test JSON.isvalid(schema, DepsTest(nothing, nothing, nothing))

        # Invalid: credit_card present but missing billing_address
        @test !JSON.isvalid(schema, DepsTest("1234", nothing, "999"))
    end

    @testset "dependencies - array form (Dict)" begin
        schema_obj = JSON.Object{String, Any}(
            "type" => "object",
            "dependencies" => JSON.Object{String, Any}(
                "credit_card" => ["billing_address"]
            )
        )

        schema = JSON.Schema{Any}(Any, schema_obj, nothing)

        # Valid: credit_card with billing_address
        @test JSON.isvalid(schema, Dict("credit_card" => "1234", "billing_address" => "123 Main"))

        # Valid: no credit_card
        @test JSON.isvalid(schema, Dict("name" => "Alice"))

        # Invalid: credit_card without billing_address
        @test !JSON.isvalid(schema, Dict("credit_card" => "1234"))
    end

    @testset "dependencies - schema form" begin
        schema_obj = JSON.Object{String, Any}(
            "type" => "object",
            "properties" => JSON.Object{String, Any}(
                "name" => JSON.Object{String, Any}("type" => "string"),
                "age" => JSON.Object{String, Any}("type" => "integer")
            ),
            "dependencies" => JSON.Object{String, Any}(
                "age" => JSON.Object{String, Any}(
                    "properties" => JSON.Object{String, Any}(
                        "birth_year" => JSON.Object{String, Any}("type" => "integer")
                    ),
                    "required" => ["birth_year"]
                )
            )
        )

        schema = JSON.Schema{Any}(Any, schema_obj, nothing)

        # Valid: age present with birth_year
        @test JSON.isvalid(schema, Dict("name" => "Alice", "age" => 30, "birth_year" => 1994))

        # Valid: no age
        @test JSON.isvalid(schema, Dict("name" => "Bob"))

        # Invalid: age present without birth_year
        @test !JSON.isvalid(schema, Dict("name" => "Carol", "age" => 25))
    end

    @testset "additionalProperties - struct (false)" begin
        JSON.@defaults struct StrictStruct
            name::String = ""
            age::Int = 0
        end

        schema_obj = JSON.Object{String, Any}(
            "type" => "object",
            "properties" => JSON.Object{String, Any}(
                "name" => JSON.Object{String, Any}("type" => "string")
            ),
            "additionalProperties" => false
        )

        schema = JSON.Schema{StrictStruct}(StrictStruct, schema_obj, nothing)

        # This would fail because 'age' is not in the schema
        # Note: For structs, all fields are present, so we can't really test this
        # in the same way as Dict. The validation checks if struct fields
        # are not in the schema's properties.
        @test !JSON.isvalid(schema, StrictStruct("Alice", 30))
    end

    @testset "additionalProperties - struct (schema)" begin
        JSON.@defaults struct FlexStruct
            name::String = ""
            extra1::Int = 0
        end

        schema_obj = JSON.Object{String, Any}(
            "type" => "object",
            "properties" => JSON.Object{String, Any}(
                "name" => JSON.Object{String, Any}("type" => "string")
            ),
            "additionalProperties" => JSON.Object{String, Any}("type" => "integer")
        )

        schema = JSON.Schema{FlexStruct}(FlexStruct, schema_obj, nothing)

        # Valid: extra1 is integer (matches additionalProperties)
        @test JSON.isvalid(schema, FlexStruct("Alice", 42))
    end
end

@testset "Advanced Array Validation (additionalItems)" begin
    @testset "additionalItems - false" begin
        schema_obj = JSON.Object{String, Any}(
            "type" => "array",
            "items" => [
                JSON.Object{String, Any}("type" => "string"),
                JSON.Object{String, Any}("type" => "number")
            ],
            "additionalItems" => false
        )

        schema = JSON.Schema{Any}(Any, schema_obj, nothing)

        # Valid: exactly 2 items matching the tuple schema
        @test JSON.isvalid(schema, ["hello", 42])

        # Invalid: more than 2 items
        @test !JSON.isvalid(schema, ["hello", 42, "extra"])
    end

    @testset "additionalItems - schema" begin
        schema_obj = JSON.Object{String, Any}(
            "type" => "array",
            "items" => [
                JSON.Object{String, Any}("type" => "string"),
                JSON.Object{String, Any}("type" => "number")
            ],
            "additionalItems" => JSON.Object{String, Any}("type" => "boolean")
        )

        schema = JSON.Schema{Any}(Any, schema_obj, nothing)

        # Valid: first two items match tuple, rest are booleans
        @test JSON.isvalid(schema, ["hello", 42, true, false])

        # Invalid: additional item is not boolean
        @test !JSON.isvalid(schema, ["hello", 42, "not a boolean"])

        # Valid: exactly 2 items (no additional items)
        @test JSON.isvalid(schema, ["hello", 42])
    end

    @testset "additionalItems with no items constraint" begin
        # When items is not an array, additionalItems has no effect
        schema_obj = JSON.Object{String, Any}(
            "type" => "array",
            "items" => JSON.Object{String, Any}("type" => "string"),
            "additionalItems" => false
        )

        schema = JSON.Schema{Any}(Any, schema_obj, nothing)

        # Valid: all items are strings (additionalItems doesn't apply)
        @test JSON.isvalid(schema, ["hello", "world", "foo"])
    end
end

@testset "Validation API and Formats" begin
    @testset "validate vs isvalid" begin
        @defaults struct ValidateTest
            val::Int = 0 &(json=(minimum=10,),)
        end
        schema = JSON.schema(ValidateTest)

        # Valid
        instance = ValidateTest(15)
        res = JSON.validate(schema, instance)
        @test res isa JSON.ValidationResult
        @test res.is_valid == true
        @test isempty(res.errors)
        @test JSON.isvalid(schema, instance) == true

        # Invalid
        instance_invalid = ValidateTest(5)
        res_invalid = JSON.validate(schema, instance_invalid)
        @test res_invalid.is_valid == false
        @test !isempty(res_invalid.errors)
        @test length(res_invalid.errors) == 1
        @test occursin("less than minimum", res_invalid.errors[1])
        @test JSON.isvalid(schema, instance_invalid) == false
    end

    @testset "Improved Format Validation" begin
        @defaults struct FormatTestV2
            email::String = "" &(json=(format="email",),)
            uri::String = "" &(json=(format="uri",),)
            dt::String = "" &(json=(format="date-time",),)
        end
        schema = JSON.schema(FormatTestV2)

        # Email
        @test JSON.isvalid(schema, FormatTestV2("test@example.com", "http://a.com", "2023-01-01T12:00:00Z"))
        @test !JSON.isvalid(schema, FormatTestV2("test @example.com", "http://a.com", "2023-01-01T12:00:00Z"))
        @test !JSON.isvalid(schema, FormatTestV2("test", "http://a.com", "2023-01-01T12:00:00Z"))

        # URI
        @test JSON.isvalid(schema, FormatTestV2("a@b.c", "ftp://example.com", "2023-01-01T12:00:00Z"))
        @test JSON.isvalid(schema, FormatTestV2("a@b.c", "mailto:user@host", "2023-01-01T12:00:00Z"))
        @test !JSON.isvalid(schema, FormatTestV2("a@b.c", "example.com", "2023-01-01T12:00:00Z"))
        @test !JSON.isvalid(schema, FormatTestV2("a@b.c", "http://exa mple.com", "2023-01-01T12:00:00Z"))

        # Date-time
        @test JSON.isvalid(schema, FormatTestV2("a@b.c", "http://a.com", "2023-01-01T12:00:00Z"))
        @test JSON.isvalid(schema, FormatTestV2("a@b.c", "http://a.com", "2023-01-01T12:00:00+00:00"))
        @test JSON.isvalid(schema, FormatTestV2("a@b.c", "http://a.com", "2023-01-01T12:00:00.123Z"))
        @test !JSON.isvalid(schema, FormatTestV2("a@b.c", "http://a.com", "2023-01-01T12:00:00")) # No timezone
        @test !JSON.isvalid(schema, FormatTestV2("a@b.c", "http://a.com", "2023/01/01"))
    end
end
