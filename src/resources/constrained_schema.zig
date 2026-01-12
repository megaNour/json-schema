const validator = @import("../validator.zig");

pub const Schema = struct {
    name: validator.String = validator.String{
        .min = 3,
        .max = 24,
    },
    age: u8 = validator.Number{
        .min = 18,
        .max = 123,
    },
};
