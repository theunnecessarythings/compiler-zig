const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const TokenSpan = tokenizer.TokenSpan;

pub const SourceManager = struct {
    allocator: std.mem.Allocator,
    files_map: std.AutoArrayHashMap(i64, []const u8),
    files_set: std.StringArrayHashMap(void),
    last_source_file_id: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) SourceManager {
        return SourceManager{
            .allocator = allocator,
            .files_map = std.AutoArrayHashMap(i64, []const u8).init(allocator),
            .files_set = std.StringArrayHashMap(void).init(allocator),
            .last_source_file_id = -1,
        };
    }

    pub fn resolveSourcePath(self: *const Self, source_id: i64) ?[]const u8 {
        return self.files_map.get(source_id);
    }

    pub fn isPathRegistered(self: *const Self, path: []const u8) bool {
        return self.files_set.get(path) != null;
    }

    pub fn registerSourcePath(self: *Self, path: []const u8) !i64 {
        const path_copy = try self.allocator.dupe(u8, path);
        self.last_source_file_id += 1;
        try self.files_map.put(self.last_source_file_id, path_copy);
        try self.files_set.put(path, {});
        return self.last_source_file_id;
    }
};

pub const DiagnosticLevel = enum {
    Error,
    Warning,
};

pub const Error = error{
    NotImplemented,
    NotFound,
    SocketNotConnected,
    Stop,
    OutOfMemory,
    FileTooBig,
    AccessDenied,
    SystemResources,
    Unexpected,
    IsDir,
    OutOfBounds,
    InvalidCharacter,
    Overflow,
    WouldBlock,
    InputOutput,
    OperationAborted,
    BrokenPipe,
    ConnectionResetByPeer,
    ConnectionTimedOut,
    NotOpenForReading,
    NetNameDeleted,
};
pub fn diagnosticLevelLiteral(level: DiagnosticLevel) []const u8 {
    return switch (level) {
        DiagnosticLevel.Error => "ERROR",
        DiagnosticLevel.Warning => "WARNING",
    };
}

pub const Diagnostic = struct {
    location: TokenSpan,
    message: []const u8,
    level: DiagnosticLevel,

    pub fn init(location: TokenSpan, message: []const u8, level: DiagnosticLevel) Diagnostic {
        return Diagnostic{
            .location = location,
            .message = message,
            .level = level,
        };
    }
};

pub const DiagnosticEngine = struct {
    allocator: std.mem.Allocator,
    source_manager: *SourceManager,
    diagnostics: std.AutoArrayHashMap(DiagnosticLevel, std.ArrayList(Diagnostic)),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, source_manager: *SourceManager) !DiagnosticEngine {
        var diagnostics = std.AutoArrayHashMap(DiagnosticLevel, std.ArrayList(Diagnostic)).init(allocator);
        _ = try diagnostics.put(DiagnosticLevel.Error, std.ArrayList(Diagnostic).init(allocator));
        _ = try diagnostics.put(DiagnosticLevel.Warning, std.ArrayList(Diagnostic).init(allocator));
        return DiagnosticEngine{
            .allocator = allocator,
            .source_manager = source_manager,
            .diagnostics = diagnostics,
        };
    }

    pub fn reportDiagnostics(self: *Self, level: DiagnosticLevel) void {
        std.debug.print("{s}s: {d}", .{
            diagnosticLevelLiteral(level),
            self.levelCount(level),
        });
        std.debug.print("====================================\n", .{});
        if (self.diagnostics.get(level)) |diagnostics| {
            for (diagnostics.items) |*diagnostic| {
                self.reportDiagnostic(diagnostic);
            }
        }
    }

    fn readFileLine(self: *Self, file_name: []const u8, line_number: usize) ![]const u8 {
        var file = try std.fs.cwd().openFile(file_name, .{});
        defer file.close();
        var buf_reader = std.io.bufferedReader(file.reader());
        var in_stream = buf_reader.reader();
        const buf = try self.allocator.alloc(u8, 1024);
        var current_line: u32 = 1;
        while (try in_stream.readUntilDelimiterOrEof(buf, '\n')) |line| {
            if (current_line == line_number) {
                return line;
            }
            current_line += 1;
        }
        return "";
    }

    fn reportDiagnostic(self: *Self, diagnostic: *Diagnostic) void {
        const location = diagnostic.location;
        const message = diagnostic.message;
        const file_name = self.source_manager.resolveSourcePath(location.file_id);
        const line_number = location.line_number;
        const source_line = self.readFileLine(file_name.?, line_number) catch {
            std.debug.print("Failed to read source file line\n", .{});
            return;
        };

        const kindLiteral = diagnosticLevelLiteral(diagnostic.level);
        std.debug.print("{s} in {s}:{d}:{d}\n", .{ kindLiteral, file_name.?, line_number, location.column_start });

        const lineNumberHeader = std.fmt.allocPrint(self.allocator, "{d} | ", .{line_number}) catch unreachable;
        std.debug.print("{s}{s}\n", .{ lineNumberHeader, source_line });

        const headerSize = lineNumberHeader.len;
        for (0..location.column_start + headerSize) |i| {
            _ = i;
            std.debug.print("~", .{});
        }

        std.debug.print("^ {s}\n\n", .{message});
    }

    pub fn reportError(self: *Self, location: TokenSpan, message: []const u8) !void {
        const d = Diagnostic.init(location, message, DiagnosticLevel.Error);
        var ds = self.diagnostics.getPtr(DiagnosticLevel.Error).?;
        _ = try ds.append(d);
    }

    pub fn reportWarning(self: *Self, location: TokenSpan, message: []const u8) !void {
        const d = Diagnostic.init(location, message, DiagnosticLevel.Warning);
        var ds = self.diagnostics.getPtr(DiagnosticLevel.Warning).?;
        _ = try ds.append(d);
    }

    pub fn levelCount(self: *Self, level: DiagnosticLevel) usize {
        const kind_diagnostics = self.diagnostics.get(level);
        if (kind_diagnostics == null) {
            return 0;
        }
        return kind_diagnostics.?.items.len;
    }
};

pub const LogType = enum {
    Parser,
    TypeChecker,
    Tokenizer,
    Codegen,
    General,
};

pub const LogLevel = enum {
    Debug,
    Info,
    Warning,
    Error,
};

pub const LogOptions = struct {
    module: LogType = LogType.General,
    log_level: LogLevel = LogLevel.Info,

    pub var enable_parser_logging: bool = false;
    pub var enable_typechecker_logging: bool = false;
    pub var enable_tokenizer_logging: bool = false;
    pub var enable_codegen_logging: bool = false;
    pub var enable_general_logging: bool = false;
};

fn logfn(loglevel: LogLevel, comptime fmt: []const u8, args: anytype) void {
    switch (loglevel) {
        .Debug => std.log.debug(fmt, args),
        .Info => std.log.info(fmt, args),
        .Warning => std.log.warn(fmt, args),
        .Error => std.log.err(fmt, args),
    }
}

pub fn log(comptime fmt: []const u8, args: anytype, log_options: LogOptions) void {
    switch (log_options.module) {
        .Parser => if (LogOptions.enable_parser_logging) logfn(log_options.log_level, fmt, args),
        .TypeChecker => if (LogOptions.enable_typechecker_logging) logfn(log_options.log_level, fmt, args),
        .Tokenizer => if (LogOptions.enable_tokenizer_logging) logfn(log_options.log_level, fmt, args),
        .Codegen => if (LogOptions.enable_codegen_logging) logfn(log_options.log_level, fmt, args),
        .General => if (LogOptions.enable_general_logging) logfn(log_options.log_level, fmt, args),
    }
}
