const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Parser = @import("parser.zig").Parser;
const Context = @import("parser.zig").Context;
const Compiler = @import("compiler.zig").Compiler;
const SourceManager = @import("diagnostics.zig").SourceManager;
const codegen = @import("generate_code.zig");

pub fn main() !void {
    const dir = try std.fs.cwd().openDir("examples", .{ .iterate = true });
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) {
            continue;
        }
        const file_path = try dir.realpathAlloc(allocator, entry.path);

        std.debug.print("Loading full path {s} \n", .{file_path});

        const source_manager = try allocator.create(SourceManager);
        source_manager.* = SourceManager.init(allocator);

        const context = try allocator.create(Context);
        context.* = try Context.init(allocator, source_manager);

        const compiler = try allocator.create(Compiler);
        compiler.* = Compiler.init(allocator, context);

        // compiler.emitLLVMIR(file_path);
        compiler.compileSourceCode(file_path);

        // compiler.checkSourceCode(file_path);

        // const compilation_unit = compiler.parseSouceCode(file_path);
        // for (compilation_unit.tree_nodes.items) |node| {
        //     std.debug.print("{any}", .{node});
        // }
        // codegen.generateCodeFromAst(allocator, compilation_unit);
    }

    const source_manager = try allocator.create(SourceManager);
    source_manager.* = SourceManager.init(allocator);
    const context = try allocator.create(Context);
    const file_path: []const u8 = "/home/sreeraj/Documents/amun-zig/examples/structs/_struct_store_fun_ptr_field.la";
    context.* = try Context.init(allocator, source_manager);

    const compiler = try allocator.create(Compiler);
    compiler.* = Compiler.init(allocator, context);

    // const compilation_unit = compiler.parseSouceCode(file_path);
    //
    // codegen.generateCodeFromAst(allocator, compilation_unit);

    // compiler.checkSourceCode(file_path);

    // compiler.emitLLVMIR(file_path);
    compiler.compileSourceCode(file_path);
}
