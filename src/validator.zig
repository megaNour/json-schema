const std = @import("std");
const eql = std.mem.eql;
const Scanner = std.json.Scanner;
const NextError = Scanner.NextError;
const Value = std.json.Value;
const expect = std.testing.expect;
const expectError = std.testing.expectError;

pub const IntegerValidationError = error{
    WrongValueType,
    MinimumValue,
    MaximumValue,
} || Scanner.NextError || std.fmt.ParseIntError;

pub const StringValidationError = error{
    WrongValueType,
    MinimumLength,
    MaximumLength,
} || Scanner.NextError;

pub const String = struct {
    min: u8 = 0,
    max: usize = std.math.maxInt(usize),

    pub fn validate(self: *const String, scanner: *Scanner) StringValidationError!void {
        if (scanner.next()) |val| {
            switch (val) {
                .string => |v| {
                    if (v.len < self.min) return StringValidationError.MinimumLength;
                    if (v.len > self.max) return StringValidationError.MaximumLength;
                },
                else => return error.WrongValueType,
            }
        } else |err| return err;
    }
};

pub const Integer = struct {
    min: u8 = 13,
    max: u8 = 25,

    pub fn validate(self: *const Integer, scanner: *Scanner) IntegerValidationError!void {
        if (scanner.next()) |val| {
            switch (val) {
                .number => |v| {
                    const int = try std.fmt.parseInt(i64, v.ptr[0..v.len], 10);
                    if (int < self.min) return IntegerValidationError.MinimumValue;
                    if (int > self.max) return IntegerValidationError.MaximumValue;
                },
                else => return error.WrongValueType,
            }
        } else |err| return err;
    }
};

pub const Extra = struct {
    allow: bool = true,

    pub fn validate(self: *const Extra) error{ExtraElementNotAllowed}!void {
        if (self.allow == false) {
            return error.ExtraElementNotAllowed;
        }
    }
};

fn setupScannerFor(scanner: *Scanner, input: []const u8) !void {
    scanner.* = std.json.Scanner.initCompleteInput(
        std.testing.allocator,
        input,
    );
    _ = try scanner.next(); // discard opening
    _ = try scanner.next(); // discard key
}

test "String validation" {
    const string_validator = String{ .max = 12, .min = 4 };

    var scanner = try std.testing.allocator.create(Scanner);
    defer std.testing.allocator.destroy(scanner);

    try setupScannerFor(scanner, "{\"name\": \"nour\"}");
    try string_validator.validate(scanner); // happy
    scanner.deinit();

    try setupScannerFor(scanner, "{\"name\": \"nournour\"}");
    try string_validator.validate(scanner); // happy
    scanner.deinit();

    try setupScannerFor(scanner, "{\"name\": \"nournournour\"}");
    try string_validator.validate(scanner); // happy
    scanner.deinit();

    try setupScannerFor(scanner, "{\"name\": \"nou\"}");
    try expectError(StringValidationError.MinimumLength, string_validator.validate(scanner));
    scanner.deinit();

    try setupScannerFor(scanner, "{\"name\": \"nournournourN\"}");
    try expectError(StringValidationError.MaximumLength, string_validator.validate(scanner));
    scanner.deinit();
}

test "Integer validation" {
    const interger_validator = Integer{ .max = 25, .min = 18 };

    var scanner = try std.testing.allocator.create(Scanner);
    defer std.testing.allocator.destroy(scanner);

    try setupScannerFor(scanner, "{\"age\": 18}");
    try interger_validator.validate(scanner); // happy
    scanner.deinit();

    try setupScannerFor(scanner, "{\"age\": 20}");
    try interger_validator.validate(scanner); // happy
    scanner.deinit();

    try setupScannerFor(scanner, "{\"age\": 25}");
    try interger_validator.validate(scanner); // happy
    scanner.deinit();

    try setupScannerFor(scanner, "{\"age\": 17}");
    try expectError(IntegerValidationError.MinimumValue, interger_validator.validate(scanner));
    scanner.deinit();

    try setupScannerFor(scanner, "{\"age\": 26}");
    try expectError(IntegerValidationError.MaximumValue, interger_validator.validate(scanner));
    scanner.deinit();
}

test "Extra validation" {
    var extra_validator = Extra{};

    try extra_validator.validate(); // happy

    extra_validator = Extra{ .allow = false };
    try expectError(error.ExtraElementNotAllowed, extra_validator.validate());
}
