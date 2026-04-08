const std = @import("std");

pub const FoodItem = struct {
    name: []const u8,
    price: f32,
    description: []const u8,
    ingredients: [][]const u8,
};

pub const FoodItemOptional = struct {
    name: ?[]const u8 = null,
    price: ?f32 = null,
    description: ?[]const u8 = null,
    ingredients: ?[][]const u8 = null,
};

pub const FoodItemNode = struct {
    node: std.SinglyLinkedList.Node = .{},
    food_item: std.json.Parsed(FoodItem),
};
