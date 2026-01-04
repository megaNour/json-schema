const std = @import("std");
const ObjectMap = std.json.ObjectMap;
const ArgIterator = std.process.ArgIterator;
const File = std.fs.File;

const generateZigCode = @import("json_schema").generateZigCode;
const jump = @import("jump");

pub fn main() !void {
    var stderr_buffer: [64]u8 = undefined;
    var stderr_writer = File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    const args_iterator = try std.process.argsWithAllocator(std.heap.page_allocator);
    var pos_jumper = jump.OverPosLean(ArgIterator).init(args_iterator);
    _ = pos_jumper.next();

    const in = try std.fs.cwd().openFile(pos_jumper.next() orelse {
        try stderr.writeAll("no input file provided. TODO: print help :-)\n");
        try stderr.flush();
        std.process.exit(1);
    }, .{ .mode = .read_only });
    defer in.close();

    const out = try std.fs.cwd().createFile(pos_jumper.next() orelse {
        try stderr.writeAll("no output file provided. TODO: print help :-)\n");
        try stderr.flush();
        std.process.exit(1);
    }, .{});
    defer out.close();

    try generateZigCode(std.heap.page_allocator, in, out);
}
