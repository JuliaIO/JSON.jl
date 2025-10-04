using Documenter, JSON

makedocs(modules = [JSON], sitename = "JSON.jl", checkdocs_ignored_modules = [JSON.Ryu])

deploydocs(repo = "github.com/JuliaIO/JSON.jl.git", push_preview = true)
