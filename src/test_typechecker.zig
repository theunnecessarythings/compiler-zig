const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const parser = @import("parser.zig");
const diagnostics = @import("diagnostics.zig");
const SourceManager = diagnostics.SourceManager;
const ast = @import("ast.zig");
const TypeChecker = @import("typechecker.zig").TypeChecker;

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    const out = try file.readToEndAlloc(allocator, comptime std.math.maxInt(usize));
    return out;
}

fn typecheck(source_file: []const u8) !void {
    const allocator = std.heap.page_allocator;
    var source_manager = SourceManager.init(allocator);
    var context = try parser.Context.init(allocator, &source_manager);
    const file_id = try context.source_manager.registerSourcePath(source_file);
    const source_content = try readFile(allocator, source_file);
    var tokenizer = Tokenizer.init(allocator, source_content, file_id);
    var source_parser = try parser.Parser.init(allocator, &context, &tokenizer);
    const compilation_unit = source_parser.parseCompilationUnit() catch |err| {
        std.debug.print("Failed to parse source file '{s}': {any}\n", .{ source_file, err });
        return err;
    };
    const type_checker = try TypeChecker.init(allocator, &context);
    return type_checker.checkCompilationUnit(compilation_unit);
}

test "check_all_examples" {
    const allocator = std.heap.page_allocator;
    const dir = try std.fs.cwd().openDir("examples", .{ .iterate = true });
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) {
            continue;
        }
        const filepath = try dir.realpathAlloc(allocator, entry.path);
        try typecheck(filepath);
    }
}
