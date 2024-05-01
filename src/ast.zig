const std = @import("std");
const Token = @import("tokenizer.zig").Token;
const TokenKind = @import("tokenizer.zig").TokenKind;
const types = @import("types.zig");
const Type = types.Type;
const Any = @import("data_structures.zig").Any;
const Error = @import("diagnostics.zig").Error;
const TypeChecker = @import("typechecker.zig").TypeChecker;
const ds = @import("data_structures.zig");

pub const AstNodeType = enum {
    Node,
    Block,
    FieldDeclaration,
    DestructuringDeclaration,
    Prototype,
    Intrinsic,
    Function,
    OperatorFunction,
    Struct,
    Enum,
    IfStatement,
    SwitchStatement,
    ForRange,
    ForEach,
    ForEver,
    While,
    Return,
    Defer,
    Break,
    Continue,
    ExpressionStatement,
    IfExpression,
    SwitchExpression,
    Tuple,
    Assign,
    Binary,
    Bitwise,
    Comparison,
    Logical,
    PrefixUnary,
    PostfixUnary,
    Call,
    Init,
    Lambda,
    Dot,
    Cast,
    TypeSize,
    TypeAlign,
    ValueSize,
    Index,
    EnumElement,
    Array,
    Vector,
    String,
    Literal,
    Number,
    Character,
    Bool,
    Null,
    Undefined,
    Infinity,
};

pub const CompilationUnit = struct {
    tree_nodes: std.ArrayList(*Statement),

    pub fn init(tree_nodes: std.ArrayList(*Statement)) CompilationUnit {
        return CompilationUnit{
            .tree_nodes = tree_nodes,
        };
    }
};

pub const Parameter = struct {
    name: Token,
    parameter_type: *Type,

    pub fn init(name: Token, parameter_type: *Type) Parameter {
        return Parameter{
            .name = name,
            .parameter_type = parameter_type,
        };
    }
};

pub const AstNode = union(enum) {
    expression: Expression,
    statement: Statement,

    const Self = @This();
    pub fn getAstNodeType(self: *const Self) AstNodeType {
        return switch (self) {
            inline else => |*x| x.getAstNodeType(),
        };
    }
};

pub const Expression = union(enum) {
    if_expression: IfExpression,
    switch_expression: SwitchExpression,
    tuple_expression: TupleExpression,
    assign_expression: AssignExpression,
    binary_expression: BinaryExpression,
    bitwise_expression: BitwiseExpression,
    comparison_expression: ComparisonExpression,
    logical_expression: LogicalExpression,
    prefix_unary_expression: PrefixUnaryExpression,
    postfix_unary_expression: PostfixUnaryExpression,
    call_expression: CallExpression,
    init_expression: InitExpression,
    lambda_expression: LambdaExpression,
    dot_expression: DotExpression,
    cast_expression: CastExpression,
    type_size_expression: TypeSizeExpression,
    type_align_expression: TypeAlignExpression,
    value_size_expression: ValueSizeExpression,
    index_expression: IndexExpression,
    enum_access_expression: EnumAccessExpression,
    array_expression: ArrayExpression,
    vector_expression: VectorExpression,
    string_expression: StringExpression,
    literal_expression: LiteralExpression,
    number_expression: NumberExpression,
    character_expression: CharacterExpression,
    bool_expression: BoolExpression,
    null_expression: NullExpression,
    undefined_expression: UndefinedExpression,
    infinity_expression: InfinityExpression,

    const Self = @This();
    pub fn getAstNodeType(self: *const Self) AstNodeType {
        return switch (self.*) {
            inline else => |*x| x.getAstNodeType(),
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return switch (self.*) {
            inline else => |*x| x.accept(visitor),
        };
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return switch (self.*) {
            inline else => |*x| x.getTypeNode(),
        };
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        return switch (self.*) {
            inline else => |*x| x.setTypeNode(new_type),
        };
    }

    pub fn isConstant(self: *const Self) bool {
        return switch (self.*) {
            inline else => |*x| x.isConstant(),
        };
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        return switch (self.*) {
            inline else => |*x| x.jsonStringify(jws),
        };
    }
};

pub const Statement = union(enum) {
    block_statement: BlockStatement,
    const_declaration: ConstDeclaration,
    field_declaration: FieldDeclaration,
    destructuring_declaration: DestructuringDeclaration,
    function_prototype: FunctionPrototype,
    intrinsic_prototype: IntrinsicPrototype,
    function_declaration: FunctionDeclaration,
    operator_function_declaration: OperatorFunctionDeclaration,
    struct_declaration: StructDeclaration,
    enum_declaration: EnumDeclaration,
    if_statement: IfStatement,
    switch_statement: SwitchStatement,
    for_range_statement: ForRangeStatement,
    for_each_statement: ForEachStatement,
    for_ever_statement: ForEverStatement,
    while_statement: WhileStatement,
    return_statement: ReturnStatement,
    defer_statement: DeferStatement,
    break_statement: BreakStatement,
    continue_statement: ContinueStatement,
    expression_statement: ExpressionStatement,

    const Self = @This();
    pub fn getAstNodeType(self: *const Self) AstNodeType {
        return switch (self.*) {
            inline else => |*x| x.getAstNodeType(),
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return switch (self.*) {
            inline else => |*x| x.accept(visitor),
        };
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        switch (self.*) {
            inline else => |*x| try x.jsonStringify(jws),
        }
    }
};

pub const BlockStatement = struct {
    statements: std.ArrayList(*Statement),
    const Self = @This();
    pub fn init(nodes: std.ArrayList(*Statement)) BlockStatement {
        return BlockStatement{
            .statements = nodes,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_block_statement(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Block;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("statements");
        try jws.write(self.statements.items);
        try jws.endObject();
    }
};

pub const FieldDeclaration = struct {
    name: Token,
    field_type: *Type,
    value: ?*Expression,
    is_global: bool,
    has_explicit_type: bool,

    const Self = @This();

    pub fn init(
        name: Token,
        field_type: *Type,
        value: ?*Expression,
        is_global: bool,
    ) FieldDeclaration {
        return FieldDeclaration{
            .name = name,
            .field_type = field_type,
            .value = value,
            .is_global = is_global,
            .has_explicit_type = field_type.typeKind() != .None,
        };
    }
    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_field_declaration(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.FieldDeclaration;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("name");
        try jws.write(self.name);
        try jws.objectField("field_type");
        try jws.write(self.field_type);
        try jws.objectField("value");
        try jws.write(self.value);
        try jws.objectField("is_global");
        try jws.write(self.is_global);
        try jws.objectField("has_explicit_type");
        try jws.write(self.has_explicit_type);
        try jws.endObject();
    }
};

pub const DestructuringDeclaration = struct {
    names: std.ArrayList(Token),
    value_types: std.ArrayList(*Type),
    value: *Expression,
    equal_token: Token,
    is_global: bool,

    const Self = @This();

    pub fn init(
        names: std.ArrayList(Token),
        value_types: std.ArrayList(*Type),
        value: *Expression,
        equal_token: Token,
        is_global: bool,
    ) DestructuringDeclaration {
        return DestructuringDeclaration{
            .names = names,
            .value_types = value_types,
            .value = value,
            .equal_token = equal_token,
            .is_global = is_global,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_destructuring_declaration(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.DestructuringDeclaration;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("names");
        try jws.write(self.names.items);
        try jws.objectField("value_types");
        try jws.write(self.value_types.items);
        try jws.objectField("value");
        try jws.write(self.value);
        try jws.objectField("equal_token");
        try jws.write(self.equal_token);
        try jws.objectField("is_global");
        try jws.write(self.is_global);
        try jws.endObject();
    }
};

pub const ConstDeclaration = struct {
    name: Token,
    value: *Expression,

    const Self = @This();

    pub fn init(name: Token, value: *Expression) ConstDeclaration {
        return ConstDeclaration{
            .name = name,
            .value = value,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_const_declaration(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.FieldDeclaration;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("name");
        try jws.write(self.name);
        try jws.objectField("value");
        try jws.write(self.value);
        try jws.endObject();
    }
};

pub const FunctionPrototype = struct {
    name: Token,
    return_type: ?*Type,
    parameters: std.ArrayList(*Parameter),
    is_external: bool,
    has_varargs: bool,
    varargs_type: ?*Type,
    is_generic: bool,
    generic_parameters: std.ArrayList([]const u8),

    const Self = @This();

    pub fn init(
        name: Token,
        return_type: ?*Type,
        parameters: std.ArrayList(*Parameter),
        is_external: bool,
        has_varargs: bool,
        varargs_type: ?*Type,
        is_generic: bool,
        generic_parameters: std.ArrayList([]const u8),
    ) FunctionPrototype {
        return FunctionPrototype{
            .name = name,
            .return_type = return_type,
            .parameters = parameters,
            .is_external = is_external,
            .has_varargs = has_varargs,
            .varargs_type = varargs_type,
            .is_generic = is_generic,
            .generic_parameters = generic_parameters,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_function_prototype(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Prototype;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("name");
        try jws.write(self.name);
        try jws.objectField("return_type");
        try jws.write(self.return_type);
        try jws.objectField("parameters");
        try jws.write(self.parameters.items);
        try jws.objectField("is_external");
        try jws.write(self.is_external);
        try jws.objectField("has_varargs");
        try jws.write(self.has_varargs);
        try jws.objectField("varargs_type");
        try jws.write(self.varargs_type);
        try jws.objectField("is_generic");
        try jws.write(self.is_generic);
        try jws.objectField("generic_parameters");
        try jws.write(self.generic_parameters.items);
        try jws.endObject();
    }
};

pub const IntrinsicPrototype = struct {
    name: Token,
    native_name: []const u8,
    parameters: std.ArrayList(*Parameter),
    return_type: ?*Type,
    varargs: bool,
    varargs_type: ?*Type,

    const Self = @This();

    pub fn init(
        name: Token,
        native_name: []const u8,
        parameters: std.ArrayList(*Parameter),
        return_type: ?*Type,
        varargs: bool,
        varargs_type: ?*Type,
    ) IntrinsicPrototype {
        return IntrinsicPrototype{
            .name = name,
            .native_name = native_name,
            .parameters = parameters,
            .return_type = return_type,
            .varargs = varargs,
            .varargs_type = varargs_type,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_intrinsic_prototype(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Intrinsic;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("name");
        try jws.write(self.name);
        try jws.objectField("native_name");
        try jws.write(self.native_name);
        try jws.objectField("parameters");
        try jws.write(self.parameters.items);
        try jws.objectField("return_type");
        try jws.write(self.return_type);
        try jws.objectField("varargs");
        try jws.write(self.varargs);
        try jws.objectField("varargs_type");
        try jws.write(self.varargs_type);
        try jws.endObject();
    }
};

pub const FunctionDeclaration = struct {
    prototype: *FunctionPrototype,
    body: *Statement,

    const Self = @This();

    pub fn init(prototype: *FunctionPrototype, body: *Statement) FunctionDeclaration {
        return FunctionDeclaration{
            .prototype = prototype,
            .body = body,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_function_declaration(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Function;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("prototype");
        try jws.write(self.prototype);
        try jws.objectField("body");
        try jws.write(self.body);
        try jws.endObject();
    }
};

pub const OperatorFunctionDeclaration = struct {
    op: Token,
    function: *FunctionDeclaration,

    const Self = @This();

    pub fn init(op: Token, function: *FunctionDeclaration) OperatorFunctionDeclaration {
        return OperatorFunctionDeclaration{
            .op = op,
            .function = function,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_operator_function_declaration(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.OperatorFunction;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("op");
        try jws.write(self.op);
        try jws.objectField("function");
        try jws.write(self.function);
        try jws.endObject();
    }
};

pub const StructDeclaration = struct {
    struct_type: *Type,

    const Self = @This();

    pub fn init(struct_type: *Type) StructDeclaration {
        return StructDeclaration{
            .struct_type = struct_type,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_struct_declaration(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Struct;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("struct_type");
        try jws.write(self.struct_type);
        try jws.endObject();
    }
};

pub const EnumDeclaration = struct {
    name: Token,
    enum_type: *Type,

    const Self = @This();

    pub fn init(name: Token, enum_type: *Type) EnumDeclaration {
        return EnumDeclaration{
            .name = name,
            .enum_type = enum_type,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_enum_declaration(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Enum;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("name");
        try jws.write(self.name);
        try jws.objectField("enum_type");
        try jws.write(self.enum_type);
        try jws.endObject();
    }
};

pub const ConditionalBlock = struct {
    position: Token,
    condition: *Expression,
    body: *Statement,

    const Self = @This();

    pub fn init(position: Token, condition: *Expression, body: *Statement) ConditionalBlock {
        return ConditionalBlock{
            .position = position,
            .condition = condition,
            .body = body,
        };
    }
};

pub const IfStatement = struct {
    conditional_blocks: std.ArrayList(*ConditionalBlock),
    has_else: bool,

    const Self = @This();

    pub fn init(conditional_blocks: std.ArrayList(*ConditionalBlock), has_else: bool) IfStatement {
        return IfStatement{
            .conditional_blocks = conditional_blocks,
            .has_else = has_else,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_if_statement(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.IfStatement;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("conditional_blocks");
        try jws.write(self.conditional_blocks.items);
        try jws.objectField("has_else");
        try jws.write(self.has_else);
        try jws.endObject();
    }
};

pub const ForRangeStatement = struct {
    position: Token,
    element_name: []const u8,
    range_start: *Expression,
    range_end: *Expression,
    step: ?*Expression,
    body: *Statement,

    const Self = @This();

    pub fn init(
        position: Token,
        element_name: []const u8,
        range_start: *Expression,
        range_end: *Expression,
        step: ?*Expression,
        body: *Statement,
    ) ForRangeStatement {
        return ForRangeStatement{
            .position = position,
            .element_name = element_name,
            .range_start = range_start,
            .range_end = range_end,
            .step = step,
            .body = body,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_for_range_statement(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.ForRange;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("element_name");
        try jws.write(self.element_name);
        try jws.objectField("range_start");
        try jws.write(self.range_start);
        try jws.objectField("range_end");
        try jws.write(self.range_end);
        try jws.objectField("step");
        try jws.write(self.step);
        try jws.objectField("body");
        try jws.write(self.body);
        try jws.endObject();
    }
};

pub const ForEachStatement = struct {
    position: Token,
    element_name: []const u8,
    index_name: []const u8,
    collection: *Expression,
    body: *Statement,

    const Self = @This();

    pub fn init(
        position: Token,
        element_name: []const u8,
        index_name: []const u8,
        collection: *Expression,
        body: *Statement,
    ) ForEachStatement {
        return ForEachStatement{
            .position = position,
            .element_name = element_name,
            .index_name = index_name,
            .collection = collection,
            .body = body,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_for_each_statement(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.ForEach;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("element_name");
        try jws.write(self.element_name);
        try jws.objectField("index_name");
        try jws.write(self.index_name);
        try jws.objectField("collection");
        try jws.write(self.collection);
        try jws.objectField("body");
        try jws.write(self.body);
        try jws.endObject();
    }
};

pub const ForEverStatement = struct {
    position: Token,
    body: *Statement,

    const Self = @This();

    pub fn init(position: Token, body: *Statement) ForEverStatement {
        return ForEverStatement{
            .position = position,
            .body = body,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_for_ever_statement(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.ForEver;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("body");
        try jws.write(self.body);
        try jws.endObject();
    }
};

pub const WhileStatement = struct {
    keyword: Token,
    condition: *Expression,
    body: *Statement,

    const Self = @This();

    pub fn init(keyword: Token, condition: *Expression, body: *Statement) WhileStatement {
        return WhileStatement{
            .keyword = keyword,
            .condition = condition,
            .body = body,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_while_statement(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.While;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("condition");
        try jws.write(self.condition);
        try jws.objectField("body");
        try jws.write(self.body);
        try jws.endObject();
    }
};

pub const SwitchCase = struct {
    position: Token,
    values: std.ArrayList(*Expression),
    body: *Statement,

    const Self = @This();

    pub fn init(position: Token, values: std.ArrayList(*Expression), body: *Statement) SwitchCase {
        return SwitchCase{
            .position = position,
            .values = values,
            .body = body,
        };
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("values");
        try jws.write(self.values.items);
        try jws.objectField("body");
        try jws.write(self.body);
        try jws.endObject();
    }
};

pub const SwitchStatement = struct {
    keyword: Token,
    argument: *Expression,
    cases: std.ArrayList(*SwitchCase),
    op: TokenKind,
    has_default_case: bool,
    should_perform_complete_check: bool,

    const Self = @This();

    pub fn init(
        keyword: Token,
        argument: *Expression,
        cases: std.ArrayList(*SwitchCase),
        op: TokenKind,
        has_default_case: bool,
        should_perform_complete_check: bool,
    ) SwitchStatement {
        return SwitchStatement{
            .keyword = keyword,
            .argument = argument,
            .cases = cases,
            .op = op,
            .has_default_case = has_default_case,
            .should_perform_complete_check = should_perform_complete_check,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_switch_statement(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.SwitchStatement;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("argument");
        try jws.write(self.argument);
        try jws.objectField("cases");
        try jws.write(self.cases.items);
        try jws.objectField("op");
        try jws.write(self.op);
        try jws.objectField("has_default_case");
        try jws.write(self.has_default_case);
        try jws.objectField("should_perform_complete_check");
        try jws.write(self.should_perform_complete_check);
        try jws.endObject();
    }
};

pub const ReturnStatement = struct {
    keyword: Token,
    value: ?*Expression,
    has_value: bool,

    const Self = @This();

    pub fn init(keyword: Token, value: ?*Expression, has_value: bool) ReturnStatement {
        return ReturnStatement{
            .keyword = keyword,
            .value = value,
            .has_value = has_value,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_return_statement(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Return;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("value");
        try jws.write(self.value);
        try jws.objectField("has_value");
        try jws.write(self.has_value);
        try jws.endObject();
    }
};

pub const DeferStatement = struct {
    call_expression: *Expression,

    const Self = @This();

    pub fn init(call_expression: *Expression) DeferStatement {
        return DeferStatement{
            .call_expression = call_expression,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_defer_statement(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Defer;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("call_expression");
        try jws.write(self.call_expression);
        try jws.endObject();
    }
};

pub const BreakStatement = struct {
    keyword: Token,
    has_times: bool,
    times: u32,

    const Self = @This();

    pub fn init(keyword: Token, has_times: bool, times: u32) BreakStatement {
        return BreakStatement{
            .keyword = keyword,
            .has_times = has_times,
            .times = times,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_break_statement(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Break;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("has_times");
        try jws.write(self.has_times);
        try jws.objectField("times");
        try jws.write(self.times);
        try jws.endObject();
    }
};

pub const ContinueStatement = struct {
    keyword: Token,
    has_times: bool,
    times: u32,

    const Self = @This();

    pub fn init(keyword: Token, has_times: bool, times: u32) ContinueStatement {
        return ContinueStatement{
            .keyword = keyword,
            .has_times = has_times,
            .times = times,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_continue_statement(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Continue;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("has_times");
        try jws.write(self.has_times);
        try jws.objectField("times");
        try jws.write(self.times);
        try jws.endObject();
    }
};

pub const ExpressionStatement = struct {
    expression: *Expression,

    const Self = @This();

    pub fn init(expression: *Expression) ExpressionStatement {
        return ExpressionStatement{
            .expression = expression,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_expression_statement(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.ExpressionStatement;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("expression");
        try jws.write(self.expression);
        try jws.endObject();
    }
};

pub const IfExpression = struct {
    tokens: std.ArrayList(Token),
    conditions: std.ArrayList(*Expression),
    values: std.ArrayList(*Expression),
    value_type: ?*Type,

    const Self = @This();

    pub fn init(
        tokens: std.ArrayList(Token),
        conditions: std.ArrayList(*Expression),
        values: std.ArrayList(*Expression),
    ) IfExpression {
        return IfExpression{
            .tokens = tokens,
            .conditions = conditions,
            .values = values,
            .value_type = @constCast(&Type.NONE_TYPE),
        };
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_if_expression(visitor.ptr, self);
    }

    pub fn isConstant(self: *const Self) bool {
        for (self.conditions.items) |condition| {
            if (!condition.isConstant()) {
                return false;
            }
        }

        for (self.values.items) |value| {
            if (!value.isConstant()) {
                return false;
            }
        }

        return true;
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.IfExpression;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("conditions");
        try jws.write(self.conditions.items);
        try jws.objectField("values");
        try jws.write(self.values.items);
        try jws.endObject();
    }
};

pub const SwitchExpression = struct {
    keyword: Token,
    argument: *Expression,
    switch_cases: std.ArrayList(*Expression),
    switch_case_values: std.ArrayList(*Expression),
    default_value: ?*Expression,
    value_type: ?*Type,
    op: TokenKind,

    const Self = @This();

    pub fn init(
        keyword: Token,
        argument: *Expression,
        switch_cases: std.ArrayList(*Expression),
        switch_case_values: std.ArrayList(*Expression),
        default_value: ?*Expression,
        op: TokenKind,
    ) SwitchExpression {
        return SwitchExpression{
            .keyword = keyword,
            .argument = argument,
            .switch_cases = switch_cases,
            .switch_case_values = switch_case_values,
            .default_value = default_value,
            .value_type = switch_case_values.items[0].getTypeNode(),
            .op = op,
        };
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_switch_expression(visitor.ptr, self);
    }

    pub fn isConstant(self: *const Self) bool {
        if (self.argument.isConstant()) {
            for (self.switch_cases.items) |condition| {
                if (!condition.isConstant()) {
                    return false;
                }
            }

            for (self.switch_case_values.items) |value| {
                if (!value.isConstant()) {
                    return false;
                }
            }

            return true;
        }
        return false;
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.SwitchExpression;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("argument");
        try jws.write(self.argument);
        try jws.objectField("switch_cases");
        try jws.write(self.switch_cases.items);
        try jws.objectField("switch_case_values");
        try jws.write(self.switch_case_values.items);
        try jws.objectField("default_value");
        try jws.write(self.default_value);
        try jws.objectField("op");
        try jws.write(self.op);
        try jws.endObject();
    }
};

pub const TupleExpression = struct {
    position: Token,
    values: std.ArrayList(*Expression),
    value_type: ?*Type,

    const Self = @This();

    pub fn init(position: Token, values: std.ArrayList(*Expression)) TupleExpression {
        return TupleExpression{
            .position = position,
            .values = values,
            .value_type = @constCast(&Type.NONE_TYPE),
        };
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_tuple_expression(visitor.ptr, self);
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Tuple;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("values");
        try jws.write(self.values.items);
        try jws.endObject();
    }
};

pub const AssignExpression = struct {
    operator_token: Token,
    left: *Expression,
    right: *Expression,
    value_type: ?*Type,

    const Self = @This();

    pub fn init(operator_token: Token, left: *Expression, right: *Expression) AssignExpression {
        return AssignExpression{
            .operator_token = operator_token,
            .left = left,
            .right = right,
            .value_type = right.getTypeNode(),
        };
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_assign_expression(visitor.ptr, self);
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return false;
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Assign;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("left");
        try jws.write(self.left);
        try jws.objectField("right");
        try jws.write(self.right);
        try jws.endObject();
    }
};

pub const BinaryExpression = struct {
    operator_token: Token,
    left: *Expression,
    right: *Expression,
    value_type: ?*Type,

    const Self = @This();

    pub fn init(operator_token: Token, left: *Expression, right: *Expression) BinaryExpression {
        return BinaryExpression{
            .operator_token = operator_token,
            .left = left,
            .right = right,
            .value_type = right.getTypeNode(),
        };
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_binary_expression(visitor.ptr, self);
    }

    pub fn isConstant(self: *const Self) bool {
        return self.left.isConstant() and self.right.isConstant();
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Binary;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("left");
        try jws.write(self.left);
        try jws.objectField("right");
        try jws.write(self.right);
        try jws.endObject();
    }
};

pub const BitwiseExpression = struct {
    operator_token: Token,
    left: *Expression,
    right: *Expression,
    value_type: ?*Type,

    const Self = @This();

    pub fn init(operator_token: Token, left: *Expression, right: *Expression) BitwiseExpression {
        return BitwiseExpression{
            .operator_token = operator_token,
            .left = left,
            .right = right,
            .value_type = right.getTypeNode(),
        };
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_bitwise_expression(visitor.ptr, self);
    }

    pub fn isConstant(self: *const Self) bool {
        return self.left.isConstant() and self.right.isConstant();
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Bitwise;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("left");
        try jws.write(self.left);
        try jws.objectField("right");
        try jws.write(self.right);
        try jws.endObject();
    }
};

pub const ComparisonExpression = struct {
    operator_token: Token,
    left: *Expression,
    right: *Expression,
    value_type: ?*Type,

    const Self = @This();

    pub fn init(operator_token: Token, left: *Expression, right: *Expression) ComparisonExpression {
        return ComparisonExpression{
            .operator_token = operator_token,
            .left = left,
            .right = right,
            .value_type = @constCast(&Type.I1_TYPE),
        };
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_comparison_expression(visitor.ptr, self);
    }

    pub fn isConstant(self: *const Self) bool {
        return self.left.isConstant() and self.right.isConstant();
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Comparison;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("left");
        try jws.write(self.left);
        try jws.objectField("right");
        try jws.write(self.right);
        try jws.endObject();
    }
};

pub const LogicalExpression = struct {
    operator_token: Token,
    left: *Expression,
    right: *Expression,
    value_type: ?*Type,

    const Self = @This();

    pub fn init(operator_token: Token, left: *Expression, right: *Expression) LogicalExpression {
        return LogicalExpression{
            .operator_token = operator_token,
            .left = left,
            .right = right,
            .value_type = @constCast(&Type.I1_TYPE),
        };
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_logical_expression(visitor.ptr, self);
    }

    pub fn isConstant(self: *const Self) bool {
        return self.left.isConstant() and self.right.isConstant();
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Logical;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("left");
        try jws.write(self.left);
        try jws.objectField("right");
        try jws.write(self.right);
        try jws.endObject();
    }
};

pub const PrefixUnaryExpression = struct {
    operator_token: Token,
    right: *Expression,
    value_type: ?*Type,

    const Self = @This();

    pub fn init(operator_token: Token, right: *Expression) PrefixUnaryExpression {
        return PrefixUnaryExpression{
            .operator_token = operator_token,
            .right = right,
            .value_type = right.getTypeNode(),
        };
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_prefix_unary_expression(visitor.ptr, self);
    }

    pub fn isConstant(self: *const Self) bool {
        return self.right.isConstant();
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.PrefixUnary;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("right");
        try jws.write(self.right);
        try jws.endObject();
    }
};

pub const PostfixUnaryExpression = struct {
    operator_token: Token,
    right: *Expression,
    value_type: ?*Type,

    const Self = @This();

    pub fn init(operator_token: Token, right: *Expression) PostfixUnaryExpression {
        return PostfixUnaryExpression{
            .operator_token = operator_token,
            .right = right,
            .value_type = right.getTypeNode(),
        };
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_postfix_unary_expression(visitor.ptr, self);
    }

    pub fn isConstant(self: *const Self) bool {
        return self.right.isConstant();
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.PostfixUnary;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("right");
        try jws.write(self.right);
        try jws.endObject();
    }
};

pub const CallExpression = struct {
    position: Token,
    callee: *Expression,
    arguments: std.ArrayList(*Expression),
    value_type: ?*Type,
    generic_arguments: std.ArrayList(*Type),

    const Self = @This();

    pub fn init(
        position: Token,
        callee: *Expression,
        arguments: std.ArrayList(*Expression),
        generic_arguments: std.ArrayList(*Type),
    ) CallExpression {
        return CallExpression{
            .position = position,
            .callee = callee,
            .arguments = arguments,
            .value_type = callee.getTypeNode(),
            .generic_arguments = generic_arguments,
        };
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_call_expression(visitor.ptr, self);
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return false;
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Call;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("callee");
        try jws.write(self.callee);
        try jws.objectField("arguments");
        try jws.write(self.arguments.items);
        try jws.objectField("generic_arguments");
        try jws.write(self.generic_arguments.items);
        try jws.endObject();
    }
};

pub const InitExpression = struct {
    position: Token,
    value_type: ?*Type,
    arguments: std.ArrayList(*Expression),

    const Self = @This();

    pub fn init(position: Token, value_type: *Type, arguments: std.ArrayList(*Expression)) InitExpression {
        return InitExpression{
            .position = position,
            .value_type = value_type,
            .arguments = arguments,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_init_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Init;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        for (self.arguments.items) |argument| {
            if (!argument.isConstant()) {
                return false;
            }
        }
        return true;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("arguments");
        try jws.write(self.arguments.items);
        try jws.endObject();
    }
};

pub const LambdaExpression = struct {
    allocator: std.mem.Allocator,
    position: Token,
    explicit_parameters: std.ArrayList(*Parameter),
    implicit_parameter_names: std.ArrayList([]const u8),
    implicit_parameter_types: std.ArrayList(*Type),
    return_type: *Type,
    body: *BlockStatement,
    lambda_type: *Type,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        position: Token,
        explicit_parameters: std.ArrayList(*Parameter),
        implicit_parameter_names: std.ArrayList([]const u8),
        implicit_parameter_types: std.ArrayList(*Type),
        return_type: *Type,
        body: *BlockStatement,
    ) LambdaExpression {
        const parameter_types = std.ArrayList(*Type).init(allocator);
        const function_type = allocator.create(Type) catch unreachable;
        function_type.* = Type{ .Function = types.FunctionType.init(
            position,
            parameter_types,
            return_type,
            false,
            null,
            false,
            false,
            std.ArrayList([]const u8).init(allocator),
        ) };
        const lambda_type = allocator.create(Type) catch unreachable;
        lambda_type.* = Type{ .Pointer = types.PointerType.init(
            function_type,
        ) };
        return LambdaExpression{
            .allocator = allocator,
            .position = position,
            .explicit_parameters = explicit_parameters,
            .implicit_parameter_names = implicit_parameter_names,
            .implicit_parameter_types = implicit_parameter_types,
            .return_type = return_type,
            .body = body,
            .lambda_type = lambda_type,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_lambda_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Lambda;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.lambda_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.lambda_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("explicit_parameters");
        try jws.write(self.explicit_parameters.items);
        try jws.objectField("implicit_parameter_names");
        try jws.write(self.implicit_parameter_names.items);
        try jws.objectField("implicit_parameter_types");
        try jws.write(self.implicit_parameter_types.items);
        try jws.objectField("return_type");
        try jws.write(self.return_type);
        try jws.objectField("body");
        try jws.write(self.body);
        try jws.endObject();
    }
};

pub const DotExpression = struct {
    dot_token: Token,
    field_name: Token,
    callee: *Expression,
    value_type: ?*Type,
    is_constant: bool = false,
    field_index: u32 = 0,

    const Self = @This();

    pub fn init(dot_token: Token, field_name: Token, callee: *Expression) DotExpression {
        return DotExpression{
            .dot_token = dot_token,
            .field_name = field_name,
            .callee = callee,
            .value_type = null,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_dot_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Dot;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        return self.is_constant;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("callee");
        try jws.write(self.callee);
        try jws.objectField("field_name");
        try jws.write(self.field_name);
        try jws.endObject();
    }
};

pub const CastExpression = struct {
    position: Token,
    value: *Expression,
    value_type: *Type,

    const Self = @This();

    pub fn init(position: Token, value: *Expression, value_type: *Type) CastExpression {
        return CastExpression{
            .position = position,
            .value = value,
            .value_type = value_type,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_cast_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Cast;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        return self.value.isConstant();
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("value");
        try jws.write(self.value);
        try jws.objectField("value_type");
        try jws.write(self.value_type);
        try jws.endObject();
    }
};

pub const TypeSizeExpression = struct {
    value_type: ?*Type,

    const Self = @This();

    pub fn init(value_type: *Type) TypeSizeExpression {
        return TypeSizeExpression{
            .value_type = value_type,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_type_size_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.TypeSize;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        _ = self;
        return @constCast(&Type.I64_TYPE);
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        _ = self;
        _ = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("value_type");
        try jws.write(self.value_type);
        try jws.endObject();
    }
};

pub const TypeAlignExpression = struct {
    value_type: ?*Type,

    const Self = @This();

    pub fn init(value_type: *Type) TypeAlignExpression {
        return TypeAlignExpression{
            .value_type = value_type,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_type_align_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.TypeAlign;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        _ = self;
        return @constCast(&Type.I64_TYPE);
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        _ = self;
        _ = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("value_type");
        try jws.write(self.value_type);
        try jws.endObject();
    }
};

pub const ValueSizeExpression = struct {
    value: *Expression,

    const Self = @This();

    pub fn init(value: *Expression) ValueSizeExpression {
        return ValueSizeExpression{
            .value = value,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_value_size_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.ValueSize;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        _ = self;
        return @constCast(&Type.I64_TYPE);
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        _ = self;
        _ = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("value");
        try jws.write(self.value);
        try jws.endObject();
    }
};

pub const IndexExpression = struct {
    position: Token,
    index: *Expression,
    value: *Expression,
    value_type: ?*Type,

    const Self = @This();

    pub fn init(position: Token, index: *Expression, value: *Expression) IndexExpression {
        return IndexExpression{
            .position = position,
            .index = index,
            .value = value,
            .value_type = @constCast(&Type.NONE_TYPE),
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_index_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Index;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        return self.index.isConstant();
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("index");
        try jws.write(self.index);
        try jws.objectField("value");
        try jws.write(self.value);
        try jws.endObject();
    }
};

pub const EnumAccessExpression = struct {
    element_name: Token,
    enum_name: Token,
    enum_element_index: u32,
    element_type: ?*Type,

    const Self = @This();

    pub fn init(element_name: Token, enum_name: Token, enum_element_index: u32, element_type: *Type) EnumAccessExpression {
        return EnumAccessExpression{
            .element_name = element_name,
            .enum_name = enum_name,
            .enum_element_index = enum_element_index,
            .element_type = element_type,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_enum_access_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.EnumElement;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.element_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.element_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("element_name");
        try jws.write(self.element_name);
        try jws.objectField("enum_name");
        try jws.write(self.enum_name);
        try jws.objectField("enum_element_index");
        try jws.write(self.enum_element_index);
        try jws.endObject();
    }
};

pub const ArrayExpression = struct {
    allocator: std.mem.Allocator,
    position: Token,
    values: std.ArrayList(*Expression),
    value_type: ?*Type,
    is_constants_array: bool,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        position: Token,
        values: std.ArrayList(*Expression),
    ) ArrayExpression {
        const size = values.items.len;
        const element_type = if (size == 0) @constCast(&Type.NONE_TYPE) else values.items[0].getTypeNode();
        const value_type = allocator.create(types.Type) catch unreachable;
        value_type.* = Type{ .StaticArray = types.StaticArrayType.init(
            element_type,
            @intCast(size),
        ) };
        var is_constants_array = true;
        for (values.items) |value| {
            if (!value.isConstant()) {
                is_constants_array = false;
                break;
            }
        }
        return ArrayExpression{
            .allocator = allocator,
            .position = position,
            .values = values,
            .value_type = value_type,
            .is_constants_array = is_constants_array,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_array_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Array;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        return self.is_constants_array;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("values");
        try jws.write(self.values.items);
        try jws.endObject();
    }
};

pub const VectorExpression = struct {
    allocator: std.mem.Allocator,
    array: *ArrayExpression,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, array: *ArrayExpression) VectorExpression {
        return VectorExpression{
            .array = array,
            .allocator = allocator,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_vector_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Vector;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        const type_ = self.array.getTypeNode();
        const ret = self.allocator.create(types.Type) catch unreachable;
        const static_array = self.allocator.create(types.StaticArrayType) catch unreachable;
        static_array.* = type_.?.StaticArray;
        ret.* = Type{ .StaticVector = types.StaticVectorType.init(static_array) };
        return ret;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.array.setTypeNode(new_type);
    }

    pub fn isConstant(self: *const Self) bool {
        return self.array.isConstant();
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("array");
        try jws.write(self.array);
        try jws.endObject();
    }
};

pub const StringExpression = struct {
    value: Token,
    value_type: ?*Type,

    const Self = @This();

    pub fn init(value: Token) StringExpression {
        return StringExpression{
            .value = value,
            .value_type = @constCast(&Type.I8_PTR_TYPE),
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_string_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.String;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("value");
        try jws.write(self.value);
        try jws.endObject();
    }
};

pub const LiteralExpression = struct {
    name: Token,
    value_type: *Type,
    constants: bool,

    const Self = @This();

    pub fn init(name: Token) LiteralExpression {
        return LiteralExpression{
            .name = name,
            .value_type = @constCast(&Type.NONE_TYPE),
            .constants = false,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_literal_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Literal;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        return self.constants;
    }

    pub fn setConstant(self: *Self, constants: bool) void {
        self.constants = constants;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("name");
        try jws.write(self.name);
        try jws.endObject();
    }
};

pub const NumberExpression = struct {
    value: Token,
    value_type: ?*Type,

    const Self = @This();

    pub fn init(value: Token, value_type: *Type) NumberExpression {
        return NumberExpression{
            .value = value,
            .value_type = value_type,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_number_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Number;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("value");
        try jws.write(self.value);
        try jws.endObject();
    }
};

pub const CharacterExpression = struct {
    value: Token,
    value_type: ?*Type,

    const Self = @This();

    pub fn init(value: Token) CharacterExpression {
        return CharacterExpression{
            .value = value,
            .value_type = @constCast(&Type.I8_TYPE),
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_character_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Character;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("value");
        try jws.write(self.value);
        try jws.endObject();
    }
};

pub const BoolExpression = struct {
    value: Token,
    value_type: ?*Type,

    const Self = @This();

    pub fn init(value: Token) BoolExpression {
        return BoolExpression{
            .value = value,
            .value_type = @constCast(&Type.I1_TYPE),
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_bool_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Bool;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("value");
        try jws.write(self.value);
        try jws.endObject();
    }
};

pub const NullExpression = struct {
    value: Token,
    value_type: *Type,
    null_base_type: *Type,

    const Self = @This();

    pub fn init(value: Token) NullExpression {
        return NullExpression{
            .value = value,
            .value_type = @constCast(&Type.NULL_TYPE),
            .null_base_type = @constCast(&Type.I32_PTR_TYPE),
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_null_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Null;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("value");
        try jws.write(self.value);
        try jws.endObject();
    }
};

pub const UndefinedExpression = struct {
    keyword: Token,
    base_type: ?*Type,

    const Self = @This();

    pub fn init(keyword: Token) UndefinedExpression {
        return UndefinedExpression{
            .keyword = keyword,
            .base_type = @constCast(&Type.NONE_TYPE),
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_undefined_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Undefined;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.base_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.base_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("keyword");
        try jws.write(self.keyword);
        try jws.endObject();
    }
};

pub const InfinityExpression = struct {
    value_type: ?*Type,

    const Self = @This();

    pub fn init(value_type: *Type) InfinityExpression {
        return InfinityExpression{
            .value_type = value_type,
        };
    }

    pub fn accept(self: *Self, visitor: anytype) Error!*Any {
        return visitor.visit_infinity_expression(visitor.ptr, self);
    }

    pub fn getAstNodeType(self: *const Self) AstNodeType {
        _ = self;
        return AstNodeType.Infinity;
    }

    pub fn getTypeNode(self: *const Self) ?*Type {
        return self.value_type;
    }

    pub fn setTypeNode(self: *Self, new_type: *Type) void {
        self.value_type = new_type;
    }

    pub fn isConstant(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn jsonStringify(self: *const Self, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("value_type");
        try jws.write(self.value_type);
        try jws.endObject();
    }
};

pub const StatementVisitor = struct {
    visit_block_statement: *const fn (*anyopaque, *BlockStatement) Error!*Any,
    visit_const_declaration: *const fn (*anyopaque, *ConstDeclaration) Error!*Any,
    visit_field_declaration: *const fn (*anyopaque, *FieldDeclaration) Error!*Any,
    visit_destructuring_declaration: *const fn (*anyopaque, *DestructuringDeclaration) Error!*Any,
    visit_function_prototype: *const fn (*anyopaque, *FunctionPrototype) Error!*Any,
    visit_intrinsic_prototype: *const fn (*anyopaque, *IntrinsicPrototype) Error!*Any,
    visit_function_declaration: *const fn (*anyopaque, *FunctionDeclaration) Error!*Any,
    visit_operator_function_declaration: *const fn (*anyopaque, *OperatorFunctionDeclaration) Error!*Any,
    visit_struct_declaration: *const fn (*anyopaque, *StructDeclaration) Error!*Any,
    visit_enum_declaration: *const fn (*anyopaque, *EnumDeclaration) Error!*Any,
    visit_if_statement: *const fn (*anyopaque, *IfStatement) Error!*Any,
    visit_switch_statement: *const fn (*anyopaque, *SwitchStatement) Error!*Any,
    visit_for_range_statement: *const fn (*anyopaque, *ForRangeStatement) Error!*Any,
    visit_for_each_statement: *const fn (*anyopaque, *ForEachStatement) Error!*Any,
    visit_for_ever_statement: *const fn (*anyopaque, *ForEverStatement) Error!*Any,
    visit_while_statement: *const fn (*anyopaque, *WhileStatement) Error!*Any,
    visit_return_statement: *const fn (*anyopaque, *ReturnStatement) Error!*Any,
    visit_defer_statement: *const fn (*anyopaque, *DeferStatement) Error!*Any,
    visit_break_statement: *const fn (*anyopaque, *BreakStatement) Error!*Any,
    visit_continue_statement: *const fn (*anyopaque, *ContinueStatement) Error!*Any,
    visit_expression_statement: *const fn (*anyopaque, *ExpressionStatement) Error!*Any,
};

pub const ExpressionVisitor = struct {
    visit_if_expression: *const fn (*anyopaque, *IfExpression) Error!*Any,
    visit_switch_expression: *const fn (*anyopaque, *SwitchExpression) Error!*Any,
    visit_tuple_expression: *const fn (*anyopaque, *TupleExpression) Error!*Any,
    visit_assign_expression: *const fn (*anyopaque, *AssignExpression) Error!*Any,
    visit_binary_expression: *const fn (*anyopaque, *BinaryExpression) Error!*Any,
    visit_bitwise_expression: *const fn (*anyopaque, *BitwiseExpression) Error!*Any,
    visit_comparison_expression: *const fn (*anyopaque, *ComparisonExpression) Error!*Any,
    visit_logical_expression: *const fn (*anyopaque, *LogicalExpression) Error!*Any,
    visit_prefix_unary_expression: *const fn (*anyopaque, *PrefixUnaryExpression) Error!*Any,
    visit_postfix_unary_expression: *const fn (*anyopaque, *PostfixUnaryExpression) Error!*Any,
    visit_call_expression: *const fn (*anyopaque, *CallExpression) Error!*Any,
    visit_init_expression: *const fn (*anyopaque, *InitExpression) Error!*Any,
    visit_lambda_expression: *const fn (*anyopaque, *LambdaExpression) Error!*Any,
    visit_dot_expression: *const fn (*anyopaque, *DotExpression) Error!*Any,
    visit_cast_expression: *const fn (*anyopaque, *CastExpression) Error!*Any,
    visit_type_size_expression: *const fn (*anyopaque, *TypeSizeExpression) Error!*Any,
    visit_type_align_expression: *const fn (*anyopaque, *TypeAlignExpression) Error!*Any,
    visit_value_size_expression: *const fn (*anyopaque, *ValueSizeExpression) Error!*Any,
    visit_index_expression: *const fn (*anyopaque, *IndexExpression) Error!*Any,
    visit_enum_access_expression: *const fn (*anyopaque, *EnumAccessExpression) Error!*Any,
    visit_array_expression: *const fn (*anyopaque, *ArrayExpression) Error!*Any,
    visit_vector_expression: *const fn (*anyopaque, *VectorExpression) Error!*Any,
    visit_string_expression: *const fn (*anyopaque, *StringExpression) Error!*Any,
    visit_literal_expression: *const fn (*anyopaque, *LiteralExpression) Error!*Any,
    visit_number_expression: *const fn (*anyopaque, *NumberExpression) Error!*Any,
    visit_character_expression: *const fn (*anyopaque, *CharacterExpression) Error!*Any,
    visit_bool_expression: *const fn (*anyopaque, *BoolExpression) Error!*Any,
    visit_null_expression: *const fn (*anyopaque, *NullExpression) Error!*Any,
    visit_undefined_expression: *const fn (*anyopaque, *UndefinedExpression) Error!*Any,
    visit_infinity_expression: *const fn (*anyopaque, *InfinityExpression) Error!*Any,
};

pub const TreeVisitor = ds.combineStruct(
    ExpressionVisitor,
    ds.combineStruct(StatementVisitor, struct { ptr: *anyopaque }),
);
