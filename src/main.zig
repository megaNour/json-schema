const std = @import("std");
const ObjectMap = std.json.ObjectMap;
const ArgIterator = std.process.ArgIterator;
const File = std.fs.File;

const jump = @import("jump");
const model = @import("json_schema").model;
const validator = @import("json_schema").validator;

const Mode = enum { model, validator };

pub fn main() !void {
    var stderr_buffer: [64]u8 = undefined;
    var stderr_writer = File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    const args_iterator = try std.process.argsWithAllocator(std.heap.page_allocator);
    var pos_jumper = jump.OverPosLean(ArgIterator).init(args_iterator);
    _ = pos_jumper.next(); // discard arg 0

    const mode_arg = pos_jumper.next() orelse {
        // TODO: print help if no positional arg
        std.process.exit(0);
    };

    const mode = blk: {
        if (std.mem.eql(u8, mode_arg, "model")) {
            break :blk Mode.model;
        } else if (std.mem.eql(u8, mode_arg, "validator")) {
            break :blk Mode.validator;
        } else {
            try stderr.writeAll("unknown mode. TODO: print help :-)\n");
            try stderr.flush();
            std.process.exit(1);
        }
    };

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

    switch (mode) {
        .model => try model(std.heap.page_allocator, in, out),
        .validator => try validator(std.heap.page_allocator, in, out),
    }
}
