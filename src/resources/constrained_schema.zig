const validator = @import("../validator.zig");
pub const Schema = struct {
    name: validator.String = .{
        .min = 3,
        .max = 24,
    },
    age: validator.Integer = .{
        .min = 18,
        .max = 123,
    },
};
