const std = @import("std");
const Parsed = std.json.Parsed;
const mongoc = @import("mongoc");
const FoodItem = @import("food_item.zig").FoodItem;
const FoodItemNode = @import("food_item.zig").FoodItemNode;

pub const MongoError = error{
    ConnectionFailed,
    CollectionNotFound,
    InvalidDataFormat,
    InvalidQuery,
    InsertDocumentFailed,
    UpdateDocumentFailed,
    DeleteDocumentFailed,
    DocumentNotFound,
};

pub const MongoClient = struct {
    allocator: std.mem.Allocator,
    client: *mongoc.mongoc_client_t,
    db_name: [*c]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, db: [*c]const u8, connection_string: [*c]const u8) MongoError!Self {
        mongoc.mongoc_init();
        const client = mongoc.mongoc_client_new(connection_string);
        if (client == null) return MongoError.ConnectionFailed;

        return .{
            .allocator = allocator,
            .client = client.?,
            .db_name = db,
        };
    }

    pub fn deinit(self: Self) void {
        mongoc.mongoc_client_destroy(self.client);
        mongoc.mongoc_cleanup();
    }

    pub fn getCollection(self: Self, collection_name: [*c]const u8) MongoError!*mongoc.mongoc_collection_t {
        const collection = mongoc.mongoc_client_get_collection(
            self.client,
            self.db_name,
            collection_name,
        );
        if (collection == null) return MongoError.CollectionNotFound;

        return collection.?;
    }

    pub fn destroyCollection(_: Self, collection: *mongoc.mongoc_collection_t) void {
        mongoc.mongoc_collection_destroy(collection);
    }

    pub fn getDocumentById(self: Self, collection: *mongoc.mongoc_collection_t, id: []const u8) MongoError!Parsed(FoodItem) {
        const id_string: [:0]u8 = std.mem.concatWithSentinel(self.allocator, u8, &.{id}, 0) catch
            @panic("Out of memory");
        defer self.allocator.free(id_string);

        var oid: mongoc.bson_oid_t = undefined;
        mongoc.bson_oid_init_from_string(&oid, id_string);

        const query = mongoc.bson_new();
        defer mongoc.bson_destroy(query);
        _ = mongoc.BSON_APPEND_OID(query, "_id", &oid);

        const options = bsonOptionsWithoutId();
        defer mongoc.bson_destroy(options.options);
        defer mongoc.bson_destroy(options.projection);

        const cursor = mongoc.mongoc_collection_find_with_opts(
            collection,
            query,
            options.options,
            null,
        );
        defer mongoc.mongoc_cursor_destroy(cursor);

        var doc: [*c]const mongoc.bson_t = undefined;
        if (!mongoc.mongoc_cursor_next(cursor, &doc))
            return MongoError.DocumentNotFound;

        const json_c = mongoc.bson_as_relaxed_extended_json(doc, null);
        defer mongoc.bson_free(json_c);

        const json: []const u8 = std.mem.span(json_c);
        return std.json.parseFromSlice(
            FoodItem,
            self.allocator,
            json,
            .{ .allocate = .alloc_always },
        ) catch return MongoError.InvalidDataFormat;
    }

    pub fn getDocuments(self: Self, collection: *mongoc.mongoc_collection_t, query: []const u8) MongoError![]Parsed(FoodItem) {
        const query_len: isize = if (query.len > 0) @intCast(query.len) else 2;
        const query_string: [:0]const u8 = if (query.len > 0)
            std.mem.concatWithSentinel(self.allocator, u8, &.{query}, 0) catch @panic("Out of memory")
        else
            std.fmt.allocPrintSentinel(self.allocator, "{{}}", .{}, 0) catch @panic("Out of memory");
        defer self.allocator.free(query_string);

        const mongo_query = mongoc.bson_new_from_json(query_string, @intCast(query_len), null);
        defer mongoc.bson_destroy(mongo_query);

        const options = bsonOptionsWithoutId();
        defer mongoc.bson_destroy(options.options);
        defer mongoc.bson_destroy(options.projection);

        const cursor = mongoc.mongoc_collection_find_with_opts(
            collection,
            mongo_query,
            options.options,
            null,
        );
        defer mongoc.mongoc_cursor_destroy(cursor);

        var food_item_list: std.SinglyLinkedList = .{};
        errdefer {
            var node = food_item_list.first;
            while (node) |n| {
                const item: *FoodItemNode = @alignCast(@fieldParentPtr("node", n));
                node = n.next;
                item.food_item.deinit();
                self.allocator.destroy(item);
            }
        }

        var doc: [*c]const mongoc.bson_t = undefined;
        var doc_amount: u32 = 0;
        while (mongoc.mongoc_cursor_next(cursor, &doc)) : (doc_amount += 1) {
            const json_c = mongoc.bson_as_relaxed_extended_json(doc, null);
            defer mongoc.bson_free(json_c);

            const json: []const u8 = std.mem.span(json_c);
            const food_item: Parsed(FoodItem) = std.json.parseFromSlice(
                FoodItem,
                self.allocator,
                json,
                .{ .allocate = .alloc_always },
            ) catch return MongoError.InvalidDataFormat;

            var node = self.allocator.create(FoodItemNode) catch @panic("Out of memory");
            node.food_item = food_item;
            food_item_list.prepend(&node.node);
        }

        if (food_item_list.first == null) return &.{};

        const food_items = self.allocator.alloc(Parsed(FoodItem), doc_amount) catch @panic("Out of Memory");
        var node: *FoodItemNode = @alignCast(@fieldParentPtr("node", food_item_list.first.?));
        for (0..food_items.len) |i| {
            food_items[i] = node.food_item;
            if (node.node.next) |next|
                node = @alignCast(@fieldParentPtr("node", next));
        }

        return food_items;
    }

    pub fn insertDocument(self: Self, collection: *mongoc.mongoc_collection_t, data: []const u8) MongoError![]const u8 {
        const valid_data = std.json.validate(self.allocator, data) catch @panic("Out of memory");
        if (!valid_data) return MongoError.InvalidDataFormat;

        const data_string: [:0]u8 = std.mem.concatWithSentinel(self.allocator, u8, &.{data}, 0) catch
            @panic("Out of memory");
        defer self.allocator.free(data_string);

        const doc = mongoc.bson_new_from_json(data_string, @intCast(data.len), null);
        defer mongoc.bson_destroy(doc);

        var err: mongoc.bson_error_t = undefined;
        var reply: mongoc.bson_t = undefined;
        defer mongoc.bson_destroy(&reply);
        const success = mongoc.mongoc_collection_insert_one(collection, doc, null, &reply, &err);
        if (!success) {
            std.log.err("Could not insert document:\n{s}", .{err.message});
            return MongoError.InsertDocumentFailed;
        }

        const json_c = mongoc.bson_as_relaxed_extended_json(&reply, null);
        defer mongoc.bson_free(json_c);
        std.debug.print("{s}\n", .{json_c});
        const json_str: []const u8 = std.mem.span(json_c);
        return std.fmt.allocPrint(self.allocator, "{s}", .{json_str[50..74]}) catch {
            @panic("Out of memory");
        };
        // It's a little bit scuffed, but it always works
    }

    pub fn updateDocument(self: Self, collection: *mongoc.mongoc_collection_t, id: []const u8, data: []const u8) MongoError!void {
        const valid_data = std.json.validate(self.allocator, data) catch @panic("Out of memory");
        if (!valid_data) return MongoError.InvalidDataFormat;

        const id_string: [:0]u8 = std.mem.concatWithSentinel(self.allocator, u8, &.{id}, 0) catch
            @panic("Out of memory");
        defer self.allocator.free(id_string);

        const data_string: [:0]u8 = std.mem.concatWithSentinel(self.allocator, u8, &.{data}, 0) catch
            @panic("Out of memory");
        defer self.allocator.free(data_string);

        var oid: mongoc.bson_oid_t = undefined;
        mongoc.bson_oid_init_from_string(&oid, id_string);

        const query = mongoc.bson_new();
        defer mongoc.bson_destroy(query);
        _ = mongoc.BSON_APPEND_OID(query, "_id", &oid);

        const update = mongoc.bson_new();
        defer mongoc.bson_destroy(update);

        const update_set = mongoc.bson_new_from_json(data_string, @intCast(data.len), null);
        defer mongoc.bson_destroy(update_set);

        _ = mongoc.bson_append_document(update, "$set", 4, update_set);

        const doc = mongoc.bson_new_from_json(data_string, @intCast(data.len), null);
        defer mongoc.bson_destroy(doc);

        const success = mongoc.mongoc_collection_update_one(
            collection,
            query,
            update,
            null,
            null,
            null,
        );
        if (!success) return MongoError.UpdateDocumentFailed;
    }

    pub fn deleteDocumentByQuery(self: Self, collection: *mongoc.mongoc_collection_t, query_json: []const u8) MongoError!void {
        const query_string: [:0]u8 = std.mem.concatWithSentinel(self.allocator, u8, &.{query_json}, 0) catch
            @panic("Out of memory");
        defer self.allocator.free(query_string);

        const query = mongoc.bson_new_from_json(query_string, @intCast(query_string.len), null);
        defer mongoc.bson_destroy(query);

        const success = mongoc.mongoc_collection_delete_one(collection, query, null, null, null);
        if (!success) return MongoError.DeleteDocumentFailed;
    }

    pub fn deleteDocumentById(self: Self, collection: *mongoc.mongoc_collection_t, id: []const u8) MongoError!void {
        const id_string: [:0]u8 = std.mem.concatWithSentinel(self.allocator, u8, &.{id}, 0) catch
            @panic("Out of memory");
        defer self.allocator.free(id_string);

        var oid: mongoc.bson_oid_t = undefined;
        mongoc.bson_oid_init_from_string(&oid, id_string);

        const query = mongoc.bson_new();
        defer mongoc.bson_destroy(query);
        _ = mongoc.BSON_APPEND_OID(query, "_id", &oid);

        const cursor = mongoc.mongoc_collection_find_with_opts(collection, query, null, null);
        defer mongoc.mongoc_cursor_destroy(cursor);
        var doc: [*c]const mongoc.bson_t = undefined;
        if (!mongoc.mongoc_cursor_next(cursor, &doc))
            return MongoError.DocumentNotFound;

        const success = mongoc.mongoc_collection_delete_one(collection, query, null, null, null);
        if (!success) return MongoError.DeleteDocumentFailed;
    }

    fn bsonOptionsWithoutId() struct { options: [*c]mongoc.bson_t, projection: [*c]mongoc.bson_t } {
        const options = mongoc.bson_new();

        const projection = mongoc.bson_new();
        _ = mongoc.bson_append_bool(projection, "_id", 3, false);
        _ = mongoc.bson_append_bool(projection, "name", 4, true);
        _ = mongoc.bson_append_bool(projection, "price", 5, true);
        _ = mongoc.bson_append_bool(projection, "description", 11, true);
        _ = mongoc.bson_append_bool(projection, "ingredients", 11, true);

        _ = mongoc.bson_append_document(options, "projection", 10, projection);

        return .{
            .options = options,
            .projection = projection,
        };
    }
};
