function serve(dispatcher, io::IO, serializer)
    @unpack deserialize, serialize = Serializer(serializer)
    @debug "Starting RPC connection"
    while isopen(io)
        request = deserialize(io)
        @debug "Received:" request
        request === nothing && break
        jsonrpc(dispatcher, serialize, io, request)
    end
    return io
end

function serve(dispatcher, server::IOServer, serializer)
    tasks = IdDict()
    try
        while isopen(server)
            @debug "Waiting for a client"
            sock = try
                accept(server)
            catch err
                @debug "accept(server)" exception=(err, catch_backtrace())
                if err isa IOError
                    break
                end
                rethrow()
            end
            @debug "Accepted a client"
            @async try
                tasks[current_task()] = sock
                serve(dispatcher, sock, serializer)
                pop!(tasks, current_task())
            catch err
                close(server)
                @debug "`serve` failed" exception=(err, catch_backtrace())
                rethrow()
            end
        end
    finally
        let tasks = copy(tasks)
            foreach(close, values(tasks))
            @sync for t in keys(tasks)
                @async wait(t)
            end
        end
    end
end

serve(dispatcher, listenable, serializer) =
    serve(dispatcher, listen(listenable), serializer)
