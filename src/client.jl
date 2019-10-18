struct Request
    method::String
    params
end

_put!(future, value) = put!(future, value)
_put!(::Nothing, _) = nothing

struct Call
    request::Request
    future::Channel{Any}
end

Call(request::Request) = Call(request, Channel(1))

function takesome!(x)
    try
        return Some(take!(x))
    catch err
        err isa InvalidStateException && return nothing
        rethrow()
    end
end

function launch_client(io, chan, serializer)
    @unpack deserialize, serialize = Serializer(serializer)

    pending = Dict{UInt, WeakRef}()

    function onexit()
        try
            @debug "launch_client (onexit)"
            close(io)
            close(chan)
            for ref in collect(values(pending))
                future = ref.value
                future === nothing && continue
                @debug "onexit: Closing" future
                close(future)
            end
        catch err
            @error "launch_client (onexit)" exception=(err, catch_backtrace())
        end
    end

    @sync begin
        @async try
            id = UInt(0)
            while isopen(io)
                maybecall = takesome!(chan)
                maybecall === nothing && break
                call = something(maybecall)
                request = (
                    method = call.request.method,
                    params = call.request.params,
                    id = id,
                    jsonrpc = Symbol("2.0"),
                )
                serialize(io, request)
                pending[id] = WeakRef(call.future)
                let id = id
                    finalizer(call.future) do _
                        pop!(pending, id, nothing)
                    end
                end
                id += 1
            end
        catch err
            @error "launch_client (request handler)" exception=(err, catch_backtrace())
            rethrow()
        finally
            onexit()
        end
        @async try
            while isopen(io)
                raw = deserialize(io)
                raw === nothing && break
                response = Response(raw)
                @debug "Response" response
                ref = pop!(pending, response.id, nothing)
                if ref === nothing
                    @error "Response with unknown ID" response
                    continue
                end
                future = ref.value
                if response isa ResultResponse
                    _put!(future, response.result)
                elseif response isa ErrorResponse
                    _put!(future, response.error)
                else
                    @error "Invalid response type" response
                end
            end
        catch err
            @error "launch_client (response handler)" exception=(err, catch_backtrace())
            rethrow()
        finally
            onexit()
        end
    end
end

struct FieldAccessor{T}
    value::T
end
fieldsof(value) = FieldAccessor(value)
Base.getproperty(accessor::FieldAccessor, name::Symbol) =
    getfield(getfield(accessor, :value), name)

struct Client
    io::IO
    task::Task
    channel::Channel{Call}
end

function Base.close(client::Client)
    c = fieldsof(client)
    close(c.io)
    wait(c.task)
end

Base.isopen(client::Client) = isopen(fieldsof(client).io)

client(listenable, serializer) = client(connect(listenable)::IO, serializer)
function client(io::IO, serializer)
    chan = Channel{Call}(0)
    return Client(
        io,
        (@async launch_client(io, chan, serializer)),
        chan
    )
end

async_request(client::Client, method, params) =
    async_request(client, Request(method, params))

function async_request(client::Client, request::Request)
    call = Call(request)
    put!(fieldsof(client).channel, call)
    return call.future
end

Base.getproperty(client::Client, name::Symbol) =
    MethodProxy(client, String(name))
Base.getproperty(client::Client, name::AbstractString) =
    MethodProxy(client, String(name))

function request(client::Client, request::Request)
    result = fetch(async_request(client, request))
    if result isa Error
        throw(result)
    end
    return result
end
# Is it beter to close the "future" (really a Channel) after `fetch`?
# Will GC take care of it?

request(client::Client, method::AbstractString, params) =
    request(client, Request(method, params))

struct MethodProxy
    client::Client
    method::String
end

(proxy::MethodProxy)(param1, params...) =
    request(proxy.client, proxy.method, collect((param1, params...)))

(proxy::MethodProxy)(; params...) =
    if isempty(params)
        request(proxy.client, proxy.method, nothing)
    else
        request(proxy.client, proxy.method, Dict{Symbol,Any}(params))
    end

function Response(response::AbstractDict{String})
    result = get(response, "result", nothing)
    if result !== nothing
        id = get(response, "id", typemax(UInt))  # TODO: handle not found
        return ResultResponse(id, result)
    end

    result = get(response, "error", nothing)
    if result !== nothing
        id = get(response, "id", nothing)
        return ErrorResponse(id, Error(result))
    end

    throw(ArgumentError("Invalid response\n:$response"))
end

function Error(result::AbstractDict{String})
    code = get(result, "code", typemax(Int))
    message = get(result, "message", "")
    data = get(result, "data", nothing)
    return Error(code, message, data)
end
