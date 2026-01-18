const std = @import("std");
const Scanner = std.json.Scanner;
const eql = std.mem.eql;
const validator = @import("validator.zig");
pub const Person = struct {
    name: validator.String = .{ .min = 3, .max = 24 },
    name_seen: bool = false,
    age: validator.Integer = .{ .min = 0, .max = 200 },
    age_seen: bool = false,
    unknown: validator.Extra = .{ .allow = true },

    pub fn validate(self: *const Person, scanner: *Scanner) !void {
        blk: while (scanner.next()) |token| {
            switch (token) {
                .object_begin => continue,
                .array_begin => continue,
                .object_end => break :blk,
                .string => |val| {
                    if (eql(u8, val, "name")) {
                        try self.name.validate(scanner);
                    } else if (eql(u8, val, "age")) {
                        try self.age.validate(scanner);
                    } else {
                        try self.unknown.validate();
                    }
                },
                else => {
                    return error.UnexpectedToken;
                },
            }
        } else |err| {
            return err;
        }
    }
};

test "validator" {
    const person = Person{};
    var scanner = std.json.Scanner.initCompleteInput(
        std.heap.page_allocator,
        "{\"age\": 25, \"name\": \"nour\", \"myExtra\": \"maybeAllowed\"} ",
    );
    try person.validate(&scanner);
}
