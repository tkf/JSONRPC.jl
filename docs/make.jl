using Documenter, JSONRPC

makedocs(;
    modules=[JSONRPC],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/tkf/JSONRPC.jl/blob/{commit}{path}#L{line}",
    sitename="JSONRPC.jl",
    authors="Takafumi Arakaki <aka.tkf@gmail.com>",
    assets=String[],
)

deploydocs(;
    repo="github.com/tkf/JSONRPC.jl",
)
