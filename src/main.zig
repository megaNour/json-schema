const std = @import("std");
const ObjectMap = std.json.ObjectMap;
const ArgIterator = std.process.ArgIterator;

const json_schema = @import("json_schema");
const jump = @import("jump");

var indent_lvl: u8 = 0;

const ArgError = error{ InputFileMissing, OutputFileMissing };
const ParsingError = error{UnsupportedToken};

pub fn main() !void {
    var stderr_buffer: [64]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    const args_iterator = try std.process.argsWithAllocator(std.heap.page_allocator);
    var pos_jumper = jump.OverPosLean(ArgIterator).init(args_iterator);
    _ = pos_jumper.next();

    // Args parsing
    const input_file = try std.fs.cwd().openFile(pos_jumper.next() orelse {
        try stderr.writeAll("no input file provided. TODO: print help :-)\n");
        try stderr.flush();
        std.process.exit(0);
    }, .{ .mode = .read_only });
    defer input_file.close();

    const output_file = try std.fs.cwd().createFile(pos_jumper.next() orelse {
        try stderr.writeAll("no output file provided. TODO: print help :-)\n");
        try stderr.flush();
        std.process.exit(0);
    }, .{});
    defer output_file.close();

    const stat = try input_file.stat();
    const input_file_buffer = try std.heap.page_allocator.alloc(u8, stat.size);
    defer std.heap.page_allocator.free(input_file_buffer);
    _ = try input_file.readAll(input_file_buffer);

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.heap.page_allocator, // will be wrapped in an arena anyway
        input_file_buffer,
        .{},
    );
    defer parsed.deinit();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var zig_source_buffer = try std.ArrayList(u8).initCapacity(allocator, 128_000);
    try zig_source_buffer.appendSlice(allocator, "pub const Schema = struct {");
    var iterator = parsed.value.object.get("properties").?.object.iterator();
    while (iterator.next()) |entry| {
        try walkEntry(&entry, allocator, &zig_source_buffer);
        try zig_source_buffer.appendSlice(allocator, ",");
    }
    try zig_source_buffer.appendSlice(allocator, "};");
    try zig_source_buffer.append(allocator, 0);
    const tree_input: []const u8 = zig_source_buffer.items;
    var tree = try std.zig.Ast.parse(allocator, tree_input[0 .. tree_input.len - 1 :0], .zig);
    defer tree.deinit(allocator);
    const rendered_buffer = try tree.renderAlloc(allocator);
    try output_file.writeAll(rendered_buffer);
}

pub fn walkEntry(entry: *const ObjectMap.Entry, allocator: std.mem.Allocator, buffer: *std.ArrayList(u8)) !void {
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

fn get_file_arg(pos_jumper: jump.OverPosLean(ArgIterator), stderr: std.fs.File.Writer) ?[]const u8 {
    if (pos_jumper.next()) |opt| {
        return opt;
    } else |err| {
        switch (err) {
            jump.LocalParsingError.MissingValue => {
                try stderr.print("{any}, hint: {s}", .{ err, pos_jumper.diag.debug_hint });
            },
            jump.LocalParsingError.ForbiddenValue => unreachable,
        }
    }
}
