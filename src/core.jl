const JSONRPCID = Union{AbstractString, Integer}

@enum(
    ErrorCode,
    ParseError = -32700,
    InvalidRequest = -32600,
    MethodNotFound = -32601,
    InvalidParams = -32602,
    InternalError = -32603,
    # -32000 to -32099: Server error
    MethodException = -32001,
    SerializationError = -32002,
    UserError = -40000,
)

abstract type Response end

struct ResultResponse <: Response
    id::JSONRPCID
    result
    jsonrpc::Symbol
    ResultResponse(id, result) = new(id, result, Symbol("2.0"))
end

struct Error
    code::Int
    message::String
    data
end

Error(code::ErrorCode, message, data) = Error(Int(code), message, data)
Error(code, message) = Error(code, message, nothing)

usererror(message::AbstractString, data=nothing) =
    Error(UserError, message, data)

struct ErrorResponse <: Response
    id::Union{JSONRPCID, Nothing}
    error::Error
    jsonrpc::Symbol
    ErrorResponse(id, error) = new(id, error, Symbol("2.0"))
end

ErrorResponse(code::ErrorCode) =
    ErrorResponse(nothing, Error(code, string(code)))

ErrorResponse(id, code::ErrorCode) =
    ErrorResponse(id, Error(code, string(code)))

ErrorResponse(id, code::ErrorCode, message::String, data=nothing) =
    ErrorResponse(id, Error(code, message, data))

function jsonrpc(dispatcher, rf, acc, input::AbstractDict{String})
    @debug "jsonrpc" dispatcher rf acc input

    id = get(input, "id", nothing)
    if !(id isa String || id isa Int)
        id = nothing
    end
    @debug "`id` field is parsed" id
    if get(input, "jsonrpc", nothing) != "2.0"
        return rf(acc, ErrorResponse(id, InvalidRequest))
    end
    @debug "`jsonrpc` field is correct"

    fname = get(input, "method", nothing)
    if !(fname isa String)
        return rf(acc, ErrorResponse(id, InvalidRequest))
    end
    @debug "`method` field is correct"

    params = get(input, "params", nothing)
    if !(params isa Vector || params isa Dict || params isa Nothing)
        return rf(acc, ErrorResponse(id, InvalidRequest))
    end
    @debug "`params` field is correct"

    @debug "Request parsed" id fname params
    id === nothing && return acc  # notification
    @debug "Request is valid"

    f = get(dispatcher, fname, nothing)
    if f === nothing
        return rf(acc, ErrorResponse(id, MethodNotFound))
    end
    @debug "Method is found"

    result, success = try
        f(params), true
    catch err
        @debug "Failed" f params exception=(err, catch_backtrace())
        err, false
    end
    @debug "got" result success
    if success
        if result isa Exception
            return rf(acc, ErrorResponse(id, UserError, sprint(showerror, result)))
        elseif result isa Error
            return rf(acc, ErrorResponse(id, result))
        else
            return rf(acc, ResultResponse(id, result))
        end
    else
        return rf(acc, ErrorResponse(id, MethodException, sprint(showerror, result)))
    end
end

function jsonrpc(dispatcher, rf, acc, input::AbstractVector)
    isempty(input) && return rf(acc, ErrorResponse(InvalidRequest))
    results = foldl([], init=input) do acc, input
        jsonrpc(dispatcher, rf, acc, input)
    end
    isempty(results) && return acc  # notification
    return rf(acc, results)
end

jsonrpc(dispatcher, rf, acc, response::Response) = rf(acc, response)

jsonrpc(dispatcher, rf, acc, _) =
    rf(acc, ErrorResponse(InvalidRequest))
