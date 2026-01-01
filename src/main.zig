const std = @import("std");
const ObjectMap = std.json.ObjectMap;
const json_schema = @import("json_schema");
var indent_lvl: u8 = 0;
const space_buffer = [_]u8{' '} ** 256;
pub fn main() !void {
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.heap.page_allocator,
        @embedFile("resources/simple_schema.json"),
        .{},
    );
    std.debug.print("pub const Schema = struct {{\n", .{});
    var iterator = parsed.value.object.get("properties").?.object.iterator();
    while (iterator.next()) |entry| {
        walkEntry(&entry);
        std.debug.print(",\n", .{});
    }
    std.debug.print("}}\n", .{});
}

pub fn walkEntry(entry: *const ObjectMap.Entry) void {
    indent_lvl += 1;
    switch (entry.value_ptr.*) {
        .object => |value| {
            std.debug.print("{s}{s}: ", .{ space_buffer[0 .. indent_lvl * 4], entry.key_ptr.* });
            var iterator = value.iterator();
            while (iterator.next()) |sub_entry| {
                walkEntry(&sub_entry);
            }
        },
        .string => |value| {
            if (std.mem.eql(u8, value, "string")) {
                std.debug.print("[]const u8", .{});
            } else if (std.mem.eql(u8, value, "integer")) std.debug.print("u8", .{});
        },
        else => {
            std.debug.panic("cannot handle type: {}\n", .{entry.value_ptr.*});
        },
    }
    indent_lvl -= 1;
}
