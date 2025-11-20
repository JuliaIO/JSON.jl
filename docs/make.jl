using Documenter, JSON

makedocs(
    modules = [JSON],
    sitename = "JSON.jl",
    pages = [
        "Home" => "index.md",
        "JSON Writing" => "writing.md",
        "JSON Reading" => "reading.md",
        "Migration Guides" => "migrate.md",
        "API Reference" => "reference.md",
    ],
)

deploydocs(repo = "github.com/JuliaIO/JSON.jl.git", push_preview = true)
