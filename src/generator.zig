const std = @import("std");
const File = std.fs.File;

/// Read 'in' as a JSON Schema
/// Write 'out' as a zig struct
/// base_allocator will be used as child allocator of arenas
pub fn model(base_allocator: std.mem.Allocator, in: File, out: File) !void {
    // Read and parse json
    const stat = try in.stat();
    const input_file_buffer = try base_allocator.alloc(u8, stat.size);
    defer base_allocator.free(input_file_buffer);
    _ = try in.readAll(input_file_buffer);

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        base_allocator,
        input_file_buffer,
        .{},
    );
    defer parsed.deinit();

    // Generate zig code
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var zig_source_buffer = try std.ArrayList(u8).initCapacity(allocator, 128_000);
    try zig_source_buffer.appendSlice(allocator, "pub const Schema = struct {");
    var iterator = parsed.value.object.get("properties").?.object.iterator();
    while (iterator.next()) |entry| {
        try walkEntry(&entry, allocator, &zig_source_buffer);
        try zig_source_buffer.append(allocator, ',');
    }
    try zig_source_buffer.appendSlice(allocator, "};");
    try zig_source_buffer.append(allocator, 0);
    const tree_input: []const u8 = zig_source_buffer.items;
    var tree = try std.zig.Ast.parse(allocator, tree_input[0 .. tree_input.len - 1 :0], .zig);
    const rendered_buffer = try tree.renderAlloc(allocator);
    try out.writeAll(rendered_buffer);
}

fn walkEntry(entry: *const std.json.ObjectMap.Entry, allocator: std.mem.Allocator, buffer: *std.ArrayList(u8)) !void {
    switch (entry.value_ptr.*) {
        .object => |value| {
            try buffer.appendSlice(allocator, entry.key_ptr.*);
            try buffer.append(allocator, ':');
            var iterator = value.iterator();
            while (iterator.next()) |sub_entry| {
                try walkEntry(&sub_entry, allocator, buffer);
            }
        },
        .string => |value| {
            if (std.mem.eql(u8, value, "string")) {
                try buffer.appendSlice(allocator, "[]const u8");
            } else if (std.mem.eql(u8, value, "integer")) try buffer.appendSlice(allocator, "u8");
        },
        else => {
            return error.UnsupportedToken;
        },
    }
}
