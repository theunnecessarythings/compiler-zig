const std = @import("std");
const types = @import("types.zig");
const Type = types.Type;
const llvm_types = @import("llvm/types.zig");
const log = @import("diagnostics.zig").log;

pub const Any = union(enum) {
    U32: u32,
    Type: *Type,
    Bool: bool,
    LLVMValue: llvm_types.LLVMValueRef,
    LLVMType: llvm_types.LLVMTypeRef,
    Void,
    Null,
};

pub fn ScopedMap(comptime V: type) type {
    return struct {
        allocator: std.mem.Allocator,
        linked_scoped: std.ArrayList(std.StringArrayHashMap(V)),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .linked_scoped = std.ArrayList(std.StringArrayHashMap(V)).init(allocator),
            };
        }

        pub fn define(self: *Self, key: []const u8, value: V) bool {
            if (self.linked_scoped.getLast().contains(key)) {
                return false;
            }
            const length = self.linked_scoped.items.len;
            self.linked_scoped.items[length - 1].put(key, value) catch unreachable;
            return true;
        }

        pub fn update(self: *Self, key: []const u8, value: V) !void {
            const len = self.linked_scoped.items.len;
            var i: i64 = @intCast(len - 1);
            while (i >= 0) : (i -= 1) {
                if (self.linked_scoped.items[@intCast(i)].contains(key)) {
                    try self.linked_scoped.items[@intCast(i)].put(key, value);
                    // return;
                }
            }
        }

        pub fn isDefined(self: *Self, key: []const u8) bool {
            const len = self.linked_scoped.items.len;
            var i: i64 = @intCast(len - 1);
            while (i >= 0) : (i -= 1) {
                if (self.linked_scoped.items[@intCast(i)].contains(key)) {
                    return true;
                }
            }
            return false;
        }

        pub fn pushNewScope(self: *Self) !void {
            return self.linked_scoped.append(std.StringArrayHashMap(V).init(self.allocator));
        }

        pub fn popCurrentScope(self: *Self) void {
            _ = self.linked_scoped.pop();
        }

        pub fn printKeys(self: *const Self) void {
            const len = self.linked_scoped.items.len;
            var i: i64 = @intCast(len - 1);
            while (i >= 0) : (i -= 1) {
                const keys = self.linked_scoped.items[@intCast(i)].keys();
                for (keys) |key| {
                    log("Level {d}: {s}", .{ i, key }, .{ .module = .General });
                }
            }
        }

        pub fn lookup(self: *Self, key: []const u8) ?V {
            const len = self.linked_scoped.items.len;
            var i: i64 = @intCast(len - 1);

            while (i >= 0) : (i -= 1) {
                if (self.linked_scoped.items[@intCast(i)].contains(key)) {
                    return self.linked_scoped.items[@intCast(i)].get(key);
                }
            }
            return null;
        }

        pub fn lookupOnCurrent(self: *Self, key: []const u8) ?V {
            const i = self.linked_scoped.items.len - 1;
            if (self.linked_scoped.items[i].contains(key)) {
                return self.linked_scoped.items[i].get(key);
            }
            return null;
        }

        pub fn lookupWithLevel(self: *Self, key: []const u8) struct { x: ?V, i: usize } {
            const len = self.linked_scoped.items.len;
            var i: i64 = @intCast(len - 1);

            while (i >= 0) : (i -= 1) {
                if (self.linked_scoped.items[@intCast(i)].contains(key)) {
                    return .{ .x = self.linked_scoped.items[@intCast(i)].get(key), .i = @intCast(i) };
                }
            }
            return .{ .x = null, .i = 0 };
        }

        pub fn size(self: *Self) usize {
            return self.linked_scoped.items.len;
        }
    };
}

pub fn ScopedList(comptime V: type) type {
    return struct {
        allocator: std.mem.Allocator,
        linked_scopes: std.ArrayList(std.ArrayList(V)),

        const Self = @This();
        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .linked_scopes = std.ArrayList(std.ArrayList(V)).init(allocator),
            };
        }

        pub fn pushFront(self: *Self, value: V) !void {
            try self.linked_scopes.items[self.linked_scopes.items.len - 1].insert(0, value);
        }

        pub fn pushBack(self: *Self, value: V) void {
            self.linked_scopes.items[self.linked_scopes.items.len - 1].append(value);
        }

        pub fn pushNewScope(self: *Self) !void {
            return self.linked_scopes.append(std.ArrayList(V).init(self.allocator));
        }

        pub fn popCurrentScope(self: *Self) void {
            _ = self.linked_scopes.pop();
        }

        pub fn size(self: *const Self) usize {
            return self.linked_scopes.items.len;
        }

        pub fn getScopeElements(self: *const Self, index: usize) []V {
            return self.linked_scopes.items[index].items;
        }

        pub fn getScopeElements2(self: *const Self) []V {
            return self.linked_scopes.getLast().items;
        }
    };
}

pub const AliasTable = struct {
    allocator: std.mem.Allocator,
    type_alias_table: std.StringArrayHashMap(*Type),

    pub fn init(allocator: std.mem.Allocator) !AliasTable {
        var table = AliasTable{
            .allocator = allocator,
            .type_alias_table = std.StringArrayHashMap(*Type).init(allocator),
        };
        try table.configTypeAliasTable();
        return table;
    }

    pub fn contains(self: *AliasTable, key: []const u8) bool {
        return self.type_alias_table.contains(key);
    }

    pub fn defineAlias(self: *AliasTable, key: []const u8, value: *Type) !void {
        try self.type_alias_table.put(key, value);
    }

    pub fn resolveAlias(self: *AliasTable, key: []const u8) *Type {
        return self.type_alias_table.get(key).?;
    }

    fn configTypeAliasTable(self: *AliasTable) !void {
        try self.defineAlias("int1", @constCast(&Type.I1_TYPE));
        try self.defineAlias("int8", @constCast(&Type.I8_TYPE));
        try self.defineAlias("int16", @constCast(&Type.I16_TYPE));
        try self.defineAlias("int32", @constCast(&Type.I32_TYPE));
        try self.defineAlias("int64", @constCast(&Type.I64_TYPE));

        try self.defineAlias("char", @constCast(&Type.I8_TYPE));
        try self.defineAlias("uchar", @constCast(&Type.U8_TYPE));

        try self.defineAlias("uint8", @constCast(&Type.U8_TYPE));
        try self.defineAlias("uint16", @constCast(&Type.U16_TYPE));
        try self.defineAlias("uint32", @constCast(&Type.U32_TYPE));
        try self.defineAlias("uint64", @constCast(&Type.U64_TYPE));

        try self.defineAlias("float32", @constCast(&Type.F32_TYPE));
        try self.defineAlias("float64", @constCast(&Type.F64_TYPE));

        try self.defineAlias("void", @constCast(&Type.VOID_TYPE));
    }
};

pub fn contains(comptime T: type, vec: []const T, value: T) bool {
    for (vec) |item| {
        if (T == []const u8) {
            if (std.mem.eql(u8, item, value)) {
                return true;
            }
        } else {
            if (item == value) {
                return true;
            }
        }
    }
    return false;
}

pub fn combineStruct(comptime T1: type, comptime T2: type) type {
    const fields = std.meta.fields(T1) ++ std.meta.fields(T2);
    var combined_fields: [fields.len]std.builtin.Type.StructField = undefined;
    var i: usize = 0;
    inline for (fields) |field| {
        combined_fields[i] = .{
            .name = field.name,
            .type = field.type,
            .default_value = field.default_value,
            .is_comptime = field.is_comptime,
            .alignment = field.alignment,
        };
        i += 1;
    }

    return @Type(.{
        .Struct = .{
            .layout = .auto,
            .fields = &combined_fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

pub fn indexOf(haystack: [][]const u8, needle: []const u8) ?usize {
    for (haystack, 0..haystack.len) |item, index| {
        if (std.mem.eql(u8, item, needle)) {
            return index;
        }
    }
    return null;
}
