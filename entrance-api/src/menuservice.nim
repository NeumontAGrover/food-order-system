import std/asynchttpserver, std/httpclient, std/asyncdispatch

proc healthCheck*(req: Request, headers: HttpHeaders) {.async, gcsafe.} =
    let client = newAsyncHttpClient()

    if (req.reqMethod != HttpGet):
        await req.respond(Http405, "{\"message\":\"Invalid method\"}", headers)
        return

    try:
        let response = await client.getContent("http://menu-service:21991/healthcheck")
        await req.respond(Http200, response, headers)
    except:
        await req.respond(Http500, "{\"message\":\"Healthcheck failed\"}", headers)

proc getMenuItem*(req: Request, headers: HttpHeaders) {.async, gcsafe.} =
    if (req.reqMethod == HttpGet):
        await req.respond(Http405, "{\"message\":\"Invalid method\"}", headers)
        return
