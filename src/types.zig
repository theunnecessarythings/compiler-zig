const std = @import("std");
const TokenKind = @import("tokenizer.zig").TokenKind;
const Token = @import("tokenizer.zig").Token;
const tokenizer = @import("tokenizer.zig");
const Error = @import("diagnostics.zig").Error;

pub const TypeKind = enum {
    Number,
    Pointer,
    Function,
    StaticArray,
    StaticVector,
    Struct,
    Tuple,
    Enum,
    EnumElement,
    GenericParameter,
    GenericStruct,
    None,
    Void,
    Null,
};

pub const NumberKind = enum {
    Integer1,
    Integer8,
    Integer16,
    Integer32,
    Integer64,
    UInteger8,
    UInteger16,
    UInteger32,
    UInteger64,
    Float32,
    Float64,
};

pub fn numberKindWidth(kind: NumberKind) u32 {
    return switch (kind) {
        .Integer1 => 1,
        .Integer8 => 8,
        .Integer16 => 16,
        .Integer32 => 32,
        .Integer64 => 64,
        .UInteger8 => 8,
        .UInteger16 => 16,
        .UInteger32 => 32,
        .UInteger64 => 64,
        .Float32 => 32,
        .Float64 => 64,
    };
}

pub fn numberKindTokenKind(kind: NumberKind) TokenKind {
    return switch (kind) {
        .Integer1 => .Int1,
        .Integer8 => .Int8,
        .Integer16 => .Int16,
        .Integer32 => .Int32,
        .Integer64 => .Int64,
        .UInteger8 => .Uint8,
        .UInteger16 => .Uint16,
        .UInteger32 => .Uint32,
        .UInteger64 => .Uint64,
        .Float32 => .Float32,
        .Float64 => .Float64,
    };
}

pub fn integersKindMaxValue(kind: NumberKind) u64 {
    return switch (kind) {
        .Integer1 => 1,
        .Integer8 => std.math.maxInt(i8),
        .Integer16 => std.math.maxInt(i16),
        .Integer32 => std.math.maxInt(i32),
        .Integer64 => std.math.maxInt(i64),
        .UInteger8 => std.math.maxInt(u8),
        .UInteger16 => std.math.maxInt(u16),
        .UInteger32 => std.math.maxInt(u32),
        .UInteger64 => std.math.maxInt(u64),
        else => unreachable,
    };
}

pub fn integersKindMinValue(kind: NumberKind) i64 {
    return switch (kind) {
        .Integer1 => 0,
        .Integer8 => std.math.minInt(i8),
        .Integer16 => std.math.minInt(i16),
        .Integer32 => std.math.minInt(i32),
        .Integer64 => std.math.minInt(i64),
        .UInteger8 => 0,
        .UInteger16 => 0,
        .UInteger32 => 0,
        .UInteger64 => 0,
        else => unreachable,
    };
}

pub const Type = union(enum) {
    Number: NumberType,
    Pointer: PointerType,
    Function: FunctionType,
    StaticArray: StaticArrayType,
    StaticVector: StaticVectorType,
    Struct: StructType,
    Tuple: TupleType,
    Enum: EnumType,
    EnumElement: EnumElementType,
    GenericParameter: GenericParameterType,
    GenericStruct: GenericStructType,
    None: NoneType,
    Void: VoidType,
    Null: NullType,

    pub const I1_TYPE = Type{ .Number = NumberType.init(.Integer1) };
    pub const I8_TYPE = Type{ .Number = NumberType.init(.Integer8) };
    pub const I16_TYPE = Type{ .Number = NumberType.init(.Integer16) };
    pub const I32_TYPE = Type{ .Number = NumberType.init(.Integer32) };
    pub const I64_TYPE = Type{ .Number = NumberType.init(.Integer64) };
    pub const U8_TYPE = Type{ .Number = NumberType.init(.UInteger8) };
    pub const U16_TYPE = Type{ .Number = NumberType.init(.UInteger16) };
    pub const U32_TYPE = Type{ .Number = NumberType.init(.UInteger32) };
    pub const U64_TYPE = Type{ .Number = NumberType.init(.UInteger64) };
    pub const F32_TYPE = Type{ .Number = NumberType.init(.Float32) };
    pub const F64_TYPE = Type{ .Number = NumberType.init(.Float64) };
    pub const VOID_TYPE = Type{ .Void = VoidType.init() };
    pub const NULL_TYPE = Type{ .Null = NullType.init() };
    pub const NONE_TYPE = Type{ .None = NoneType.init() };
    pub const I8_PTR_TYPE = Type{ .Pointer = PointerType.init(@constCast(&I8_TYPE)) };
    pub const I32_PTR_TYPE = Type{ .Pointer = PointerType.init(@constCast(&I32_TYPE)) };

    pub fn typeKind(self: *const Type) TypeKind {
        return switch (self.*) {
            .Number => .Number,
            .Pointer => .Pointer,
            .Function => .Function,
            .StaticArray => .StaticArray,
            .StaticVector => .StaticVector,
            .Struct => .Struct,
            .Tuple => .Tuple,
            .Enum => .Enum,
            .EnumElement => .EnumElement,
            .GenericParameter => .GenericParameter,
            .GenericStruct => .GenericStruct,
            .None => .None,
            .Void => .Void,
            .Null => .Null,
        };
    }
};

pub const NumberType = struct {
    number_kind: NumberKind,

    pub fn init(kind: NumberKind) NumberType {
        return NumberType{
            .number_kind = kind,
        };
    }
};

pub const PointerType = struct {
    base_type: *Type,

    pub fn init(base_type: *Type) PointerType {
        return PointerType{
            .base_type = base_type,
        };
    }
};

pub const StaticArrayType = struct {
    element_type: ?*Type,
    size: u32,

    pub fn init(element_type: ?*Type, size: u32) StaticArrayType {
        return StaticArrayType{
            .element_type = element_type,
            .size = size,
        };
    }
};

pub const StaticVectorType = struct {
    array: *StaticArrayType,

    pub fn init(array: *StaticArrayType) StaticVectorType {
        return StaticVectorType{
            .array = array,
        };
    }
};

pub const FunctionType = struct {
    name: Token,
    parameters: std.ArrayList(*Type),
    return_type: *Type,
    has_varargs: bool,
    varargs_type: ?*Type,
    is_intrinsic: bool,
    is_generic: bool,
    generic_names: std.ArrayList([]const u8),
    implicit_parameters_count: u32 = 0,

    pub fn init(
        name: Token,
        parameters: std.ArrayList(*Type),
        return_type: *Type,
        has_varargs: bool,
        varargs_type: ?*Type,
        is_intrinsic: bool,
        is_generic: bool,
        generic_names: std.ArrayList([]const u8),
    ) FunctionType {
        return FunctionType{
            .name = name,
            .parameters = parameters,
            .return_type = return_type,
            .has_varargs = has_varargs,
            .varargs_type = varargs_type,
            .is_intrinsic = is_intrinsic,
            .is_generic = is_generic,
            .generic_names = generic_names,
        };
    }
};

pub const StructType = struct {
    name: []const u8,
    field_names: std.ArrayList([]const u8),
    field_types: std.ArrayList(*Type),
    generic_parameters: std.ArrayList([]const u8),
    generic_parameter_types: std.ArrayList(*Type),
    is_packed: bool = false,
    is_generic: bool = false,
    is_extern: bool = false,
    pub fn init(
        name: []const u8,
        field_names: std.ArrayList([]const u8),
        field_types: std.ArrayList(*Type),
        generic_parameters: std.ArrayList([]const u8),
        generic_parameter_types: std.ArrayList(*Type),
        is_packed: bool,
        is_generic: bool,
        is_extern: bool,
    ) StructType {
        return StructType{
            .name = name,
            .field_names = field_names,
            .field_types = field_types,
            .generic_parameters = generic_parameters,
            .generic_parameter_types = generic_parameter_types,
            .is_packed = is_packed,
            .is_generic = is_generic,
            .is_extern = is_extern,
        };
    }
};

pub const TupleType = struct {
    name: []const u8,
    field_types: std.ArrayList(*Type),

    pub fn init(name: []const u8, field_types: std.ArrayList(*Type)) TupleType {
        return TupleType{
            .name = name,
            .field_types = field_types,
        };
    }
};

pub const EnumType = struct {
    name: []const u8,
    values: std.StringArrayHashMap(u32),
    element_type: ?*Type,

    pub fn init(
        name: []const u8,
        values: std.StringArrayHashMap(u32),
        element_type: ?*Type,
    ) EnumType {
        return EnumType{
            .name = name,
            .values = values,
            .element_type = element_type,
        };
    }
};

pub const EnumElementType = struct {
    enum_name: []const u8,
    element_type: *Type,

    pub fn init(enum_name: []const u8, element_type: *Type) EnumElementType {
        return EnumElementType{
            .enum_name = enum_name,
            .element_type = element_type,
        };
    }
};

pub const GenericParameterType = struct {
    name: []const u8,

    pub fn init(name: []const u8) GenericParameterType {
        return GenericParameterType{
            .name = name,
        };
    }
};

pub const GenericStructType = struct {
    struct_type: *StructType,
    parameters: std.ArrayList(*Type),

    pub fn init(struct_type: *StructType, parameters: std.ArrayList(*Type)) GenericStructType {
        return GenericStructType{
            .struct_type = struct_type,
            .parameters = parameters,
        };
    }
};

pub const VoidType = struct {
    pub fn init() VoidType {
        return VoidType{};
    }
};

pub const NullType = struct {
    pub fn init() NullType {
        return NullType{};
    }
};

pub const NoneType = struct {
    pub fn init() NoneType {
        return NoneType{};
    }
};

pub fn isTypesEquals(type_a: *const Type, type_b: *const Type) bool {
    const type_kind = type_a.typeKind();
    const other_kind = type_b.typeKind();

    if (type_kind == TypeKind.Number and type_b.typeKind() == TypeKind.Number) {
        const type_number = type_a.Number;
        const other_number = type_b.Number;
        return type_number.number_kind == other_number.number_kind;
    }

    if (type_kind == TypeKind.Pointer and type_b.typeKind() == TypeKind.Pointer) {
        const type_ptr = type_a.Pointer;
        const other_ptr = type_b.Pointer;
        return isTypesEquals(type_ptr.base_type, other_ptr.base_type);
    }

    if (type_kind == TypeKind.StaticArray and type_b.typeKind() == TypeKind.StaticArray) {
        const type_array = type_a.StaticArray;
        const other_array = type_b.StaticArray;
        return type_array.size == other_array.size and
            isTypesEquals(type_array.element_type.?, other_array.element_type.?);
    }

    if (type_kind == TypeKind.StaticVector and type_b.typeKind() == TypeKind.StaticVector) {
        const type_vector = type_a.StaticVector;
        const other_vector = type_b.StaticVector;
        return isTypesEquals(type_vector.array.element_type.?, other_vector.array.element_type.?);
    }

    if (type_kind == TypeKind.Function and type_b.typeKind() == TypeKind.Function) {
        const type_function = type_a.Function;
        const other_function = type_b.Function;
        return isFunctionsTypesEquals(&type_function, &other_function);
    }

    if (type_kind == TypeKind.Struct and type_b.typeKind() == TypeKind.Struct) {
        const type_struct = type_a.Struct;
        const other_struct = type_b.Struct;
        return std.mem.eql(u8, type_struct.name, other_struct.name);
    }

    if (type_kind == TypeKind.Tuple and type_b.typeKind() == TypeKind.Tuple) {
        const type_tuple = type_a.Tuple;
        const other_tuple = type_b.Tuple;
        return std.mem.eql(u8, type_tuple.name, other_tuple.name);
    }

    if (type_kind == TypeKind.EnumElement and type_b.typeKind() == TypeKind.EnumElement) {
        const type_element = type_a.EnumElement;
        const other_element = type_b.EnumElement;
        return std.mem.eql(u8, type_element.enum_name, other_element.enum_name);
    }

    if (type_kind == TypeKind.GenericStruct and type_b.typeKind() == TypeKind.GenericStruct) {
        const type_element = type_a.GenericStruct;
        const other_element = type_b.GenericStruct;
        const type_struct = Type{
            .Struct = type_element.struct_type.*,
        };
        const other_struct = Type{
            .Struct = other_element.struct_type.*,
        };
        if (!isTypesEquals(&type_struct, &other_struct)) {
            return false;
        }

        const type_parameters = type_element.parameters;
        const other_parameters = other_element.parameters;
        if (type_parameters.items.len != other_parameters.items.len) {
            return false;
        }

        for (type_parameters.items, 0..) |type_parameter, i| {
            if (!isTypesEquals(type_parameter, other_parameters.items[i])) {
                return false;
            }
        }

        return true;
    }

    return type_kind == other_kind;
}

pub fn isFunctionsTypesEquals(type_a: *const FunctionType, other: *const FunctionType) bool {
    const type_parameters = type_a.parameters;
    const other_parameters = other.parameters;
    const type_parameters_size = type_parameters.items.len;
    if (type_parameters_size != other_parameters.items.len) {
        return false;
    }
    for (type_parameters.items, 0..) |type_parameter, i| {
        if (!isTypesEquals(type_parameter, other_parameters.items[i])) {
            return false;
        }
    }
    return isTypesEquals(type_a.return_type, other.return_type);
}

pub fn canTypesCasted(from: *Type, to: *Type) bool {
    const from_kind = from.typeKind();
    const to_kind = to.typeKind();

    // Catch casting from un castable type
    if (from_kind == TypeKind.Void or from_kind == TypeKind.None or
        from_kind == TypeKind.Enum or from_kind == TypeKind.EnumElement or
        from_kind == TypeKind.Function)
    {
        return false;
    }

    // Catch casting to un castable type
    if (to_kind == TypeKind.Void or to_kind == TypeKind.None or
        to_kind == TypeKind.Enum or to_kind == TypeKind.EnumElement or
        to_kind == TypeKind.Function)
    {
        return false;
    }

    // Casting between numbers
    if (from_kind == TypeKind.Number and to_kind == TypeKind.Number) {
        return true;
    }

    // Allow casting to and from void pointer type
    if (isPointerOfType(from, &Type.VOID_TYPE) or isPointerOfType(to, &Type.VOID_TYPE)) {
        return true;
    }

    // Casting Array to pointer of the same elemnet type
    if (from_kind == TypeKind.StaticArray and to_kind == TypeKind.Pointer) {
        const from_array = from.StaticArray;
        const to_pointer = to.Pointer;
        return isTypesEquals(from_array.element_type.?, to_pointer.base_type);
    }

    return false;
}

pub fn getTypeLiteral(allocator: std.mem.Allocator, type_a: *const Type) ![]const u8 {
    const type_kind = type_a.typeKind();
    if (type_kind == TypeKind.Number) {
        const number_type = type_a.Number;
        return getNumberKindLiteral(number_type.number_kind);
    }

    if (type_kind == TypeKind.StaticArray) {
        const array_type = type_a.StaticArray;
        return try std.fmt.allocPrint(allocator, "[{d}]{s}", .{ array_type.size, try getTypeLiteral(allocator, array_type.element_type.?) });
    }

    if (type_kind == TypeKind.StaticVector) {
        const vector_type = type_a.StaticVector;
        return try std.fmt.allocPrint(allocator, "@vec{s}", .{try getTypeLiteral(allocator, vector_type.array.element_type.?)});
    }

    if (type_kind == TypeKind.Pointer) {
        const pointer_type = type_a.Pointer;
        return try std.fmt.allocPrint(allocator, "*{s}", .{try getTypeLiteral(allocator, pointer_type.base_type)});
    }

    if (type_kind == TypeKind.Function) {
        const function_type = type_a.Function;

        var string_stream = std.ArrayList(u8).init(allocator);
        try string_stream.append('(');
        for (function_type.parameters.items) |parameter| {
            try string_stream.append(' ');
            try string_stream.appendSlice(try getTypeLiteral(allocator, parameter));
            try string_stream.append(' ');
        }
        try string_stream.append(')');
        try string_stream.appendSlice(" -> ");
        try string_stream.appendSlice(try getTypeLiteral(allocator, function_type.return_type));
        return string_stream.toOwnedSlice();
    }

    if (type_kind == TypeKind.Struct) {
        const struct_type = type_a.Struct;
        return struct_type.name;
    }

    if (type_kind == TypeKind.Tuple) {
        const tuple_type = type_a.Tuple;

        var string_stream = std.ArrayList(u8).init(allocator);
        try string_stream.append('(');
        for (tuple_type.field_types.items) |parameter| {
            try string_stream.append(' ');
            try string_stream.appendSlice(try getTypeLiteral(allocator, parameter));
            try string_stream.append(' ');
        }
        try string_stream.append(')');
        return string_stream.toOwnedSlice();
    }

    if (type_kind == TypeKind.Enum) {
        const enum_type = type_a.Enum;
        return enum_type.name;
    }

    if (type_kind == TypeKind.EnumElement) {
        const enum_element = type_a.EnumElement;
        return enum_element.enum_name;
    }

    if (type_kind == TypeKind.GenericStruct) {
        const generic_struct = type_a.GenericStruct;
        var string_stream = std.ArrayList(u8).init(allocator);
        try string_stream.appendSlice(try getTypeLiteral(allocator, &Type{ .Struct = generic_struct.struct_type.* }));
        try string_stream.append('<');
        for (generic_struct.parameters.items) |parameter| {
            try string_stream.appendSlice(try getTypeLiteral(allocator, parameter));
            try string_stream.append(',');
        }
        try string_stream.append('>');
        return string_stream.toOwnedSlice();
    }

    if (type_kind == TypeKind.GenericParameter) {
        const generic_parameter = type_a.GenericParameter;
        return generic_parameter.name;
    }

    if (type_kind == TypeKind.None) {
        return "none";
    }

    if (type_kind == TypeKind.Void) {
        return "void";
    }

    if (type_kind == TypeKind.Null) {
        return "null";
    }

    return "";
}

pub fn getNumberKindLiteral(kind: NumberKind) []const u8 {
    return switch (kind) {
        .Integer1 => "int1",
        .Integer8 => "int8",
        .Integer16 => "int16",
        .Integer32 => "int32",
        .Integer64 => "int64",
        .UInteger8 => "uint8",
        .UInteger16 => "uint16",
        .UInteger32 => "uint32",
        .UInteger64 => "uint64",
        .Float32 => "float32",
        .Float64 => "float64",
    };
}

pub fn isNumberType(type_a: *Type) bool {
    return type_a.typeKind() == TypeKind.Number;
}

pub fn isIntegerType(type_a: *Type) bool {
    if (type_a.typeKind() == .Number) {
        const number_type = type_a.Number;
        const number_kind = number_type.number_kind;
        return number_kind != .Float32 and
            number_kind != .Float64;
    }
    return false;
}

pub fn isSignedIntegerType(type_a: *Type) bool {
    if (type_a.typeKind() == .Number) {
        const number_type = type_a.Number;
        const number_kind = number_type.number_kind;
        return number_kind == .Integer1 or
            number_kind == .Integer8 or
            number_kind == .Integer16 or
            number_kind == .Integer32 or
            number_kind == .Integer64;
    }
    return false;
}

pub fn isInteger1Type(type_a: *Type) bool {
    if (type_a.typeKind() == .Number) {
        const number_type = type_a.Number;
        return number_type.number_kind == .Integer1;
    }
    return false;
}

pub fn isInteger32Type(type_a: *Type) bool {
    if (type_a.typeKind() == .Number) {
        const number_type = type_a.Number;
        return number_type.number_kind == .Integer32;
    }
    return false;
}

pub fn isInteger64Type(type_a: *Type) bool {
    if (type_a.typeKind() == .Number) {
        const number_type = type_a.Number;
        return number_type.number_kind == .Integer64;
    }
    return false;
}

pub fn isUnsignedIntegerType(type_a: *Type) bool {
    if (type_a.typeKind() == .Number) {
        const number_type = type_a.Number;
        const number_kind = number_type.number_kind;
        return number_kind == .UInteger8 or
            number_kind == .UInteger16 or
            number_kind == .UInteger32 or
            number_kind == .UInteger64;
    }
    return false;
}

pub fn isEnumType(type_a: *Type) bool {
    return type_a.typeKind() == .Enum;
}

pub fn isEnumElementType(type_a: *Type) bool {
    return type_a.typeKind() == .EnumElement;
}

pub fn isStructType(type_a: *Type) bool {
    return type_a.typeKind() == .Struct;
}

pub fn isGenericStructType(type_a: *const Type) bool {
    return type_a.typeKind() == .GenericStruct;
}

pub fn isTupleType(type_a: *Type) bool {
    return type_a.typeKind() == .Tuple;
}

pub fn isBooleanType(type_a: *Type) bool {
    if (type_a.typeKind() == .Number) {
        const number_type = type_a.Number;
        return number_type.number_kind == .Integer1;
    }
    return false;
}

pub fn isFunctionType(type_a: *const Type) bool {
    return type_a.typeKind() == .Function;
}

pub fn isFunctionPointerType(type_a: *const Type) bool {
    if (isPointerType(type_a)) {
        const pointer = type_a.Pointer;
        return isFunctionType(pointer.base_type);
    }
    return false;
}

pub fn isArrayType(type_a: *Type) bool {
    return type_a.typeKind() == .StaticArray;
}

pub fn isVectorType(type_a: *Type) bool {
    return type_a.typeKind() == .StaticVector;
}

pub fn isPointerType(type_a: *const Type) bool {
    return type_a.typeKind() == .Pointer;
}

pub fn isVoidType(type_a: *Type) bool {
    return type_a.typeKind() == .Void;
}

pub fn isNullType(type_a: *Type) bool {
    return type_a.typeKind() == .Null;
}

pub fn isNoneType(type_a: *Type) bool {
    const type_kind = type_a.typeKind();

    if (type_kind == .StaticArray) {
        const array_type = type_a.StaticArray;
        return array_type.element_type.?.typeKind() == .None;
    }

    if (type_kind == TypeKind.Pointer) {
        const array_type = type_a.Pointer;
        return array_type.base_type.typeKind() == .None;
    }

    return type_kind == .None;
}

pub fn isPointerOfType(type_a: *Type, base: *const Type) bool {
    if (type_a.typeKind() != .Pointer) {
        return false;
    }
    const pointer_type = type_a.Pointer;
    return isTypesEquals(pointer_type.base_type, base);
}

pub fn isArrayOfType(type_a: *Type, base: *Type) bool {
    if (type_a.typeKind() != .StaticArray) {
        return false;
    }
    const array_type = type_a.StaticArray;
    return isTypesEquals(array_type.element_type, base);
}

pub fn mangleTupleType(allocator: std.mem.Allocator, tuple_type: *const TupleType) ![]const u8 {
    return std.fmt.allocPrint(allocator, "_tuple_{s}", .{try mangleTypes(allocator, tuple_type.field_types.items)});
}

pub fn mangleOperatorFunction(allocator: std.mem.Allocator, kind: TokenKind, parameters: []const *Type) ![]const u8 {
    const operator_literal = try tokenizer.overloadingOperatorLiteral(kind);
    var operator_function_name = try std.fmt.allocPrint(allocator, "_operator_{s}", .{operator_literal});
    for (parameters) |parameter| {
        operator_function_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ operator_function_name, try mangleType(allocator, parameter) });
    }
    return operator_function_name;
}

pub fn mangleTypes(allocator: std.mem.Allocator, types: []const *Type) Error![]const u8 {
    var mangled_types = std.ArrayList(u8).init(allocator);
    for (types) |type_| {
        try mangled_types.appendSlice(try mangleType(allocator, type_));
    }
    return mangled_types.items;
}

fn numberTypeMangler(kind: NumberKind) []const u8 {
    return switch (kind) {
        .Integer1 => "i1",
        .Integer8 => "i8",
        .Integer16 => "i16",
        .Integer32 => "i32",
        .Integer64 => "i64",
        .UInteger8 => "u8",
        .UInteger16 => "u16",
        .UInteger32 => "u32",
        .UInteger64 => "u64",
        .Float32 => "f32",
        .Float64 => "f64",
    };
}

pub fn mangleType(allocator: std.mem.Allocator, type_: *const Type) ![]const u8 {
    const kind = type_.typeKind();
    switch (kind) {
        .Number => {
            const number_type = type_.Number;
            return numberTypeMangler(number_type.number_kind);
        },
        .Pointer => {
            const pointer_type = type_.Pointer;
            return std.fmt.allocPrint(allocator, "p{s}", .{try mangleType(allocator, pointer_type.base_type)});
        },
        .StaticArray => {
            const array_type = type_.StaticArray;
            return std.fmt.allocPrint(allocator, "_a{d}{s}", .{ array_type.size, try mangleType(allocator, array_type.element_type.?) });
        },
        .EnumElement => {
            const enum_element = type_.EnumElement;
            return enum_element.enum_name;
        },
        .Struct => {
            const struct_type = type_.Struct;
            return struct_type.name;
        },
        .Tuple => {
            const tuple_type = type_.Tuple;
            return mangleTupleType(allocator, &tuple_type);
        },
        else => return "",
    }
}
