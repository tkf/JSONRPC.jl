abstract type Serializer end
Serializer(serializer::NamedTuple) = StatelessSerializer(serializer)

struct StatelessSerializer
    serialize
    deserialize
end

StatelessSerializer(; serialize, deserialize) = StatelessSerializer(serialize, deserialize)

StatelessSerializer(serializer::NamedTuple) = StatelessSerializer(; serializer...)

trygetid(x::AbstractDict) = haskey(x, :id) ? x : get(x, "id", nothing)
trygetid(x::NamedTuple) = get(x, :id, nothing)
trygetid(x) =
    try
        try
            return x.id
        catch
        end
        return x[:id]
    catch
        return nothing
    end

function ignoringclosed(f, io, args...)
    try
        return f(io, args...)
    catch err
        err isa IOError && !isopen(io) && return
        rethrow()
    end
end

# https://en.wikipedia.org/wiki/JSON_streaming

function jsonparseln(io)
    line = readline(io)
    isempty(line) && return nothing
    @debug "jsonparseln" line
    return JSON.parse(line)
end

function jsonprintln(io, x)
    @debug "jsonprintln: Sending" x

    local line, err, backtrace
    try
        line = JSON.json(x)
        true
    catch err
        @error "`jsonprintln` failed to send serialize a message" exception = (
            err,
            catch_backtrace(),
        )
        backtrace = sprint(showerror, err, catch_backtrace())
        false
    end && begin
        ignoringclosed(println, io, line)
        return
    end

    # Failed to serialize. Try to respond as an error:
    id = trygetid(x)
    message = sprint(showerror, err)
    data = (backtrace = backtrace,)
    line = JSON.json(ErrorResponse(id, SerializationError, message, data))
    ignoringclosed(println, io, line)
    return
end

const NDJSON = (serialize = jsonprintln, deserialize = jsonparseln)

# probably doesn't work?
const Concatenated_JSON = (serialize = JSON.print, deserialize = JSON.parse)
