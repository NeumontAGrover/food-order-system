import std/asynchttpserver, std/asyncdispatch, std/httpclient
import menuservice

proc request(req: Request) {.async.} =
    const headers = {"Content-Type": "application/json"}
    let http_headers = headers.newHttpHeaders()
    let path = req.url.path

    case path:
        of "/healthcheck":
            await req.respond(Http404, "{\"message\": \"Service is healthy\"}", http_headers)
        of "/menu/healthcheck":
            await menuservice.healthCheck(req, http_headers)
        else:
            await req.respond(Http404, "{\"message\": \"Invalid path\"}", http_headers)

proc main {.async.} =
    let server = newAsyncHttpServer()
    server.listen(Port(3000))

    while true:
        if (server.shouldAcceptRequest()):
            await server.acceptRequest(request)
        else:
            server.close()
            break


waitFor main()
