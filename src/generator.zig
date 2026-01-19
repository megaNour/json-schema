const std = @import("std");
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;
const Parsed = std.json.Parsed;
const Value = std.json.Value;
const Scanner = std.json.Scanner;
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
        try walkModelEntry(&entry, allocator, &zig_source_buffer);
        try zig_source_buffer.append(allocator, ',');
    }
    try zig_source_buffer.appendSlice(allocator, "};");
    try zig_source_buffer.append(allocator, 0);
    const tree_input: []const u8 = zig_source_buffer.items;
    var tree = try std.zig.Ast.parse(allocator, tree_input[0 .. tree_input.len - 1 :0], .zig);
    std.debug.print("{s}\n\n", .{tree_input});
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

fn walkModelEntry(entry: *const std.json.ObjectMap.Entry, allocator: Allocator, buffer: *std.ArrayList(u8)) !void {
    switch (entry.value_ptr.*) {
        .object => |value| {
            try buffer.appendSlice(allocator, entry.key_ptr.*);
            try buffer.append(allocator, ':');
            var iterator = value.iterator();
            while (iterator.next()) |sub_entry| {
                try walkModelEntry(&sub_entry, allocator, buffer);
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

pub const SchemaParsingError = error{ InvalidSchema, Unsupported };

pub fn validator(base_allocator: Allocator, in: File, out: File) !void {
    // Init a scanner
    var scanner: Scanner = undefined;
    const input_file_buffer = try initScanner(base_allocator, in, &scanner);
    defer base_allocator.free(input_file_buffer);
    defer scanner.deinit();

    // Generate zig code
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var zig_source_buffer = try std.ArrayList(u8).initCapacity(allocator, 128_000);
    try zig_source_buffer.appendSlice(allocator, "const validator = @import(\"../validator.zig\");pub const Schema = struct {");

    try walkStream(allocator, &zig_source_buffer, &scanner);
    try zig_source_buffer.appendSlice(allocator, "};");
    try zig_source_buffer.append(allocator, 0);

    const tree_input: []const u8 = zig_source_buffer.items;
    var tree = try std.zig.Ast.parse(allocator, tree_input[0 .. tree_input.len - 1 :0], .zig);
    const rendered_buffer = try tree.renderAlloc(allocator);
    try out.writeAll(rendered_buffer);
}

fn initScanner(base_allocator: Allocator, in: File, scanner_ptr: *Scanner) FileParseError![]const u8 {
    const stat = try in.stat();
    const input_file_buffer = try base_allocator.alloc(u8, stat.size);
    _ = try in.readAll(input_file_buffer);
    // defer base_allocator.free(input_file_buffer);

    scanner_ptr.* = std.json.Scanner.initCompleteInput(
        base_allocator,
        input_file_buffer,
    );
    return input_file_buffer;
}

const State = enum {
    start,
    schema_key,
    schema_value,
    property_name,
    property_object_key,
    property_object_value,
    end,
};

const Property = struct {
    type: ?[]const u8 = undefined,
    min: ?[]const u8 = undefined,
    max: ?[]const u8 = undefined,
};

fn walkStream(allocator: Allocator, zig_source_buffer: *std.ArrayList(u8), scanner: *Scanner) !void {
    var state: State = .start;
    var prop = Property{};
    while (scanner.next()) |token| {
        std.debug.print("{any}: {any}\n", .{ state, token });
        switch (state) {
            .start => switch (token) {
                .object_begin => state = .schema_key,
                .true => continue,
                .object_end => state = .end,
                else => return error.UnexpectedToken,
            },
            .end => switch (token) {
                .end_of_document => break,
                else => return error.UnexpectedToken,
            },
            .schema_key => switch (token) {
                .string => |key| {
                    if (eql(u8, key, "title")) {
                        try zig_source_buffer.appendSlice(allocator, "const title = \"");
                        state = .schema_value;
                    } else if (eql(u8, key, "properties")) state = .property_name;
                },
                .array_end, .object_end => state = .end,
                .end_of_document => break,
                else => return error.UnexpectedToken,
            },
            .schema_value => switch (token) {
                .string => |value| {
                    try zig_source_buffer.appendSlice(allocator, value);
                    try zig_source_buffer.appendSlice(allocator, "\";");
                    state = .schema_key;
                },
                else => return error.UnexpectedToken,
            },
            .property_name => switch (token) {
                .object_begin => continue,
                .string => |val| {
                    try zig_source_buffer.appendSlice(allocator, "const prop_");
                    try zig_source_buffer.appendSlice(allocator, val);
                    try zig_source_buffer.appendSlice(allocator, ": ");
                    state = .property_object_key;
                },
                .object_end => state = .schema_key,
                else => return error.UnexpectedToken,
            },
            .property_object_key => switch (token) {
                .object_begin => continue,
                .string => |value| {
                    if (eql(u8, value, "type")) switch (try scanner.next()) {
                        .string => |val| prop.type = val,
                        else => return error.UnexpectedToken,
                    } else if (eql(u8, value, "maxLength") or eql(u8, value, "maximum")) switch (try scanner.next()) {
                        .number => |val| prop.max = val,
                        else => return error.UnexpectedToken,
                    } else if (eql(u8, value, "minLength") or eql(u8, value, "minimum")) switch (try scanner.next()) {
                        .number => |val| prop.min = val,
                        else => return error.UnexpectedToken,
                    } else return error.UnexpectedToken;
                },
                .object_end => {
                    // TODO: serialize the validator call
                    try zig_source_buffer.appendSlice(allocator, "ToBeDetermined = .{};");
                    state = .property_name;
                },
                else => return error.UnexpectedToken,
            },
            .property_object_value => {
                // will be usefull for complex values like arrays of accepted values
                return error.YouShouldNotReachHereForNow;
            },
        }
    } else |nextErr| {
        return nextErr;
    }
}

// fn walkSchemaEntryDropped(allocator: Allocator, zig_source_buffer: *std.ArrayList(u8), value: *const Value) !void {
//     switch (value.*) {
//         .object => |obj| {
//             if (obj.get("type")) |json_type_value| {
//                 switch (json_type_value) {
//                     .string => |jtype| {
//                         if (std.mem.eql(u8, jtype, "object")) {
//                             std.debug.print("{s} has {any} properties.\n", .{ obj.get("type").?.string, obj.unmanaged });
//                             if (obj.get("properties")) |properties| {
//                                 switch (properties) {
//                                     .object => |o| {
//                                         var iterator = o.iterator();
//                                         while (iterator.next()) |entry| {
//                                             try zig_source_buffer.appendSlice(allocator, entry.key_ptr.*);
//                                             try zig_source_buffer.appendSlice(allocator, ": ");
//                                             try walkSchemaEntryDropped(allocator, zig_source_buffer, entry.value_ptr);
//                                         }
//                                     },
//                                     else => return SchemaParsingError.InvalidSchema,
//                                 }
//                             }
//                         } else if (std.mem.eql(u8, jtype, "string")) {
//                             try zig_source_buffer.appendSlice(allocator, "validator.String = .{");
//                             if (obj.get("minLength")) |min| {
//                                 switch (min) {
//                                     .integer => |val| {
//                                         try zig_source_buffer.appendSlice(allocator, ".min = ");
//                                         var buf: [20]u8 = undefined;
//                                         const str = try std.fmt.bufPrint(&buf, "{d},", .{val});
//                                         try zig_source_buffer.appendSlice(allocator, str);
//                                     },
//                                     else => return SchemaParsingError.InvalidSchema,
//                                 }
//                             }
//                             if (obj.get("maxLength")) |max| {
//                                 switch (max) {
//                                     .integer => |val| {
//                                         try zig_source_buffer.appendSlice(allocator, ".max = ");
//                                         var buf: [20]u8 = undefined;
//                                         const str = try std.fmt.bufPrint(&buf, "{d},", .{val});
//                                         try zig_source_buffer.appendSlice(allocator, str);
//                                     },
//                                     else => return SchemaParsingError.InvalidSchema,
//                                 }
//                             }
//                             try zig_source_buffer.appendSlice(allocator, "},");
//                         } else if (std.mem.eql(u8, jtype, "integer")) {
//                             try zig_source_buffer.appendSlice(allocator, "validator.Integer = .{");
//                             if (obj.get("minimum")) |min| {
//                                 switch (min) {
//                                     .integer => |val| {
//                                         try zig_source_buffer.appendSlice(allocator, ".min = ");
//                                         var buf: [20]u8 = undefined;
//                                         const str = try std.fmt.bufPrint(&buf, "{d},", .{val});
//                                         try zig_source_buffer.appendSlice(allocator, str);
//                                     },
//                                     else => return SchemaParsingError.InvalidSchema,
//                                 }
//                             }
//                             if (obj.get("maximum")) |max| {
//                                 switch (max) {
//                                     .integer => |val| {
//                                         try zig_source_buffer.appendSlice(allocator, ".max = ");
//                                         var buf: [20]u8 = undefined;
//                                         const str = try std.fmt.bufPrint(&buf, "{d},", .{val});
//                                         try zig_source_buffer.appendSlice(allocator, str);
//                                     },
//                                     else => return SchemaParsingError.InvalidSchema,
//                                 }
//                             }
//                             try zig_source_buffer.appendSlice(allocator, "},");
//                         }
//                     },
//                     else => return SchemaParsingError.InvalidSchema,
//                 }
//             }
//         },
//         .bool => |b| {
//             if (!b) return SchemaParsingError.InvalidSchema; // `true` is a valid schema unlike `false`
//         },
//         else => return SchemaParsingError.InvalidSchema,
//     }
// }
