const std = @import("std");
const parser = @import("parser.zig");
const Parser = parser.Parser;
const Context = parser.Context;
const ast = @import("ast.zig");
const CompilationUnit = ast.CompilationUnit;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const TypeChecker = @import("typechecker.zig").TypeChecker;
const backend = @import("llvm_backend.zig");
const llvm = @import("llvm/llvm-zig.zig");
const llvm_core = llvm.core;
const linker = @import("linker.zig");

const c = @cImport({
    @cInclude("llvm-c/Core.h");
    @cInclude("llvm-c/Target.h");
    @cInclude("llvm-c/TargetMachine.h");
});

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    context: *Context,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, context: *Context) Self {
        return Self{
            .allocator = allocator,
            .context = context,
        };
    }

    pub fn parseSouceCode(self: *Self, source_file: []const u8, gen_ast: bool) *CompilationUnit {
        const file_id = self.context.source_manager.registerSourcePath(source_file) catch {
            std.debug.print("Failed to register source file '{s}'\n", .{source_file});
            return std.process.exit(1);
        };
        const source_content = self.readFile(source_file);
        const tokenizer = self.allocator.create(Tokenizer) catch unreachable;
        tokenizer.* = Tokenizer.init(self.allocator, source_content, file_id);
        var source_parser = Parser.init(self.allocator, self.context, tokenizer) catch {
            std.debug.print("Failed to create parser for source file '{s}'\n", .{source_file});
            return std.process.exit(1);
        };
        const compilation_unit = source_parser.parseCompilationUnit() catch |err| {
            std.debug.print("Failed to parse source file '{s}', Error: {any}\n", .{ source_file, err });
            self.context.diagnostics.reportDiagnostics(.Error);
            return std.process.exit(1);
        };
        if (self.context.diagnostics.levelCount(.Error) > 0) {
            self.context.diagnostics.reportDiagnostics(.Error);
            std.process.exit(1);
        }

        if (gen_ast) {
            self.generateAstJson(compilation_unit);
        }

        return compilation_unit;
    }

    pub fn generateAstJson(self: *const Self, compilation_unit: *const CompilationUnit) void {
        const out = std.json.fmt(
            compilation_unit.tree_nodes.items,
            .{ .whitespace = .indent_2 },
        );
        const json_string = std.fmt.allocPrint(self.allocator, "{any}\n", .{out}) catch |err| {
            std.debug.print("Failed to format AST to JSON: {any}\n", .{err});
            std.process.exit(1);
        };
        const file = std.fs.cwd().createFile(
            "ast.json",
            .{ .read = true },
        ) catch |err| {
            std.debug.print("Failed to create file: {any}\n", .{err});
            std.process.exit(1);
        };
        defer file.close();

        _ = file.writeAll(json_string) catch |err| {
            std.debug.print("Failed to write to file: {any}\n", .{err});
            std.process.exit(1);
        };
    }

    pub fn checkSourceCode(self: *Self, source_file: []const u8) void {
        const compilation_unit = self.parseSouceCode(source_file, false);

        var type_checker = TypeChecker.init(self.allocator, self.context) catch {
            std.debug.print("Failed to create type checker for source file '{s}'\n", .{source_file});
            std.process.exit(1);
        };
        _ = type_checker.checkCompilationUnit(compilation_unit) catch |err| {
            std.debug.print("Failed to type check source file '{s}'\n", .{source_file});
            std.debug.print("Typechecker Error: {any}\n", .{err});
        };

        if (self.context.options.should_report_warns and self.context.diagnostics.levelCount(.Warning) > 0) {
            self.context.diagnostics.reportDiagnostics(.Warning);
        }

        if (self.context.diagnostics.levelCount(.Error) > 0) {
            self.context.diagnostics.reportDiagnostics(.Error);
            // std.process.exit(1);
            return;
        }

        if (self.context.options.convert_warns_to_errors and self.context.diagnostics.levelCount(.Warning) > 0) {
            std.process.exit(1);
        }

        std.debug.print("Source code '{s}' is valid\n", .{source_file});
    }

    pub fn emitLLVMIR(self: *Self, source_file: []const u8) void {
        const compilation_unit = self.parseSouceCode(source_file, false);

        var type_checker = TypeChecker.init(self.allocator, self.context) catch {
            std.debug.print("Failed to create type checker for source file '{s}'\n", .{source_file});
            std.process.exit(1);
        };

        _ = type_checker.checkCompilationUnit(compilation_unit) catch |err| {
            std.debug.print("Failed to type check source file '{s}'\n", .{source_file});
            std.debug.print("Typechecker Error: {any}\n", .{err});
        };

        self.generateAstJson(compilation_unit);

        if (self.context.options.should_report_warns and self.context.diagnostics.levelCount(.Warning) > 0) {
            self.context.diagnostics.reportDiagnostics(.Warning);
        }

        if (self.context.diagnostics.levelCount(.Error) > 0) {
            self.context.diagnostics.reportDiagnostics(.Error);
            std.process.exit(1);
        }

        if (self.context.options.convert_warns_to_errors and self.context.diagnostics.levelCount(.Warning) > 0) {
            std.process.exit(1);
        }

        var llvm_backend = backend.LLVMBackend.init(self.allocator) catch {
            std.debug.print("Failed to create LLVM Backend\n", .{});
            std.process.exit(1);
        };
        const llvm_ir_module = llvm_backend.compile(source_file, compilation_unit) catch |err| {
            std.debug.print("Failed to compile source file '{s}'\n", .{source_file});
            std.debug.print("LLVM Backend Error: {any}\n", .{err});
            std.process.exit(1);
        };

        const file_name = std.fmt.allocPrint(self.allocator, "{s}.ll", .{self.context.options.output_file_name}) catch unreachable;
        const ir_file_name = self.allocator.dupeZ(u8, file_name) catch unreachable;

        const err_message: [*c][*c]u8 = undefined;
        const err = llvm_core.LLVMPrintModuleToFile(llvm_ir_module, ir_file_name, err_message);
        if (err == 1) {
            std.debug.print("Failed to write LLVM IR to file '{s}'\n", .{ir_file_name});
            std.process.exit(1);
        }
    }

    pub fn compileSourceCode(self: *Self, source_file: []const u8) !void {
        var external_linker = linker.ExternalLinker.init(self.allocator);
        if (self.context.options.linker_extra_flags.items.len > 0) {
            for (self.context.options.linker_extra_flags.items) |flag| {
                external_linker.linker_flags.append(flag) catch unreachable;
            }
        }
        if (!external_linker.checkAvailableLinker()) {
            std.debug.print("No available linker found. Please install one of these options\n", .{});
            for (external_linker.potential_linker_names.items) |linker_option| {
                std.debug.print("  {s}\n", .{linker_option});
            }
            std.process.exit(1);
        }

        const compilation_unit = self.parseSouceCode(source_file, false);

        var typechecker = TypeChecker.init(self.allocator, self.context) catch {
            std.debug.print("Failed to create type checker for source file '{s}'\n", .{source_file});
            std.process.exit(1);
        };

        _ = typechecker.checkCompilationUnit(compilation_unit) catch |err| {
            std.debug.print("Failed to type check source file '{s}'\n", .{source_file});
            std.debug.print("Typechecker Error: {any}\n", .{err});
        };

        if (self.context.options.should_report_warns and self.context.diagnostics.levelCount(.Warning) > 0) {
            self.context.diagnostics.reportDiagnostics(.Warning);
        }

        if (self.context.diagnostics.levelCount(.Error) > 0) {
            self.context.diagnostics.reportDiagnostics(.Error);
            std.process.exit(1);
        }

        if (self.context.options.convert_warns_to_errors and self.context.diagnostics.levelCount(.Warning) > 0) {
            std.process.exit(1);
        }

        var llvm_backend = backend.LLVMBackend.init(self.allocator) catch {
            std.debug.print("Failed to create LLVM Backend\n", .{});
            std.process.exit(1);
        };

        const llvm_ir_module = llvm_backend.compile(source_file, compilation_unit) catch |err| {
            std.debug.print("Failed to compile source file '{s}'\n", .{source_file});
            std.debug.print("LLVM Backend Error: {any}\n", .{err});
            std.process.exit(1);
        };

        if (llvm_core.LLVMGetNamedFunction(llvm_ir_module, "main") == null) {
            std.debug.print("No 'main' function found in source file '{s}'\n", .{source_file});
            // std.process.exit(1);
            return;
        }
        _ = c.LLVMInitializeNativeTarget();
        _ = c.LLVMInitializeNativeAsmParser();
        _ = c.LLVMInitializeNativeAsmPrinter();

        const object_file_path = self.allocator.dupeZ(u8, std.fmt.allocPrint(self.allocator, "{s}.o", .{self.context.options.output_file_name}) catch unreachable) catch unreachable;

        const target_triple = llvm.target_machine.LLVMGetDefaultTargetTriple();
        var target: llvm.types.LLVMTargetRef = undefined;
        var error_message: [*c]u8 = undefined;
        const err = llvm.target_machine.LLVMGetTargetFromTriple(target_triple, &target, &error_message);
        if (err != 0) {
            std.debug.print("Failed to get target from triple '{s}', Error: {s}\n", .{ target_triple, error_message });
            std.process.exit(1);
        }

        const cpu = "generic";
        const features = "";
        const target_machine = llvm.target_machine.LLVMCreateTargetMachine(target, target_triple, cpu, features, .LLVMCodeGenLevelDefault, .LLVMRelocDefault, .LLVMCodeModelDefault);
        const pass_manager = llvm_core.LLVMCreatePassManager();

        const result = llvm.target_machine.LLVMTargetMachineEmitToFile(target_machine, llvm_ir_module, object_file_path, .LLVMObjectFile, &error_message);

        if (result != 0) {
            std.debug.print("Target machine can't emit a file of this type: {s}\n", .{error_message});
            llvm_core.LLVMDisposeMessage(error_message);
            llvm_core.LLVMDisposePassManager(pass_manager);
            llvm_core.LLVMDisposeModule(llvm_ir_module);
            std.process.exit(1);
        }

        llvm.target_machine.LLVMAddAnalysisPasses(target_machine, pass_manager);
        _ = llvm_core.LLVMRunPassManager(pass_manager, llvm_ir_module);

        llvm_core.LLVMDisposeModule(llvm_ir_module);
        llvm_core.LLVMDisposePassManager(pass_manager);

        _ = external_linker.link(object_file_path) catch |err_| {
            std.debug.print("Failed to link object file '{s}', Error: {any}\n", .{ object_file_path, err_ });
            std.process.exit(1);
        };
        std.debug.print("Successfully compiled source file '{s}'\n", .{source_file});
    }

    fn readFile(self: *Self, path: []const u8) []const u8 {
        var file = std.fs.cwd().openFile(path, .{}) catch |err|
            {
            std.debug.print("Failed to open file '{s}', Error: {any}\n", .{ path, err });
            return std.process.exit(1);
        };
        const out = file.readToEndAlloc(self.allocator, comptime std.math.maxInt(usize)) catch |err| {
            std.debug.print("Failed to read file '{s}', Error: {any}", .{ path, err });
            return std.process.exit(1);
        };
        return out;
    }
};
