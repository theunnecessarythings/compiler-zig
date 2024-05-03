const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Parser = @import("parser.zig").Parser;
const Context = @import("parser.zig").Context;
const Compiler = @import("compiler.zig").Compiler;
const SourceManager = @import("diagnostics.zig").SourceManager;
const codegen = @import("generate_code.zig");
const LogOptions = @import("diagnostics.zig").LogOptions;

fn runCmd(allocator: std.mem.Allocator, file_path: []const u8, cmd: []const u8) !void {
    if (!std.mem.containsAtLeast(u8, file_path, 1, ".la")) {
        const dir = try std.fs.cwd().openDir(file_path, .{ .iterate = true });
        var walker = try dir.walk(allocator);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            if (entry.kind != .file) {
                continue;
            }
            const filepath = try dir.realpathAlloc(allocator, entry.path);
            try runCmd(allocator, filepath, cmd);
        }
        return;
    } else {
        std.debug.print("Running command \x1b[34m\x1b[1m{s}\x1b[0m on file `{s}` \n", .{ cmd, file_path });
        const source_manager = try allocator.create(SourceManager);
        source_manager.* = SourceManager.init(allocator);
        const context = try allocator.create(Context);
        context.* = try Context.init(allocator, source_manager);
        const compiler = try allocator.create(Compiler);
        compiler.* = Compiler.init(allocator, context);

        if (std.mem.eql(u8, cmd, "check")) {
            compiler.checkSourceCode(file_path);
        } else if (std.mem.eql(u8, cmd, "compile")) {
            try compiler.compileSourceCode(file_path);
        } else if (std.mem.eql(u8, cmd, "emit-ir")) {
            compiler.emitLLVMIR(file_path);
        } else if (std.mem.eql(u8, cmd, "generate-code")) {
            const compilation_unit = compiler.parseSouceCode(file_path, false);
            codegen.generateCodeFromAst(allocator, compilation_unit);
        } else if (std.mem.eql(u8, cmd, "gen-ast")) {
            _ = compiler.parseSouceCode(file_path, true);
        } else {
            std.debug.print("Invalid command {s} \n", .{cmd});
        }
    }
}

fn setLogTypes(types: []const u8) void {
    var types_ = std.mem.split(u8, types, ",");
    while (types_.next()) |type_| {
        if (std.mem.eql(u8, "p", type_)) {
            LogOptions.enable_parser_logging = true;
        } else if (std.mem.eql(u8, "l", type_)) {
            LogOptions.enable_tokenizer_logging = true;
        } else if (std.mem.eql(u8, "c", type_)) {
            LogOptions.enable_codegen_logging = true;
        } else if (std.mem.eql(u8, "t", type_)) {
            LogOptions.enable_typechecker_logging = true;
        } else if (std.mem.eql(u8, "g", type_)) {
            LogOptions.enable_general_logging = true;
        }
    }
}

pub fn main() !void {
    const dir = try std.fs.cwd().openDir("examples", .{ .iterate = true });
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var arg_iter = try std.process.argsWithAllocator(allocator);
    defer arg_iter.deinit();
    _ = arg_iter.next();
    const command = arg_iter.next();
    const file_path = arg_iter.next();
    const log_types = arg_iter.next();

    if (log_types) |types| {
        setLogTypes(types);
    }

    if (command == null or file_path == null) {
        std.debug.print("Usage: ./compiler <command> <file_path> \n", .{});
        std.process.exit(1);
    }

    const start = try std.time.Instant.now();

    if (command) |cmd| {
        if (std.mem.eql(u8, cmd, "check")) {
            try runCmd(allocator, file_path.?, "check");
        } else if (std.mem.eql(u8, cmd, "compile")) {
            try runCmd(allocator, file_path.?, "compile");
        } else if (std.mem.eql(u8, cmd, "emit-ir")) {
            try runCmd(allocator, file_path.?, "emit-ir");
        } else if (std.mem.eql(u8, cmd, "generate-code")) {
            try runCmd(allocator, file_path.?, "generate-code");
        } else if (std.mem.eql(u8, cmd, "gen-ast")) {
            try runCmd(allocator, file_path.?, "gen-ast");
        } else {
            std.debug.print("Invalid command {s} \n", .{cmd});
            std.process.exit(1);
        }
    }

    const end = try std.time.Instant.now();
    const elapsed = end.since(start);

    std.debug.print("Time taken: {d} ms \n", .{elapsed / 1000_000});
    // std.debug.print("Memory usage: {d} bytes \n", .{arena.queryCapacity()});
}
