const std = @import("std");
const Allocator = std.mem.Allocator;
const Parsed = std.json.Parsed;
const Value = std.json.Value;
const expect = std.testing.expect;
const expectError = std.testing.expectError;
const File = std.fs.File;

/// Read 'in' as a JSON Schema
/// Write 'out' as a zig struct
/// base_allocator will be used as child allocator of arenas
pub fn model(base_allocator: Allocator, in: File, out: File) !void {
    // Read and parse json
    const parsed = try load(base_allocator, in, Value);
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

pub const FileParseError = File.ReadError || File.StatError || std.json.ParseError(std.json.Scanner);

fn load(base_allocator: Allocator, in: File, comptime T: type) FileParseError!Parsed(T) {
    const stat = try in.stat();
    const input_file_buffer = try base_allocator.alloc(u8, stat.size);
    _ = try in.readAll(input_file_buffer);
    defer base_allocator.free(input_file_buffer);

    return try std.json.parseFromSlice(
        T,
        base_allocator,
        input_file_buffer,
        .{},
    );
}

fn walkEntry(entry: *const std.json.ObjectMap.Entry, allocator: Allocator, buffer: *std.ArrayList(u8)) !void {
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

pub fn validator(base_allocator: Allocator, in: File, out: File) !void {
    _ = base_allocator;
    _ = in;
    _ = out;
}
pub const StringValidationError = error{
    MinimumLengthError,
    MaximumLengthError,
};

test "String too short" {
    const sv = String{ .min = 2 };
    try expectError(StringValidationError.MinimumLengthError, sv.validate("a"));
}

test "String too long" {
    const sv = String{ .max = 2 };
    try expectError(StringValidationError.MaximumLengthError, sv.validate("alif"));
}

test String {
    const sv = String{ .min = 2, .max = 4 };
    try sv.validate("alif");
}

/// pattern constraint is not supported for now
pub const String = struct {
    min: u8 = 0,
    max: usize = std.math.maxInt(usize),
    // TODO: accept a pattern

    pub fn validate(self: *const String, value: []const u8) StringValidationError!void {
        if (value.len < self.min) return StringValidationError.MinimumLengthError;
        if (value.len > self.max) return StringValidationError.MaximumLengthError;
    }
};

// TODO: and test it plz
pub const Number = struct {
    min: u8 = 0,
    max: u8 = 150,

    pub fn validate(self: *const String, value: []const u8) StringValidationError!void {
        // TODO: in a hurry
        _ = self;
        _ = value;
    }
};
