const std = @import("std");
const httpz = @import("httpz");
const MenuController = @import("menu_controller.zig");
const MongoClient = @import("mongo.zig").MongoClient;
const Request = httpz.Request;
const Response = httpz.Response;

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();
    const mongo = try MongoClient.init(
        allocator,
        "menudb",
        "mongodb://menudb:27017",
    );
    MenuController.client = &mongo;

    const port = 21991;
    var server = try httpz.Server(void).init(
        init.io,
        allocator,
        .{ .address = .all(21991) },
        {},
    );
    defer {
        server.stop();
        server.deinit();
    }

    var router = try server.router(.{});
    router.get("/menu/:id", MenuController.getMenuItem, .{});
    router.get("/menu", MenuController.getAllMenuItems, .{});
    router.post("/menu", MenuController.createMenuItem, .{});
    router.put("/menu/:id", MenuController.updateMenuItem, .{});
    router.delete("/menu/:id", MenuController.deleteMenuItem, .{});
    router.get("/menu/healthcheck", healthCheck, .{});

    std.log.info("The service is running on http://menu-service:{}", .{port});
    try server.listen();
}

fn healthCheck(req: *Request, res: *Response) !void {
    _ = req;
    res.status = 200;
    try res.json(.{ .message = "The service is healthy" }, .{});
}
