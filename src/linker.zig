const std = @import("std");
const llvm = @import("llvm/llvm-zig.zig");
const llvm_core = llvm.core;

pub const ExternalLinker = struct {
    allocator: std.mem.Allocator,
    potential_linker_names: std.ArrayList([]const u8),
    linker_flags: std.ArrayList([]const u8),
    current_linker_name: []const u8,

    const Self = ExternalLinker;

    pub fn init(allocator: std.mem.Allocator) ExternalLinker {
        var potential_linker_names = std.ArrayList([]const u8).init(allocator);
        potential_linker_names.append("gcc") catch unreachable;
        potential_linker_names.append("clang") catch unreachable;

        var linker_flags = std.ArrayList([]const u8).init(allocator);
        linker_flags.append("-no-pie") catch unreachable;
        linker_flags.append("-flto") catch unreachable;
        linker_flags.append("-lm") catch unreachable;

        return ExternalLinker{
            .allocator = allocator,
            .potential_linker_names = potential_linker_names,
            .linker_flags = linker_flags,
            .current_linker_name = potential_linker_names.items[0],
        };
    }

    pub fn link(self: *Self, object_file_path: []const u8) !i64 {
        var linker_command_builder = std.ArrayList([]const u8).init(self.allocator);
        try linker_command_builder.append(self.current_linker_name);

        try linker_command_builder.append(object_file_path);
        for (self.linker_flags.items) |flag| {
            try linker_command_builder.append(flag);
        }

        try linker_command_builder.append("-o");
        try linker_command_builder.append(object_file_path[0 .. object_file_path.len - 2]);

        const result = std.ChildProcess.run(.{
            .allocator = self.allocator,
            .argv = linker_command_builder.items,
        }) catch |err| {
            std.debug.print("Failed to run linker: {any}\n", .{err});
            return err;
        };

        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }
        if (result.stdout.len != 0) {
            std.debug.print("{s}\n", .{result.stdout});
        }
        if (result.stderr.len != 0) {
            std.debug.print("{s}\n", .{result.stderr});
            std.process.exit(1);
        }

        return 0;
    }

    pub fn checkAvailableLinker(self: *Self) bool {
        for (self.potential_linker_names.items) |linker_name| {
            _ = findProgramByName(self.allocator, linker_name) catch return false;
            self.current_linker_name = linker_name;
            return true;
        }
        return false;
    }

    fn findProgramByName(allocator: std.mem.Allocator, program_name: []const u8) ![]const u8 {
        const result = try std.ChildProcess.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "which", program_name },
        });

        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }
        var iter = std.mem.split(u8, result.stdout, " ");
        return iter.next().?;
    }
};
