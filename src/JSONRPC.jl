module JSONRPC

import JSON
using Base: IOServer, IOError
using Parameters: @unpack
using Sockets: accept, connect, listen

include("core.jl")
include("serializers.jl")
include("server.jl")
include("client.jl")

end # module
