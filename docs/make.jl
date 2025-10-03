using Documenter, JSON

makedocs(modules = [JSON], sitename = "JSON.jl")

deploydocs(repo = "github.com/JuliaIO/JSON.jl.git", push_preview = true)
