# Migration guides

This guide provides an overview of how to migrate your code from either the pre-1.0 JSON.jl package to the 1.0 release or from JSON3.jl. The 1.0 release introduces several improvements and changes, particularly in how JSON is read and written, leveraging StructUtils.jl for customization and extensibility. Below, we outline the key differences and provide step-by-step instructions for updating your code.

---

## Migration guide from pre-1.0 -> 1.0

### Writing JSON
- `JSON.json`
  - What stayed the same:
    - Produces a compact String by default
    - Can automatically serialize basic structs in a sensible way
    - Can take an integer 2nd argument to induce "pretty printing" of the JSON output
  - What changed:
    - Can now pass `JSON.json(x; pretty=true)` or `JSON.json(x; pretty=4)` to control pretty printing
    - Can pass filename as first argument to write JSON directly to a file `JSON.json(file, x)` the file name is returned
    - Can pass any `IO` as 1st argument to write JSON to it: `JSON.json(io, x)`
    - Circular reference tracking is fixed/improved (previously peer references were written as null)
    - Explicit keyword arguments to control a number of serialization features, including:
      - `omit_null::Bool` whether `nothing`/`missing` Julia values should be skipped when serializing
      - `omit_empty::Bool` whether empty Julia collection values should be skipped when serializing
      - `allownan::Bool` similar to the parsing keyword argument to allow/disallow writing of invalid JSON values `NaN`, `-Inf`, and `Inf`
      - `ninf::String` the string to write if `allownan=true` and serializing `-Inf`
      - `inf::String` the string to write if `allownan=true` and serializing `Inf`
      - `nan::String` the string to write if `allownan=true` and serializing `NaN`
      - `jsonlines::String` when serializing an array, write each element independently on a new line as an implicit array; can be read back when parsing by also passing `jsonlines=true`
      - `inline_limit::Int` threshold number of elements in an array under which an array should be printed on a single line (only applicable when pretty printing)
      - `float_style::Symbol` allowed values are `:shortest`, `:fixed`, and `:exp` corresponding to printf format styles, `%g`, `%f`, and `%e`, respectively
      - `float_precision::Int` number of decimal places to use when printing floats
  - Why the changes:
    - Mostly just modernizing the interfaces (use of keyword arguments vs. positional)
    - Utilizing multiple dispatch to combine `JSON.print` and `JSON.json` and provide convenience for writing to files
    - Most opened issues over the last few years were about providing more controls around writing JSON without having to completely implement a custom serializer
    - More consistency with `JSON.parse` keyword args with `allownan` and `jsonlines`
- `JSON.print`
  - What stayed the same:
    - Technically still defined for backwards compatibility, but just calls `JSON.json` under the hood
  - Why the changes:
    - Not necessary as all the functionality can be combined without ambiguity or overlap with `JSON.json`
- `JSON.lower`
  - What stayed the same:
    - Still used to transform Julia values into JSON-appropriate values
  - What changed:
    - `lower` technically now lives in the StructUtils.jl package (though overloading in JSON is fine)
    - Can overload for a specific "style" for non-owned types, like `struct MyStyle <: JSON.JSONStyle end`, then `JSON.lower(::MyStyle, x::Rational) = (den=x.den, num=x.num)`, then have the style used when writing like `JSON.json(1//3; style=MyStyle())`
    - Probably don't need to `lower` except in rare cases; there are default `lower` defintions for common types and most structs/AbstractDict/AbstractArray will work out of the box; `lower` is mostly useful when wanting to have the JSON output of a struct be a string or a number, for example, so going between aggregate/non-aggregate from Julia to JSON
  - Why the changes:
    - Along with the new corresponding `lift` interface, the `lower` + `lift` combination is a powerful generalization of doing "domain transformations"
- `JSON.StructuralContext` / `JSON.show_json` / `JSON.Serialization`
  - What stayed the same:
    - These have been removed in favor of simpler interfaces and custom `JSONStyle` subtypes + overloads
  - Why the changes:
    - The use of distinct contexts for different writing styles (pretty, compact) is unnecessary and led to code duplication
    - There was often confusion about whether a custom Serialization or StructuralContext was needed and what intefaces were then required to implement
    - The need to customize separators, delimiters, and indentation, while powerful, can be accomplished much simpler via keyword arguments or is not necessary at all (i.e. JSON.jl shouldn't be too concerned with how to produce anything that isn't JSON)
    - Instead of overloading show_string/show_element/show_key/show_pair/show_json, `lower` can be used to accomplish any requirements of "overloading" how values are serialized; the addition of "styles" also allows customizing for non-owned types instead of needing a custom context + `show_json` method
- `JSONText`
  - What changed:
    - Nothing; `JSONText` can still be used to have a JSON-formatted string be written as-is when serializing

### Reading JSON
- `JSON.parse` / `JSON.parsefile`
  - What stayed the same:
    - These functions take the same JSON input arguments (String, IO, or filename for `parsefile`)
    - The `dicttype`, `allownan`, and `null` keyword arguments all remain and implement the same functionality
  - What changed:
    - `JSON.Object{String, Any}` is now the default type used when parsing instead of `Dict{String, Any}`; `JSON.Object` is a drop-in replacement for `Dict`, supporting the `AbstractDict` interface, mutation, dot-access (getproperty) to keys, memory and performance benefits for small objects vs. `Dict`, and preserves the JSON order of keys. For large objects (hundreds or thousands of keys), or to otherwise restore the pre-1.0 behavior, you can do `JSON.parse(json; dicttype=Dict{String, Any})`.
    - The `inttype` keyword argument has been removed
    - The `allownan` keyword argument now defaults to `false` instead of `true` to provide a more accurate JSON specification behavior as the default
    - The `use_mmap` keyword argument has been removed from `parsefile`; mmapping will now be decided automatically by the package and any mmaps used for parsing will be completely finalized when parsing has finished
    - Numbers in JSON will now be parsed as `Int64`, `BigInt`, `Float64`, or `BigFloat`, instead of only `Int64` or `Float64`. Many JSON libraries support arbitrary precision ints/floats, and now JSON.jl does too.
    - `JSON.parse(json, T)` and `JSON.parse!(json, x)` variants have been added for constructing a Julia value from JSON, or mutating an existing Julia value from JSON; `JSON.parsefile(json, T)` and `JSON.parsefile!(json, x)` are also supported; see [JSON Reading](@ref) for more details
  - Why the changes:
    - The `inttype` keyword argument is rare among other JSON libraries and doesn't serve a strong purpose; memory gains from possibly using smaller ints is minimal and leads to more error-prone code via overflows by trying to force integers into non-standard small types
    - For the `allownan` default value change, there are many benchmarks/JSON-accuracy checking test suites that enforce adherance to the specification; following the specification by default is recommended and common across language JSON libraries
    - Mmapping is an internal detail that most users shouldn't worry about anyway, and it can be done transparently without any outside affect to the user
- `JSONText`
  - `JSONText` can now also be used while parsing, as a field type of a struct or directly to return the raw JSON (similar to how writing with `JSONText` works)

## Migration guide for JSON3.jl

The JSON.jl 1.0 release incorporates many of the design ideas that were originally developed in JSON3.jl. This guide helps you transition your code from JSON3.jl to JSON.jl 1.0, highlighting what's changed, what's similar, and the best way to update your code.

### Writing JSON

- `JSON3.write` → `JSON.json`
  - What stayed the same:
    - The core functionality of serializing Julia values to JSON remains the same
    - Support for serializing custom structs in a sensible way
    - Both can output to a string or IO
  - What changed:
    - Function name: `JSON3.write` becomes `JSON.json`
    - Direct file writing: Instead of `open(file, "w") do io; JSON3.write(io, x); end`, you can use `JSON.json(file, x)`
    - Customization framework: JSON3.jl uses StructTypes.jl, while JSON.jl 1.0 uses StructUtils.jl
    - Pretty printing: `JSON3.pretty(JSON3.write(x))` becomes `JSON.json(x; pretty=true)`
    - Special numeric values: In JSON3.jl, writing NaN/Inf/-Inf required passing `allow_inf=true`, in JSON.jl 1.0 you pass `allownan=true`
  - Why the changes:
    - Preference was given to existing JSON.jl names where possible (`JSON.json`, `allownan`, etc)
    - JSON3 pretty printing support was an example of "bolted on" functionality that had a number of issues because it tried to operate on its own; in `JSON.json`, pretty printing is directly integrated with the core serializing code and thus doesn't suffer the same ergonomic problems
    - StructUtils.jl is overall simpler and provides much more functionality "by default" meaning its much more invisible for majority of use-cases. Its design is the direct result of wanting to provide roughly similar functionality as StructTypes.jl but avoiding the pitfalls and architectural complexities it had

- Custom Type Serialization
  - What stayed the same:
    - Both provide a way to customize how types are serialized
    - Both support serializing custom types to any valid JSON value
  - What changed:
    - Interface: No need to declare `StructTypes.StructType` explicitly on structs (StructUtils.jl can detect the vast majority of struct types automatically)
    - Non-owned types: JSON.jl (via StructUtils) provides the concept of defining a custom `StructStyle` subtype that allows customizing the lowering/lifting overloads of non-owned types (JSON3.jl had repeated requests/issues with users wanting more control over non-owned types without pirating)
  - Why the changes:
    - As noted above, the overall design of StructUtils is simpler and more automatic, with the default definitions working in the vast majority of cases. If you're the author of a custom Number, AbstractString, AbstractArray, or AbstractDict, you may need to dig further into StructUtil machinery to make your types serialize/deserialize as expected, but regular structs should "just work"
    - Defining custom styles is meant to balance having to do some extra work (defining the style, passing it to `JSON.json`/`JSON.parse`) with the power and flexibility of control over how JSON serialization/deserialization work for any type, owned or not

- Field Customization
  - What stayed the same:
    - Both allow renaming fields, excluding fields, and some control over manipulating fields from JSON output (keyword args, dateformats, etc.)
  - What changed:
    - StructUtils provides convenient "struct" macros (`@noarg`, `@kwarg`, `@tags`, `@defaults`, `@nonstruct`) that allow defining default values for fields, and specifying "field tags" which are named tuples of properties for fields. Via field tags, fields can customize naming, ignoring/excluding, dateformating, custom lowering/lifting, and even "type choosing" for abstract types.
  - Why the changes:
    - The field tags and defaults of StructUtils provide very powerful and generalized abilities to specify properties for fields. These are integrated directly with the serialize/deserialize process of StructUtils and provide a seemless way to enhance and control fields as desired. Instead of providing numerous StructType overloads, we can annotate individual fields appropriately, keeping context and information tidy and close to the source.

- Null and Empty Value Handling
  - What stayed the same:
    - Both allow control over including/omitting null values and empty collections
  - What changed:
    - Control mechanism: JSON3.jl uses `StructTypes.omitempties`, JSON.jl 1.0 uses keyword arguments `omit_null` and `omit_empty`; or struct-level overloads or annotations to control omission

### Reading JSON

- `JSON3.read` → `JSON.parse` / `JSON.lazy`
  - What stayed the same:
    - Core functionality of parsing JSON into Julia values
    - Support for typed parsing into custom structs
    - Lazy parsing features
  - What changed:
    - Function names: `JSON3.read` becomes either `JSON.parse` (eager) or `JSON.lazy` (lazy)
    - Default container type: `JSON3.Object/JSON3.Array` becomes `JSON.Object{String, Any}/Vector{Any}`
    - Type integration: JSON3.jl uses StructTypes.jl, JSON.jl 1.0 uses StructUtils.jl
    - Lazy value access: Both use property access syntax (`obj.field`) but with slightly different semantics
  - Migration examples:
    ```julia
    # JSON3.jl
    obj = JSON3.read(json_str)
    typed_obj = JSON3.read(json_str, MyType)
    
    # JSON.jl 1.0
    obj = JSON.parse(json_str)               # eager parsing
    lazy_obj = JSON.lazy(json_str)           # lazy parsing
    materialized = lazy_obj[]                # materialize lazy value
    typed_obj = JSON.parse(json_str, MyType) # typed parsing
    ```

- Lazy Parsing
  - What stayed the same:
    - Both support lazy parsing for efficient access to parts of large JSON documents
    - Both allow dot notation for accessing object fields
  - What changed:
    - Object types: `JSON3.Object` becomes `JSON.LazyValue` with object type
    - Array indexing: Similar, but slight syntax differences for materializing values
    - Materialization: In JSON3.jl specific values materialize when accessed, in JSON.jl 1.0 you explicitly use `[]` to materialize
  - Migration examples:
    ```julia
    # JSON3.jl
    obj = JSON3.read(json_str)
    value = obj.deeply.nested.field  # value is materialized
    
    # JSON.jl 1.0
    obj = JSON.lazy(json_str)
    lazy_value = obj.deeply.nested.field  # still lazy
    value = obj.deeply.nested.field[]     # now materialized
    ```
  - Why the changes:
    - The lazy support in JSON.jl is truly lazy and the underlying JSON is only parsed/navigated as explicitly requested. JSON3.jl still fully parsed the JSON into a fairly compact binary representation, avoiding full materialization of objects and arrays.

- Typed Parsing
  - What stayed the same:
    - Both allow parsing directly into custom types
    - Both support object mapping, handling nested types, unions with Nothing/Missing
  - What changed:
    - Interface: `StructTypes.StructType` becomes JSON.jl's StructUtils integration
    - Default values: `StructTypes.defaults` becomes `@defaults` macro
    - Type selection: Custom JSON3 dispatching becomes `JSON.@choosetype`
  - Migration examples:
    ```julia
    # JSON3.jl
    StructTypes.StructType(::Type{MyType}) = StructTypes.Struct()
    StructTypes.defaults(::Type{MyType}) = (field1=0, field2="default")
    
    # Type selection in JSON3.jl
    StructTypes.StructType(::Type{AbstractParent}) = StructTypes.AbstractType()
    StructTypes.subtypes(::Type{AbstractParent}) = (a=ConcreteA, b=ConcreteB)
    
    # JSON.jl 1.0
    @defaults struct MyType
        field1::Int = 0
        field2::String = "default"
    end
    
    # Type selection in JSON.jl 1.0
    JSON.@choosetype AbstractParent x -> x.type[] == "a" ? ConcreteA : ConcreteB
    ```

- Custom Field Mapping
  - What stayed the same:
    - Both support mapping between JSON property names and struct field names
    - Both handle date formatting and other special types
  - What changed:
    - Interface: JSON3.jl uses `StructTypes.names`, JSON.jl 1.0 uses field tags
    - Date handling: Different formats for specifying date formats
  - Migration examples:
    ```julia
    # JSON3.jl
    StructTypes.names(::Type{MyType}) = ((:json_name, :struct_field),)
    StructTypes.keywordargs(::Type{MyType}) = (date_field=(dateformat=dateformat"yyyy-mm-dd",),)
    
    # JSON.jl 1.0
    @tags struct MyType
        struct_field::Int &(json=(name="json_name",),)
        date_field::Date &(json=(dateformat="yyyy-mm-dd",),)
    end
    ```

### Features unique to each library

- Only in JSON3.jl:
  - **Struct Generation**: The ability to automatically generate Julia struct definitions from JSON examples
    ```julia
    # This functionality is not available in JSON.jl 1.0
    struct_def = JSON3.generate_struct(json_data, "MyStruct")
    ```
  - If you rely heavily on this feature, continue using JSON3.jl for this specific purpose until this functionality is migrated to a separate package

- Only in JSON.jl 1.0:
  - **Enhanced JSON Lines Support**: Better handling of JSON Lines format with auto-detection for files with `.jsonl` extension
  - **More Float Formatting Controls**: Additional options for float precision and format style
  - **Improved Circular Reference Handling**: Better detection and handling of circular references
