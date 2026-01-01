const std = @import("std");
const ObjectMap = std.json.ObjectMap;
const json_schema = @import("json_schema");

pub fn main() !void {
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.heap.page_allocator,
        @embedFile("resources/simple_schema.json"),
        .{},
    );
    std.debug.print("pub const MySchema = struct {{\n", .{});
    var iterator = parsed.value.object.get("properties").?.object.iterator();
    while (iterator.next()) |entry| {
        walkEntry(&entry);
        std.debug.print(",\n", .{});
    }
    std.debug.print("}}\n", .{});
}

pub fn walkEntry(entry: *const ObjectMap.Entry) void {
    switch (entry.value_ptr.*) {
        .object => |value| {
            var iterator = value.iterator();
            while (iterator.next()) |sub_entry| {
                std.debug.print("\"{s}\"", .{sub_entry.key_ptr.*});
                walkEntry(&sub_entry);
            }
        },
        .string => |value| {
            std.debug.print("\"{s}\"", .{value});
        },
        else => {
            std.debug.panic("cannot handle type: {}", .{entry.value_ptr.*});
        },
    }
}
