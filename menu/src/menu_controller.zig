const std = @import("std");
const httpz = @import("httpz");
const MongoClient = @import("mongo.zig").MongoClient;
const FoodItem = @import("food_item.zig").FoodItem;
const FoodItemOptional = @import("food_item.zig").FoodItemOptional;
const Request = httpz.Request;
const Response = httpz.Response;

pub var client: *const MongoClient = undefined;

pub fn getMenuItem(req: *Request, res: *Response) !void {
    res.status = 200;

    const id = req.param("id");
    if (id == null or id.?.len == 0) res.status = 400;

    status: switch (res.status) {
        200 => {
            const collection = try client.getCollection("menu");
            defer client.destroyCollection(collection);

            const food_item = client.getDocumentById(collection, id.?) catch |err| {
                res.status = switch (err) {
                    error.DocumentNotFound => 404,
                    else => 500,
                };
                continue :status res.status;
            };
            defer food_item.deinit();
            try res.json(food_item.value, .{});
        },
        400 => try res.json(.{ .message = "No ID has been supplied" }, .{}),
        404 => try res.json(.{ .message = "Document not found" }, .{}),
        else => {
            res.status = 500;
            try res.json(.{ .message = "An error occurred" }, .{});
        },
    }
}

pub fn getAllMenuItems(req: *Request, res: *Response) !void {
    res.status = 200;

    const request_body = if (req.body() != null) req.body().? else &.{};

    status: switch (res.status) {
        200 => {
            const collection = try client.getCollection("menu");
            defer client.destroyCollection(collection);

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const allocator = arena.allocator();

            const docs = client.getDocuments(collection, request_body) catch |err| {
                res.status = switch (err) {
                    error.InvalidQuery => 400,
                    else => 500,
                };
                continue :status res.status;
            };
            defer {
                for (docs) |doc| doc.deinit();
                allocator.free(docs);
            }

            var doc_list = try std.array_list.Aligned(FoodItem, null).initCapacity(allocator, docs.len);
            defer doc_list.deinit(allocator);
            for (docs) |doc|
                doc_list.append(allocator, doc.value) catch @panic("Out of memory");

            try res.json(doc_list.items, .{});
        },
        400 => try res.json(.{ .message = "There was a problem parsing the query" }, .{}),
        else => {
            res.status = 500;
            try res.json(.{ .message = "An error occurred" }, .{});
        },
    }
}

pub fn createMenuItem(req: *Request, res: *Response) !void {
    res.status = 200;

    const request_body = req.body();
    if (request_body == null or request_body.?.len == 0) res.status = 204;

    status: switch (res.status) {
        200 => {
            const collection = try client.getCollection("menu");
            defer client.destroyCollection(collection);

            client.insertDocument(collection, request_body.?) catch |err| {
                res.status = switch (err) {
                    error.InvalidDataFormat => 400,
                    error.InsertDocumentFailed => 417,
                    else => 500,
                };
                continue :status res.status;
            };
            try res.json(.{ .message = "Created the menu item" }, .{});
        },
        204 => try res.json(.{ .message = "There is no body present" }, .{}),
        400 => try res.json(.{ .message = "There was a problem parsing the body" }, .{}),
        417 => try res.json(.{ .message = "Could not insert document" }, .{}),
        else => {
            res.status = 500;
            try res.json(.{ .message = "An error occurred" }, .{});
        },
    }
}

pub fn updateMenuItem(req: *Request, res: *Response) !void {
    res.status = 200;

    const id = req.param("id");
    if (id == null or id.?.len == 0) res.status = 400;

    const request_body = req.body();
    if (request_body == null or request_body.?.len == 0) res.status = 204;

    status: switch (res.status) {
        200 => {
            const collection = try client.getCollection("menu");
            defer client.destroyCollection(collection);

            client.updateDocument(collection, id.?, request_body.?) catch |err| {
                res.status = switch (err) {
                    error.InvalidDataFormat => 400,
                    error.UpdateDocumentFailed => 417,
                    else => 500,
                };
                continue :status res.status;
            };
        },
        204 => try res.json(.{ .message = "There is no body present" }, .{}),
        400 => try res.json(.{ .message = "There was a problem parsing the body" }, .{}),
        417 => try res.json(.{ .message = "Could not insert document" }, .{}),
        else => {
            res.status = 500;
            try res.json(.{ .message = "An error occurred" }, .{});
        },
    }
}

pub fn deleteMenuItem(req: *Request, res: *Response) !void {
    res.status = 200;

    const id = req.param("id");
    if (id == null or id.?.len == 0) res.status = 400;

    status: switch (res.status) {
        200 => {
            const collection = try client.getCollection("menu");
            defer client.destroyCollection(collection);

            client.deleteDocumentById(collection, id.?) catch |err| {
                res.status = switch (err) {
                    error.DocumentNotFound => 404,
                    else => 500,
                };
                continue :status res.status;
            };
            try res.json(.{ .message = "Deleted the menu item" }, .{});
        },
        400 => try res.json(.{ .message = "No ID has been supplied" }, .{}),
        404 => try res.json(.{ .message = "Document not found" }, .{}),
        else => {
            res.status = 500;
            try res.json(.{ .message = "An error occurred" }, .{});
        },
    }
}
