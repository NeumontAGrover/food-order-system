import std/asynchttpserver, std/asyncdispatch, std/httpclient, std/strutils, std/streams
import nim_amqp
import menuservice

proc request(req: Request) {.async.} =
    const headers = {"Content-Type": "application/json"}
    let httpHeaders = headers.newHttpHeaders()
    let pathList = req.url.path.split("/")

    if (pathList.len < 2):
        await req.respond(Http404, "{\"message\": \"Invalid path\"}", httpHeaders)

    if (pathList[1] == "healthcheck"):
        await req.respond(Http404, "{\"message\": \"Service is healthy\"}", httpHeaders)
    elif (pathList[1] == "menu"):
        if (pathList.len < 3):
            await req.respond(Http404, "{\"message\": \"Invalid path\"}", httpHeaders)

        if (pathList[2] == "healthcheck"):
            await menuservice.healthCheck(req, httpHeaders)
        
        if (not pathList[2].isEmptyOrWhitespace):
            await menuservice.getMenuItem(req, httpHeaders, pathList[2])
        else:
            await req.respond(Http404, "{\"message\": \"Invalid ID for menu item\"}", httpHeaders)
    else:
        await req.respond(Http404, "{\"message\": \"Invalid path\"}", httpHeaders)

proc testLavinMQ() =
    let channel = connect("lavinmq", "guest", "guest", "/", 5672).createChannel()
    proc handleMessage(chan: AMQPChannel, message: ContentData) =
        echo message.body.readAll()
        channel.acknowledgeMessage(0)

    channel.registerMessageHandler(handleMessage)
    channel.startAsyncConsumer()


proc main {.async.} =
    testLavinMQ()

    let server = newAsyncHttpServer()
    server.listen(Port(3000))

    while true:
        if (server.shouldAcceptRequest()):
            await server.acceptRequest(request)
        else:
            server.close()
            break


waitFor main()
