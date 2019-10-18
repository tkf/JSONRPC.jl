using JSONRPC
using Logging: current_logger, with_logger
using Sockets
using Test
using Test: TestLogger

struct NonSerializable end

function start_test_server(server, serializer)
    dispatcher = Dict(
        "add1" => ((x,),) -> x + 1,
        "nonserializable" => _ -> NonSerializable(),
    )
    @async JSONRPC.serve(dispatcher, server, serializer)
end

function with_test_server(f, serializer = JSONRPC.NDJSON)
    mktempdir() do dir
        listenable = joinpath(dir, "jsonrpc.socket")
        server = listen(listenable)
        logger = TestLogger()
        # logger = current_logger()
        with_logger(logger) do
            task = start_test_server(server, serializer)
            try
                f(listenable, serializer, logger)
            finally
                close(server)
                wait(task)
            end
        end
    end
end

function waittrue(f)
    for _ in 1:100
        f() && return true
        sleep(0.01)
    end
    return false
end

@testset begin
    with_test_server() do listenable, serializer, logger
        io = connect(listenable)
        client = JSONRPC.client(io, serializer)

        @test client.add1(2) == 3

        err = nothing
        @test try
            client.add1(nothing)
        catch err
            err
        end isa JSONRPC.Error
        @test err.code == Int(JSONRPC.MethodException)

        @testset "serialization error on server" begin
            err = nothing
            @test try
                Some(client.nonserializable())
            catch err
                err
            end isa JSONRPC.Error
            @test err.code == Int(JSONRPC.SerializationError)
            @test client.add1(2) == 3  # recoverable
        end

        #=
        @testset "serialization error on client" begin
            write(io, """{"broken": "json"]\n""")
            @test client.add1(2) == 3  # recoverable
        end
        =#

        serializer.serialize(io, Dict("broken" => "request"))
        if logger isa TestLogger
            @test waittrue() do
                any(l.message == "Response with unknown ID" for l in logger.logs)
            end
        else
            @info "It's OK to see `Error: Response with unknown ID` here."
            sleep(0.1)
        end

        @test client.add1(2) == 3  # broken request is recoverable
    end
end

@testset "sending response to closed connection (`jsonprintln`)" begin
    with_test_server()  do listenable, serializer, logger
        io = connect(listenable)
        client = JSONRPC.client(io, serializer)

        # Make sure it's working
        @test client.add1(2) == 3

        # Test that trying to send response to closed connection does
        # not throw:
        serializer.serialize(io, Dict("broken" => "request"))
        if logger isa TestLogger
            @test waittrue() do
                any(l.message == "Response with unknown ID" for l in logger.logs)
            end
        else
            @info "It's OK to see `Error: Response with unknown ID` here."
            sleep(0.1)
        end
    end
end
