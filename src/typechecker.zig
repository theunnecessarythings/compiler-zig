const std = @import("std");
const Context = @import("parser.zig").Context;
const ScopedMap = @import("data_structures.zig").ScopedMap;
const ast = @import("ast.zig");
const types = @import("types.zig");
const Error = @import("diagnostics.zig").Error;
const ds = @import("data_structures.zig");
const tokenizer = @import("tokenizer.zig");
const log = @import("diagnostics.zig").log;

const Pair = struct {
    first: []const u8,
    second: *types.Type,
};

pub const TypeChecker = struct {
    allocator: std.mem.Allocator,
    context: *Context,
    types_table: ScopedMap(*ds.Any),
    generic_functions_declarations: std.StringArrayHashMap(*ast.FunctionDeclaration),
    generic_types: std.StringArrayHashMap(*types.Type),
    return_types_stack: std.ArrayList(*types.Type),
    is_inside_lambda_body: bool,
    lambda_implicit_parameters: std.ArrayList(std.ArrayList(*Pair)),
    visitor: *ast.TreeVisitor,

    pub fn init(allocator: std.mem.Allocator, context: *Context) !*TypeChecker {
        const self = try allocator.create(TypeChecker);
        var types_table = ScopedMap(*ds.Any).init(allocator);
        try types_table.pushNewScope();
        self.* = TypeChecker{
            .allocator = allocator,
            .context = context,
            .types_table = types_table,
            .generic_functions_declarations = std.StringArrayHashMap(*ast.FunctionDeclaration).init(allocator),
            .generic_types = std.StringArrayHashMap(*types.Type).init(allocator),
            .return_types_stack = std.ArrayList(*types.Type).init(allocator),
            .is_inside_lambda_body = false,
            .lambda_implicit_parameters = std.ArrayList(std.ArrayList(*Pair)).init(allocator),
            .visitor = undefined,
        };
        self.visitor = try self.getVisitor();
        return self;
    }

    fn getVisitor(self: *TypeChecker) !*ast.TreeVisitor {
        const ptr: *anyopaque = @ptrCast(self);
        const visit_block_statement: *const fn (*anyopaque, *ast.BlockStatement) Error!*ds.Any = @ptrCast(&visitBlockStatement);
        const visit_field_declaration: *const fn (*anyopaque, *ast.FieldDeclaration) Error!*ds.Any = @ptrCast(&visitFieldDeclaration);
        const visit_const_declaration: *const fn (*anyopaque, *ast.ConstDeclaration) Error!*ds.Any = @ptrCast(&visitConstDeclaration);
        const visit_function_prototype: *const fn (*anyopaque, *ast.FunctionPrototype) Error!*ds.Any = @ptrCast(&visitFunctionPrototype);
        const visit_intrinsic_prototype: *const fn (*anyopaque, *ast.IntrinsicPrototype) Error!*ds.Any = @ptrCast(&visitIntrinsicPrototype);
        const visit_function_declaration: *const fn (*anyopaque, *ast.FunctionDeclaration) Error!*ds.Any = @ptrCast(&visitFunctionDeclaration);
        const visit_operator_function_declaration: *const fn (*anyopaque, *ast.OperatorFunctionDeclaration) Error!*ds.Any = @ptrCast(&visitOperatorFunctionDeclaration);
        const visit_struct_declaration: *const fn (*anyopaque, *ast.StructDeclaration) Error!*ds.Any = @ptrCast(&visitStructDeclaration);
        const visit_enum_declaration: *const fn (*anyopaque, *ast.EnumDeclaration) Error!*ds.Any = @ptrCast(&visitEnumDeclaration);
        const visit_if_statement: *const fn (*anyopaque, *ast.IfStatement) Error!*ds.Any = @ptrCast(&visitIfStatement);
        const visit_for_range_statement: *const fn (*anyopaque, *ast.ForRangeStatement) Error!*ds.Any = @ptrCast(&visitForRangeStatement);
        const visit_for_each_statement: *const fn (*anyopaque, *ast.ForEachStatement) Error!*ds.Any = @ptrCast(&visitForEachStatement);
        const visit_forever_statement: *const fn (*anyopaque, *ast.ForEverStatement) Error!*ds.Any = @ptrCast(&visitForeverStatement);
        const visit_while_statement: *const fn (*anyopaque, *ast.WhileStatement) Error!*ds.Any = @ptrCast(&visitWhileStatement);
        const visit_switch_statement: *const fn (*anyopaque, *ast.SwitchStatement) Error!*ds.Any = @ptrCast(&visitSwitchStatement);
        const visit_return_statement: *const fn (*anyopaque, *ast.ReturnStatement) Error!*ds.Any = @ptrCast(&visitReturnStatement);
        const visit_expression_statement: *const fn (*anyopaque, *ast.ExpressionStatement) Error!*ds.Any = @ptrCast(&visitExpressionStatement);
        const visit_if_expression: *const fn (*anyopaque, *ast.IfExpression) Error!*ds.Any = @ptrCast(&visitIfExpression);
        const visit_switch_expression: *const fn (*anyopaque, *ast.SwitchExpression) Error!*ds.Any = @ptrCast(&visitSwitchExpression);
        const visit_tuple_expression: *const fn (*anyopaque, *ast.TupleExpression) Error!*ds.Any = @ptrCast(&visitTupleExpression);
        const visit_assign_expression: *const fn (*anyopaque, *ast.AssignExpression) Error!*ds.Any = @ptrCast(&visitAssignExpression);
        const visit_binary_expression: *const fn (*anyopaque, *ast.BinaryExpression) Error!*ds.Any = @ptrCast(&visitBinaryExpression);
        const visit_call_expression: *const fn (*anyopaque, *ast.CallExpression) Error!*ds.Any = @ptrCast(&visitCallExpression);
        const visit_index_expression: *const fn (*anyopaque, *ast.IndexExpression) Error!*ds.Any = @ptrCast(&visitIndexExpression);
        const visit_enum_access_expression: *const fn (*anyopaque, *ast.EnumAccessExpression) Error!*ds.Any = @ptrCast(&visitEnumAccessExpression);
        const visit_number_expression: *const fn (*anyopaque, *ast.NumberExpression) Error!*ds.Any = @ptrCast(&visitNumberExpression);
        const visit_string_expression: *const fn (*anyopaque, *ast.StringExpression) Error!*ds.Any = @ptrCast(&visitStringExpression);
        const visit_null_expression: *const fn (*anyopaque, *ast.NullExpression) Error!*ds.Any = @ptrCast(&visitNullExpression);
        const visit_array_expression: *const fn (*anyopaque, *ast.ArrayExpression) Error!*ds.Any = @ptrCast(&visitArrayExpression);
        const visit_lambda_expression: *const fn (*anyopaque, *ast.LambdaExpression) Error!*ds.Any = @ptrCast(&visitLambdaExpression);
        const visit_cast_expression: *const fn (*anyopaque, *ast.CastExpression) Error!*ds.Any = @ptrCast(&visitCastExpression);
        const visit_comparison_expression: *const fn (*anyopaque, *ast.ComparisonExpression) Error!*ds.Any = @ptrCast(&visitComparisonExpression);
        const visit_logical_expression: *const fn (*anyopaque, *ast.LogicalExpression) Error!*ds.Any = @ptrCast(&visitLogicalExpression);
        const visit_prefix_unary_expression: *const fn (*anyopaque, *ast.PrefixUnaryExpression) Error!*ds.Any = @ptrCast(&visitPrefixUnaryExpression);
        const visit_postfix_unary_expression: *const fn (*anyopaque, *ast.PostfixUnaryExpression) Error!*ds.Any = @ptrCast(&visitPostfixUnaryExpression);
        const visit_dot_expression: *const fn (*anyopaque, *ast.DotExpression) Error!*ds.Any = @ptrCast(&visitDotExpression);
        const visit_type_size_expression: *const fn (*anyopaque, *ast.TypeSizeExpression) Error!*ds.Any = @ptrCast(&visitTypeSizeExpression);
        const visit_type_align_expression: *const fn (*anyopaque, *ast.TypeAlignExpression) Error!*ds.Any = @ptrCast(&visitTypeAlignExpression);
        const visit_init_expression: *const fn (*anyopaque, *ast.InitExpression) Error!*ds.Any = @ptrCast(&visitInitializeExpression);
        const visit_value_size_expression: *const fn (*anyopaque, *ast.ValueSizeExpression) Error!*ds.Any = @ptrCast(&visitValueSizeExpression);
        const visit_vector_expression: *const fn (*anyopaque, *ast.VectorExpression) Error!*ds.Any = @ptrCast(&visitVectorExpression);
        const visit_literal_expression: *const fn (*anyopaque, *ast.LiteralExpression) Error!*ds.Any = @ptrCast(&visitLiteralExpression);
        const visit_character_expression: *const fn (*anyopaque, *ast.CharacterExpression) Error!*ds.Any = @ptrCast(&visitCharacterExpression);
        const visit_bool_expression: *const fn (*anyopaque, *ast.BoolExpression) Error!*ds.Any = @ptrCast(&visitBooleanExpression);
        const visit_bitwise_expression: *const fn (*anyopaque, *ast.BitwiseExpression) Error!*ds.Any = @ptrCast(&visitBitwiseExpression);
        const visit_undefined_expression: *const fn (*anyopaque, *ast.UndefinedExpression) Error!*ds.Any = @ptrCast(&visitUndefinedExpression);
        const visit_infinity_expression: *const fn (*anyopaque, *ast.InfinityExpression) Error!*ds.Any = @ptrCast(&visitInfinityExpression);
        const visit_destructuring_declaration: *const fn (*anyopaque, *ast.DestructuringDeclaration) Error!*ds.Any = @ptrCast(&visitDestructuringDeclaration);
        const visit_defer_statement: *const fn (*anyopaque, *ast.DeferStatement) Error!*ds.Any = @ptrCast(&visitDeferStatement);
        const visit_break_statement: *const fn (*anyopaque, *ast.BreakStatement) Error!*ds.Any = @ptrCast(&visitBreakStatement);
        const visit_continue_statement: *const fn (*anyopaque, *ast.ContinueStatement) Error!*ds.Any = @ptrCast(&visitContinueStatement);

        const _visitor = ast.TreeVisitor{
            .ptr = ptr,
            .visit_block_statement = visit_block_statement,
            .visit_field_declaration = visit_field_declaration,
            .visit_const_declaration = visit_const_declaration,
            .visit_function_prototype = visit_function_prototype,
            .visit_intrinsic_prototype = visit_intrinsic_prototype,
            .visit_function_declaration = visit_function_declaration,
            .visit_operator_function_declaration = visit_operator_function_declaration,
            .visit_struct_declaration = visit_struct_declaration,
            .visit_enum_declaration = visit_enum_declaration,
            .visit_if_statement = visit_if_statement,
            .visit_for_range_statement = visit_for_range_statement,
            .visit_for_each_statement = visit_for_each_statement,
            .visit_for_ever_statement = visit_forever_statement,
            .visit_while_statement = visit_while_statement,
            .visit_switch_statement = visit_switch_statement,
            .visit_return_statement = visit_return_statement,
            .visit_expression_statement = visit_expression_statement,
            .visit_if_expression = visit_if_expression,
            .visit_switch_expression = visit_switch_expression,
            .visit_tuple_expression = visit_tuple_expression,
            .visit_index_expression = visit_index_expression,
            .visit_enum_access_expression = visit_enum_access_expression,
            .visit_number_expression = visit_number_expression,
            .visit_string_expression = visit_string_expression,
            .visit_null_expression = visit_null_expression,
            .visit_array_expression = visit_array_expression,
            .visit_lambda_expression = visit_lambda_expression,
            .visit_call_expression = visit_call_expression,
            .visit_binary_expression = visit_binary_expression,
            .visit_assign_expression = visit_assign_expression,
            .visit_cast_expression = visit_cast_expression,
            .visit_comparison_expression = visit_comparison_expression,
            .visit_logical_expression = visit_logical_expression,
            .visit_prefix_unary_expression = visit_prefix_unary_expression,
            .visit_postfix_unary_expression = visit_postfix_unary_expression,
            .visit_dot_expression = visit_dot_expression,
            .visit_type_size_expression = visit_type_size_expression,
            .visit_type_align_expression = visit_type_align_expression,
            .visit_init_expression = visit_init_expression,
            .visit_value_size_expression = visit_value_size_expression,
            .visit_vector_expression = visit_vector_expression,
            .visit_literal_expression = visit_literal_expression,
            .visit_character_expression = visit_character_expression,
            .visit_bool_expression = visit_bool_expression,
            .visit_bitwise_expression = visit_bitwise_expression,
            .visit_undefined_expression = visit_undefined_expression,
            .visit_infinity_expression = visit_infinity_expression,
            .visit_destructuring_declaration = visit_destructuring_declaration,
            .visit_defer_statement = visit_defer_statement,
            .visit_break_statement = visit_break_statement,
            .visit_continue_statement = visit_continue_statement,
        };

        return try self.allocReturn(ast.TreeVisitor, _visitor);
    }

    pub fn checkCompilationUnit(self: *TypeChecker, compilation_unit: *ast.CompilationUnit) !void {
        const statements = compilation_unit.tree_nodes;
        for (statements.items) |statement| {
            _ = try statement.accept(self.visitor);
        }
    }

    pub fn pushNewScope(self: *TypeChecker) !void {
        log("Pushing new scope", .{}, .{ .module = .TypeChecker });
        try self.types_table.pushNewScope();
    }

    pub fn popCurrentScope(self: *TypeChecker) void {
        log("Popping current scope", .{}, .{ .module = .TypeChecker });
        self.types_table.popCurrentScope();
    }

    pub fn visitBlockStatement(self: *TypeChecker, node: *ast.BlockStatement) !*ds.Any {
        log("Visiting block statement", .{}, .{ .module = .TypeChecker });
        try self.pushNewScope();
        for (node.statements.items) |statement| {
            _ = try statement.accept(self.visitor);
        }
        self.popCurrentScope();
        return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
    }

    pub fn visitFieldDeclaration(self: *TypeChecker, node: *ast.FieldDeclaration) !*ds.Any {
        log("Visiting field declaration", .{}, .{ .module = .TypeChecker });
        var left_type = if (node.has_explicit_type) try self.resolveGenericType(node.field_type, null, null) else @constCast(&types.Type.NONE_TYPE);
        const right_value = node.value;
        const name = node.name.literal;

        var should_update_node_type = true;

        if (right_value != null) {
            const origin_right_value_type = right_value.?.getTypeNode();
            var right_type = self.nodeType(try right_value.?.accept(self.visitor));

            if (types.isVoidType(right_type)) {
                try self.context.diagnostics.reportError(node.name.position, "Can't declare field with void type");
                return Error.Stop;
            }
            var is_type_updated = false;
            if (origin_right_value_type != null) {
                is_type_updated = origin_right_value_type.?.typeKind() == .GenericStruct;
                if (is_type_updated) {
                    // node.field_type = origin_right_value_type.?;
                    right_type = try self.resolveGenericType(right_type, null, null);
                    node.field_type = right_type;
                    should_update_node_type = false;
                    const is_first_defined = self.types_table.define(name, try self.allocReturn(ds.Any, ds.Any{ .Type = right_type }));
                    if (!is_first_defined) {
                        try self.context.diagnostics.reportError(node.name.position, try std.fmt.allocPrint(self.allocator, "Field {s} is defined twice in the same scope", .{name}));
                        return Error.Stop;
                    }
                }
            }

            if (types.isGenericStructType(left_type)) {
                left_type = try self.resolveGenericType(left_type, null, null);
            }

            if (node.is_global and !right_value.?.isConstant()) {
                try self.context.diagnostics.reportError(node.name.position, "Initializer elemeent is not a compile-time constant");
                return Error.Stop;
            }

            const is_left_none_type = types.isNoneType(left_type);
            const is_left_ptr_type = types.isPointerType(left_type);
            const is_right_none_type = types.isNoneType(right_type);
            const is_right_null_type = types.isNullType(right_type);

            if (is_left_none_type and is_right_none_type) {
                try self.context.diagnostics.reportError(node.name.position, "Can't resolve field type rvalue is null, please add type to the variable");
                return Error.Stop;
            }

            if (is_left_none_type and is_right_null_type) {
                try self.context.diagnostics.reportError(node.name.position, "Can't resolve field type rvalue is null, please add type to the variable");
                return Error.Stop;
            }

            if (!is_left_ptr_type and is_right_null_type) {
                try self.context.diagnostics.reportError(node.name.position, "Can't declare non pointer variable with tnull value");
                return Error.Stop;
            }

            if (!is_type_updated and is_left_none_type) {
                node.field_type = right_type;
                left_type = right_type;
                is_type_updated = true;
            }

            if (!is_type_updated and is_right_none_type) {
                node.value.?.setTypeNode(left_type);
                right_type = left_type;
                is_type_updated = true;
            }

            if (is_left_ptr_type and is_right_null_type) {
                node.value.?.null_expression.null_base_type = left_type;
                is_type_updated = true;
            }

            if (!is_type_updated and !types.isTypesEquals(left_type, right_type)) {
                try self.context.diagnostics.reportError(node.name.position, try std.fmt.allocPrint(self.allocator, "Type mismatch, expected {s}, found {s}", .{ try types.getTypeLiteral(self.allocator, left_type), try types.getTypeLiteral(self.allocator, right_type) }));
                return Error.Stop;
            }
        }

        if (should_update_node_type) {
            var is_first_defined = true;
            if (left_type.typeKind() == .GenericStruct) {
                node.field_type = left_type;
                const resolved_type = try self.resolveGenericType(left_type, null, null);
                is_first_defined = self.types_table.define(name, try self.allocReturn(ds.Any, ds.Any{ .Type = resolved_type }));
            } else {
                is_first_defined = self.types_table.define(name, try self.allocReturn(ds.Any, ds.Any{ .Type = left_type }));
            }

            if (!is_first_defined) {
                try self.context.diagnostics.reportError(node.name.position, try std.fmt.allocPrint(self.allocator, "Field {s} is defined twice in the same scope", .{name}));
                return Error.Stop;
            }
        }
        return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
    }

    pub fn visitConstDeclaration(self: *TypeChecker, node: *ast.ConstDeclaration) !*ds.Any {
        log("Visiting const declaration", .{}, .{ .module = .TypeChecker });
        const name = node.name.literal;
        const type_ = try node.value.accept(self.visitor);
        const is_first_defined = self.types_table.define(name, type_);
        if (!is_first_defined) {
            try self.context.diagnostics.reportError(node.name.position, try std.fmt.allocPrint(self.allocator, "Field {s} is defined twice in the same scope", .{name}));
            return Error.Stop;
        }
        return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
    }

    pub fn visitFunctionPrototype(self: *TypeChecker, node: *ast.FunctionPrototype) !*ds.Any {
        log("Visiting function prototype", .{}, .{ .module = .TypeChecker });
        const name = node.name;
        var parameters = std.ArrayList(*types.Type).init(self.allocator);
        try parameters.ensureTotalCapacity(node.parameters.items.len);

        for (node.parameters.items) |parameter| {
            try parameters.append(parameter.parameter_type);
        }

        const return_type = node.return_type;
        const function_type = try self.allocReturn(types.Type, types.Type{ .Function = types.FunctionType.init(
            name,
            parameters,
            return_type.?,
            node.has_varargs,
            node.varargs_type,
            false,
            false,
            std.ArrayList([]const u8).init(self.allocator),
        ) });
        const function_type_any = try self.allocReturn(ds.Any, ds.Any{ .Type = function_type });

        const is_first_defined = self.types_table.define(name.literal, function_type_any);
        if (!is_first_defined) {
            try self.context.diagnostics.reportError(name.position, try std.fmt.allocPrint(self.allocator, "Function {s} is defined twice in the same scope", .{name.literal}));
            return Error.Stop;
        }
        return function_type_any;
    }

    pub fn visitIntrinsicPrototype(self: *TypeChecker, node: *ast.IntrinsicPrototype) !*ds.Any {
        log("Visiting intrinsic prototype", .{}, .{ .module = .TypeChecker });
        const name = node.name;
        var parameters = std.ArrayList(*types.Type).init(self.allocator);

        for (node.parameters.items) |parameter| {
            try parameters.append(parameter.parameter_type);
        }

        const return_type = node.return_type;
        const function_type = try self.allocReturn(types.Type, types.Type{ .Function = types.FunctionType.init(
            name,
            parameters,
            return_type.?,
            node.varargs,
            node.varargs_type,
            true,
            false,
            std.ArrayList([]const u8).init(self.allocator),
        ) });

        const function_type_any = try self.allocReturn(ds.Any, ds.Any{ .Type = function_type });
        const is_first_defined = self.types_table.define(name.literal, function_type_any);
        if (!is_first_defined) {
            try self.context.diagnostics.reportError(name.position, "Intrinsic function is defined twice in the same scope");
            return Error.Stop;
        }
        return function_type_any;
    }

    pub fn visitFunctionDeclaration(self: *TypeChecker, node: *ast.FunctionDeclaration) !*ds.Any {
        log("Visiting function declaration, node: {any}", .{node}, .{ .module = .TypeChecker });
        const prototype = node.prototype;
        if (prototype.is_generic) {
            try self.generic_functions_declarations.put(prototype.name.literal, node);
            return try self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
        }

        const function_type = self.nodeType(try node.prototype.accept(self.visitor));
        const function = function_type.Function;
        try self.return_types_stack.append(function.return_type);

        try self.pushNewScope();
        for (prototype.parameters.items) |parameter| {
            const parameter_type = try self.allocReturn(ds.Any, ds.Any{ .Type = parameter.parameter_type });
            _ = self.types_table.define(parameter.name.literal, parameter_type);
        }

        const function_body = node.body;
        _ = try function_body.accept(self.visitor);
        self.popCurrentScope();

        _ = self.return_types_stack.pop();

        if (!types.isVoidType(function.return_type) and !self.checkMissingReturnStatement(function_body)) {
            try self.context.diagnostics.reportError(node.prototype.name.position, "A 'return' statement required in a function with a block body ('{...}')");
            return Error.Stop;
        }

        return try self.allocReturn(ds.Any, ds.Any{ .Type = function_type });
    }

    pub fn visitOperatorFunctionDeclaration(self: *TypeChecker, node: *ast.OperatorFunctionDeclaration) !*ds.Any {
        log("Visiting operator function declaration", .{}, .{ .module = .TypeChecker });
        const prototype = node.function.prototype;
        const parameters = prototype.parameters;

        var has_non_primitive_parameter = false;
        for (parameters.items) |parameter| {
            const type_ = parameter.parameter_type;
            if (!(types.isNumberType(type_) or types.isEnumElementType(type_))) {
                has_non_primitive_parameter = true;
                break;
            }
        }

        if (!has_non_primitive_parameter) {
            try self.context.diagnostics.reportError(node.op.position, "overloaded operator must have at least one parameter of struct, tuple, array, enum");
            return Error.Stop;
        }

        return node.function.accept(self.visitor);
    }

    pub fn visitStructDeclaration(self: *TypeChecker, node: *ast.StructDeclaration) !*ds.Any {
        log("Visiting struct declaration", .{}, .{ .module = .TypeChecker });
        const struct_type = node.struct_type;
        if (!struct_type.Struct.is_generic) {
            const struct_name = struct_type.Struct.name;
            const struct_type_any = try self.allocReturn(ds.Any, ds.Any{ .Type = struct_type });
            _ = self.types_table.define(struct_name, struct_type_any);
        }
        return self.allocReturn(ds.Any, .Null);
    }

    pub fn visitEnumDeclaration(self: *TypeChecker, node: *ast.EnumDeclaration) !*ds.Any {
        log("Visiting enum declaration", .{}, .{ .module = .TypeChecker });
        const name = node.name.literal;
        const enum_type = node.enum_type.Enum;
        const enum_element_type = enum_type.element_type.?;
        if (!types.isIntegerType(enum_element_type)) {
            try self.context.diagnostics.reportError(node.name.position, "Enum element type must be a integer type");
            return Error.Stop;
        }

        const element_size = enum_type.values.count();
        if (element_size > 2 and types.isBooleanType(enum_element_type)) {
            try self.context.diagnostics.reportError(node.name.position, "Enum with bool (int1) type can't has more than 2 elements");
            return Error.Stop;
        }

        const is_first_defined = self.types_table.define(name, try self.allocReturn(ds.Any, ds.Any{ .Type = node.enum_type }));
        if (!is_first_defined) {
            try self.context.diagnostics.reportError(node.name.position, try std.fmt.allocPrint(self.allocator, "enumeration {s} is defined twice in the same scope", .{name}));
            return Error.Stop;
        }
        return self.allocReturn(ds.Any, ds.Any{ .Bool = is_first_defined });
    }

    pub fn visitIfStatement(self: *TypeChecker, node: *ast.IfStatement) !*ds.Any {
        log("Visiting if statement", .{}, .{ .module = .TypeChecker });
        for (node.conditional_blocks.items) |conditional_block| {
            const condition = self.nodeType(try conditional_block.condition.accept(self.visitor));
            if (!types.isNumberType(condition)) {
                try self.context.diagnostics.reportError(conditional_block.position.position, try std.fmt.allocPrint(self.allocator, "if condition mush be a number but got {s}", .{try types.getTypeLiteral(self.allocator, condition)}));
                return Error.Stop;
            }
            try self.pushNewScope();
            _ = try conditional_block.body.accept(self.visitor);
            self.popCurrentScope();
        }
        return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
    }

    pub fn visitForRangeStatement(self: *TypeChecker, node: *ast.ForRangeStatement) !*ds.Any {
        log("Visiting for range statement", .{}, .{ .module = .TypeChecker });
        const start_type = self.nodeType(try node.range_start.accept(self.visitor));
        const end_type = self.nodeType(try node.range_end.accept(self.visitor));

        if (types.isNumberType(start_type) and types.isTypesEquals(start_type, end_type)) {
            if (node.step) |step| {
                const step_type = self.nodeType(try step.accept(self.visitor));
                if (!types.isTypesEquals(step_type, start_type)) {
                    try self.context.diagnostics.reportError(node.position.position, "For range step type must be the same as start and end type");
                    return Error.Stop;
                }
            }

            try self.pushNewScope();
            _ = self.types_table.define(node.element_name, try self.allocReturn(ds.Any, ds.Any{ .Type = start_type }));
            _ = try node.body.accept(self.visitor);
            self.popCurrentScope();
            return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
        }

        try self.context.diagnostics.reportError(node.position.position, "For range start and end types must be integers");
        return Error.Stop;
    }

    pub fn visitForEachStatement(self: *TypeChecker, node: *ast.ForEachStatement) !*ds.Any {
        log("Visiting for each statement", .{}, .{ .module = .TypeChecker });
        const collection_type = self.nodeType(try node.collection.accept(self.visitor));
        const is_array_type = collection_type.typeKind() == .StaticArray;
        const is_string_type = types.isPointerOfType(collection_type, @constCast(&types.Type.I8_TYPE));
        const is_vector_type = collection_type.typeKind() == types.TypeKind.StaticVector;

        if (!is_array_type and !is_string_type and !is_vector_type) {
            try self.context.diagnostics.reportError(node.position.position, "For each expect array or string as paramter");
            return Error.Stop;
        }

        try self.pushNewScope();

        if (!std.mem.eql(u8, node.element_name, "_")) {
            if (is_array_type) {
                const array_type = collection_type.StaticArray;
                _ = self.types_table.define(node.element_name, try self.allocReturn(ds.Any, ds.Any{ .Type = array_type.element_type.? }));
            } else if (is_vector_type) {
                const vector_type = collection_type.StaticVector;
                _ = self.types_table.define(node.element_name, try self.allocReturn(ds.Any, ds.Any{ .Type = vector_type.array.element_type.? }));
            } else {
                _ = self.types_table.define(node.element_name, try self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I8_TYPE) }));
            }
        }

        if (!std.mem.eql(u8, node.index_name, "_")) {
            _ = self.types_table.define(node.index_name, try self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I64_TYPE) }));
        }

        _ = try node.body.accept(self.visitor);

        self.popCurrentScope();
        return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
    }

    pub fn visitForeverStatement(self: *TypeChecker, node: *ast.ForEverStatement) !*ds.Any {
        log("Visiting forever statement", .{}, .{ .module = .TypeChecker });
        try self.pushNewScope();
        _ = try node.body.accept(self.visitor);
        self.popCurrentScope();
        return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
    }

    pub fn visitWhileStatement(self: *TypeChecker, node: *ast.WhileStatement) !*ds.Any {
        log("Visiting while statement", .{}, .{ .module = .TypeChecker });
        const left_type = self.nodeType(try node.condition.accept(self.visitor));
        if (!types.isNumberType(left_type)) {
            try self.context.diagnostics.reportError(node.keyword.position, try std.fmt.allocPrint(self.allocator, "While condition mush be a number but got {s}", .{try types.getTypeLiteral(self.allocator, left_type)}));
            return Error.Stop;
        }
        try self.pushNewScope();
        _ = try node.body.accept(self.visitor);
        self.popCurrentScope();
        return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
    }

    pub fn visitSwitchStatement(self: *TypeChecker, node: *ast.SwitchStatement) !*ds.Any {
        log("Visiting switch statement", .{}, .{ .module = .TypeChecker });
        const argument = self.nodeType(try node.argument.accept(self.visitor));
        const position = node.keyword.position;

        const is_argment_enum_type = types.isEnumElementType(argument);
        const is_argument_num_type = types.isIntegerType(argument);
        if (!is_argument_num_type and !is_argment_enum_type) {
            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Switch argument type must be integer or enum element but found {s}", .{try types.getTypeLiteral(self.allocator, argument)}));
            return Error.Stop;
        }

        var cases_values = std.StringArrayHashMap(void).init(self.allocator);

        var case_index: u32 = 0;
        const cases_count = node.cases.items.len;

        for (node.cases.items) |branch| {
            const values = branch.values;
            const branch_position = branch.position.position;

            if (!node.has_default_case or (case_index != (cases_count - 1))) {
                for (values.items) |value| {
                    const value_node_type = value.getAstNodeType();
                    if (value_node_type == ast.AstNodeType.EnumElement) {
                        if (is_argment_enum_type) {
                            const enum_access = value.enum_access_expression;
                            const enum_element = argument.EnumElement;
                            if (!std.mem.eql(u8, enum_access.enum_name.literal, enum_element.enum_name)) {
                                try self.context.diagnostics.reportError(branch_position, try std.fmt.allocPrint(self.allocator, "Switch argument and case are elements of different enums {s} and {s}", .{ enum_element.enum_name, enum_access.enum_name.literal }));
                                return Error.Stop;
                            }

                            const enum_index_string = try std.fmt.allocPrint(self.allocator, "{d}", .{enum_access.enum_element_index});
                            if ((try cases_values.getOrPut(enum_index_string)).found_existing) {
                                try self.context.diagnostics.reportError(branch_position, "Switch can't has more than case with the same constants value");
                                return Error.Stop;
                            }

                            continue;
                        }

                        try self.context.diagnostics.reportError(branch_position, "Switch argument is enum type and expect all cases to be the same type");
                        return Error.Stop;
                    }

                    if (value_node_type == ast.AstNodeType.Number) {
                        if (is_argument_num_type) {
                            const value_type = self.nodeType(try value.accept(self.visitor));
                            if (!types.isNumberType(value_type)) {
                                try self.context.diagnostics.reportError(branch_position, try std.fmt.allocPrint(self.allocator, "Switch case value must be an integer but found {s}", .{try types.getTypeLiteral(self.allocator, value_type)}));
                                return Error.Stop;
                            }

                            const number = value.number_expression;
                            if ((try cases_values.getOrPut(number.value.literal)).found_existing) {
                                try self.context.diagnostics.reportError(branch_position, "Switch can't has more than case with the same constants value");
                                return Error.Stop;
                            }

                            continue;
                        }

                        try self.context.diagnostics.reportError(branch_position, "Switch argument is integer type and expect all cases to be the same type");
                        return Error.Stop;
                    }

                    try self.context.diagnostics.reportError(branch_position, "Switch case type must be integer or enum element");
                    return Error.Stop;
                }
            }

            try self.pushNewScope();
            _ = try branch.body.accept(self.visitor);
            self.popCurrentScope();

            case_index += 1;
        }

        if (node.should_perform_complete_check and types.isEnumElementType(argument)) {
            const enum_element = argument.EnumElement;
            const enum_name = enum_element.enum_name;
            _ = enum_name;
            const enum_type = self.context.enumerations.get(enum_element.enum_name).?;
            try self.checkCompleteSwitchCases(enum_type, cases_values, node.has_default_case, position);
        }

        return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
    }

    pub fn visitReturnStatement(self: *TypeChecker, node: *ast.ReturnStatement) !*ds.Any {
        log("Visiting return statement", .{}, .{ .module = .TypeChecker });
        if (!node.has_value) {
            if (self.return_types_stack.getLast().typeKind() != .Void) {
                try self.context.diagnostics.reportError(node.keyword.position, try std.fmt.allocPrint(self.allocator, "Expect return value to be {s} but got void", .{try types.getTypeLiteral(self.allocator, self.return_types_stack.getLast())}));
                return Error.Stop;
            }
            return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
        }

        // This is wrong, if the return type is generic, we cannot resolve it here
        const return_type = self.nodeType(try node.value.?.accept(self.visitor));
        const function_return_type = try self.resolveGenericType(self.return_types_stack.getLast(), null, null);

        if (!types.isTypesEquals(function_return_type, return_type)) {
            if (types.isPointerType(function_return_type) and types.isNullType(return_type)) {
                node.value.?.null_expression.null_base_type = function_return_type;
                return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
            }

            if (!types.isPointerType(function_return_type) and types.isNullType(return_type)) {
                try self.context.diagnostics.reportError(node.keyword.position, "Can't return null from function that return non pointer type");
                return Error.Stop;
            }

            if (types.isFunctionPointerType(function_return_type) and types.isFunctionPointerType(return_type)) {
                const expected_fun_ptr_type = function_return_type.Pointer;
                const expected_fun_type = expected_fun_ptr_type.base_type.Function;

                const return_fun_ptr = return_type.Pointer;
                const return_fun = return_fun_ptr.base_type.Function;

                if (expected_fun_type.implicit_parameters_count != return_fun.implicit_parameters_count) {
                    try self.context.diagnostics.reportError(node.keyword.position, "Can't return lambda that implicit capture values from function");
                    return Error.Stop;
                }
            }

            try self.context.diagnostics.reportError(node.keyword.position, try std.fmt.allocPrint(self.allocator, "Expect return value to be {s} but got {s}", .{ try types.getTypeLiteral(self.allocator, function_return_type), try types.getTypeLiteral(self.allocator, return_type) }));
            return Error.Stop;
        }

        return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
    }

    pub fn visitDestructuringDeclaration(self: *TypeChecker, node: *ast.DestructuringDeclaration) !*ds.Any {
        log("Visiting destructuring declaration", .{}, .{ .module = .TypeChecker });
        const position = node.equal_token.position;

        if (node.is_global) {
            try self.context.diagnostics.reportError(position, "Can't declare destructuring declaration in global scope");
            return Error.Stop;
        }

        const value = self.nodeType(try node.value.accept(self.visitor));
        if (!types.isTupleType(value)) {
            try self.context.diagnostics.reportError(position, "Destructuring declaration expect tuple type");
            return Error.Stop;
        }

        const tuple_value = value.Tuple;
        const tuple_field_types = tuple_value.field_types;
        const tuple_size = tuple_field_types.items.len;

        if (tuple_field_types.items.len != node.names.items.len) {
            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Number of fields must be equal to tuple size, expected {d} but got {d}", .{ tuple_field_types.items.len, node.names.items.len }));
            return Error.Stop;
        }

        for (0..tuple_size) |i| {
            if (types.isNoneType(node.value_types.items[i])) {
                node.value_types.items[i] = try self.resolveGenericType(tuple_field_types.items[i], null, null);
            } else if (!types.isTypesEquals(node.value_types.items[i], tuple_field_types.items[i])) {
                try self.context.diagnostics.reportError(node.names.items[i].position, "Field type must be equal to tuple element type");
                return Error.Stop;
            }

            const is_first_defined = self.types_table.define(node.names.items[i].literal, try self.allocReturn(ds.Any, ds.Any{ .Type = node.value_types.items[i] }));
            if (!is_first_defined) {
                try self.context.diagnostics.reportError(node.names.items[i].position, try std.fmt.allocPrint(self.allocator, "Field {s} is defined twice in the same scope", .{node.names.items[i].literal}));
                return Error.Stop;
            }
        }
        return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
    }

    pub fn visitDeferStatement(self: *TypeChecker, node: *ast.DeferStatement) !*ds.Any {
        log("Visiting defer statement", .{}, .{ .module = .TypeChecker });
        _ = try node.call_expression.accept(self.visitor);
        return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
    }

    pub fn visitBreakStatement(self: *TypeChecker, node: *ast.BreakStatement) !*ds.Any {
        log("Visiting break statement", .{}, .{ .module = .TypeChecker });
        if (node.has_times and node.times == 1) {
            try self.context.diagnostics.reportWarning(node.keyword.position, "`break 1;` can implicity written as `break;`");
        }
        return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
    }

    pub fn visitContinueStatement(self: *TypeChecker, node: *ast.ContinueStatement) !*ds.Any {
        log("Visiting continue statement", .{}, .{ .module = .TypeChecker });
        if (node.has_times and node.times == 1) {
            try self.context.diagnostics.reportWarning(node.keyword.position, "`continue 1;` can implicity written as `continue;`");
        }
        return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
    }

    pub fn visitExpressionStatement(self: *TypeChecker, node: *ast.ExpressionStatement) !*ds.Any {
        log("Visiting expression statement", .{}, .{ .module = .TypeChecker });
        return try node.expression.accept(self.visitor);
    }

    pub fn visitIfExpression(self: *TypeChecker, node: *ast.IfExpression) !*ds.Any {
        log("Visiting if expression", .{}, .{ .module = .TypeChecker });
        const branches_count = node.tokens.items.len;
        var node_type = @constCast(&types.Type.NONE_TYPE);

        for (0..branches_count) |i| {
            const condition = node.conditions.items[i];
            const condition_type = self.nodeType(try condition.accept(self.visitor));
            if (!types.isNumberType(condition_type)) {
                try self.context.diagnostics.reportError(node.tokens.items[i].position, try std.fmt.allocPrint(self.allocator, "If Expression condition mush be a number but got {s}", .{try types.getTypeLiteral(self.allocator, condition_type)}));
                return Error.Stop;
            }

            const value = self.nodeType(try node.values.items[i].accept(self.visitor));
            if (i == 0) {
                node_type = value;
                continue;
            }

            if (!types.isTypesEquals(node_type, value)) {
                try self.context.diagnostics.reportError(node.tokens.items[i].position, try std.fmt.allocPrint(self.allocator, "If Expression Type missmatch expect {s} but got {s}", .{ try types.getTypeLiteral(self.allocator, node_type), try types.getTypeLiteral(self.allocator, value) }));
                return Error.Stop;
            }
        }

        node.setTypeNode(node_type);
        return self.allocReturn(ds.Any, ds.Any{ .Type = node_type });
    }

    pub fn visitSwitchExpression(self: *TypeChecker, node: *ast.SwitchExpression) !*ds.Any {
        log("Visiting switch expression", .{}, .{ .module = .TypeChecker });
        const argument = self.nodeType(try node.argument.accept(self.visitor));
        const position = node.keyword.position;

        const cases = node.switch_cases;
        const cases_size = cases.items.len;

        for (cases.items) |case_expression| {
            const case_type = self.nodeType(try case_expression.accept(self.visitor));
            if (!types.isTypesEquals(argument, case_type)) {
                try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Switch case type must be the same type of argument type {s} but got {s}", .{ try types.getTypeLiteral(self.allocator, argument), try types.getTypeLiteral(self.allocator, case_type) }));
                return Error.Stop;
            }
        }

        const values = node.switch_case_values;
        const expected_type = self.nodeType(try values.items[0].accept(self.visitor));
        for (1..cases_size) |i| {
            const case_value = values.items[i];
            const case_value_type = self.nodeType(try case_value.accept(self.visitor));
            if (!types.isTypesEquals(expected_type, case_value_type)) {
                try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Switch cases must be the same time but got {s} and {s}", .{ try types.getTypeLiteral(self.allocator, expected_type), try types.getTypeLiteral(self.allocator, case_value_type) }));
                return Error.Stop;
            }
        }

        var has_else_branch = false;
        const else_value = node.default_value;
        if (else_value != null) {
            const default_value_type = self.nodeType(try else_value.?.accept(self.visitor));
            has_else_branch = true;
            if (!types.isTypesEquals(expected_type, default_value_type)) {
                try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Switch case default values must be the same type of other cases expect {s} but got {s}", .{ try types.getTypeLiteral(self.allocator, expected_type), try types.getTypeLiteral(self.allocator, default_value_type) }));
                return Error.Stop;
            }
        }

        if (!has_else_branch) {
            if (types.isEnumElementType(argument)) {
                const enum_element = argument.EnumElement;
                const enum_name = enum_element.enum_name;
                const enum_type = self.context.enumerations.get(enum_name).?;
                const enum_values = enum_type.values;
                const cases_count = cases.items.len;
                if (enum_values.count() > cases_count) {
                    try self.context.diagnostics.reportError(position, "Switch is incomplete and must has else branch");
                    return Error.Stop;
                }
            } else {
                try self.context.diagnostics.reportError(position, "Switch is incomplete and must has else branch");
                return Error.Stop;
            }
        }

        node.setTypeNode(expected_type);
        return self.allocReturn(ds.Any, ds.Any{ .Type = expected_type });
    }

    pub fn visitTupleExpression(self: *TypeChecker, node: *ast.TupleExpression) !*ds.Any {
        log("Visiting tuple expression", .{}, .{ .module = .TypeChecker });
        var field_types = std.ArrayList(*types.Type).init(self.allocator);

        for (node.values.items) |value| {
            try field_types.append(self.nodeType(try value.accept(self.visitor)));
        }

        var tuple_type = types.TupleType.init("", field_types);
        tuple_type.name = try std.fmt.allocPrint(self.allocator, "_tuple_{s}", .{try types.mangleTypes(self.allocator, field_types.items)});
        const type_ = try self.allocReturn(types.Type, types.Type{ .Tuple = tuple_type });
        node.setTypeNode(type_);
        return self.allocReturn(ds.Any, ds.Any{ .Type = type_ });
    }

    pub fn visitAssignExpression(self: *TypeChecker, node: *ast.AssignExpression) !*ds.Any {
        log("Visiting assign expression", .{}, .{ .module = .TypeChecker });
        const left_node = node.left;
        const left_type = self.nodeType(try left_node.accept(self.visitor));

        try self.checkValidAssignmentRightSide(left_node, node.operator_token.position);

        const right_type = self.nodeType(try node.right.accept(self.visitor));

        if (types.isPointerType(left_type) and types.isNullType(right_type)) {
            node.right.null_expression.null_base_type = left_type;
            return self.allocReturn(ds.Any, ds.Any{ .Type = left_type });
        }

        if (!types.isTypesEquals(left_type, right_type)) {
            try self.context.diagnostics.reportError(node.operator_token.position, try std.fmt.allocPrint(self.allocator, "Type missmatch expect {s} but got {s}", .{ try types.getTypeLiteral(self.allocator, left_type), try types.getTypeLiteral(self.allocator, right_type) }));
            return Error.Stop;
        }

        return self.allocReturn(ds.Any, ds.Any{ .Type = right_type });
    }

    pub fn visitBinaryExpression(self: *TypeChecker, node: *ast.BinaryExpression) !*ds.Any {
        log("Visiting binary expression", .{}, .{ .module = .TypeChecker });
        const lhs = self.nodeType(try node.left.accept(self.visitor));
        const rhs = self.nodeType(try node.right.accept(self.visitor));
        const op = node.operator_token;
        const position = op.position;

        if (types.isNumberType(lhs) and types.isNumberType(rhs)) {
            if (types.isTypesEquals(lhs, rhs)) {
                return self.allocReturn(ds.Any, ds.Any{ .Type = lhs });
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Expect numbers types to be the same size but got {s} and {s}", .{ try types.getTypeLiteral(self.allocator, lhs), try types.getTypeLiteral(self.allocator, rhs) }));
            return Error.Stop;
        }

        if (types.isVectorType(lhs) and types.isVectorType(rhs)) {
            if (types.isTypesEquals(lhs, rhs)) {
                node.setTypeNode(lhs);
                return self.allocReturn(ds.Any, ds.Any{ .Type = lhs });
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Expect vector types to be the same size and type but got {s} and {s}", .{ try types.getTypeLiteral(self.allocator, lhs), try types.getTypeLiteral(self.allocator, rhs) }));
            return Error.Stop;
        }
        var parameters = [2]*types.Type{ lhs, rhs };
        const function_name = try types.mangleOperatorFunction(self.allocator, op.kind, &parameters);
        if (self.types_table.isDefined(function_name)) {
            const function = self.types_table.lookup(function_name).?;
            const type_ = self.nodeType(function);
            std.debug.assert(type_.typeKind() == .Function);
            const function_type = type_.Function;
            return self.allocReturn(ds.Any, ds.Any{ .Type = function_type.return_type });
        }

        const op_literal = try tokenizer.overloadingOperatorLiteral(op.kind);
        const lhs_str = try types.getTypeLiteral(self.allocator, lhs);
        const rhs_str = try types.getTypeLiteral(self.allocator, rhs);
        const prototype = try std.fmt.allocPrint(self.allocator, "operator {s}({s}, {s})", .{ op_literal, lhs_str, rhs_str });
        try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Can't find operator overloading {s}, {any}, {any}", .{ prototype, lhs, rhs }));
        return Error.Stop;
    }

    pub fn visitBitwiseExpression(self: *TypeChecker, node: *ast.BitwiseExpression) !*ds.Any {
        log("Visiting bitwise expression", .{}, .{ .module = .TypeChecker });
        const lhs = self.nodeType(try node.left.accept(self.visitor));
        const rhs = self.nodeType(try node.right.accept(self.visitor));
        const op = node.operator_token;
        const position = op.position;

        if (types.isNumberType(lhs) and types.isNumberType(rhs)) {
            if (types.isTypesEquals(lhs, rhs)) {
                const right = node.right;
                const right_node_type = right.getAstNodeType();

                if (op.kind == .RightShift or op.kind == .LeftShift) {
                    if (right_node_type == .Number) {
                        const crhs = right.number_expression;
                        const str_value = crhs.value.literal;
                        const num = try std.fmt.parseInt(i64, str_value, 10);
                        const number_kind = lhs.Number.number_kind;
                        const first_operand_width = types.numberKindWidth(number_kind);
                        if (num >= first_operand_width) {
                            try self.context.diagnostics.reportError(node.operator_token.position, try std.fmt.allocPrint(self.allocator, "Shift Expressions second operand can't be bigger than or equal first operand bit width {d}", .{first_operand_width}));
                            return Error.Stop;
                        }
                    }

                    if (right_node_type == .PrefixUnary) {
                        const unary = right.prefix_unary_expression;
                        if (unary.operator_token.kind == .Minus and unary.right.getAstNodeType() == .Number) {
                            try self.context.diagnostics.reportError(node.operator_token.position, "Shift Expressions second operand can't be a negative number");
                            return Error.Stop;
                        }
                    }
                }
                return self.allocReturn(ds.Any, ds.Any{ .Type = lhs });
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Expect numbers types to be the same size but got {s} and {s}", .{ try types.getTypeLiteral(self.allocator, lhs), try types.getTypeLiteral(self.allocator, rhs) }));
            return Error.Stop;
        }

        if (types.isVectorType(lhs) and types.isVectorType(rhs)) {
            if (types.isTypesEquals(lhs, rhs)) {
                node.setTypeNode(lhs);
                return self.allocReturn(ds.Any, ds.Any{ .Type = lhs });
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Expect vector types to be the same size and type but got {s} and {s}", .{ try types.getTypeLiteral(self.allocator, lhs), try types.getTypeLiteral(self.allocator, rhs) }));
            return Error.Stop;
        }

        var types_ = [2]*types.Type{ lhs, rhs };
        const function_name = try types.mangleOperatorFunction(self.allocator, op.kind, &types_);
        if (self.types_table.isDefined(function_name)) {
            const function = self.types_table.lookup(function_name).?;
            const type_ = self.nodeType(function);
            std.debug.assert(type_.typeKind() == .Function);
            const function_type = type_.Function;
            return self.allocReturn(ds.Any, ds.Any{ .Type = function_type.return_type });
        }

        const op_literal = try tokenizer.overloadingOperatorLiteral(op.kind);
        const lhs_str = try types.getTypeLiteral(self.allocator, lhs);
        const rhs_str = try types.getTypeLiteral(self.allocator, rhs);
        try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Can't find operator overloading operator {s}({s}, {s})", .{ op_literal, lhs_str, rhs_str }));
        return Error.Stop;
    }

    pub fn visitComparisonExpression(self: *TypeChecker, node: *ast.ComparisonExpression) !*ds.Any {
        log("Visiting comparison expression", .{}, .{ .module = .TypeChecker });
        const lhs = self.nodeType(try node.left.accept(self.visitor));
        const rhs = self.nodeType(try node.right.accept(self.visitor));
        const are_types_equals = types.isTypesEquals(lhs, rhs);
        const op = node.operator_token;
        const position = op.position;

        if (types.isNumberType(lhs) and types.isNumberType(rhs)) {
            if (are_types_equals) {
                return self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I1_TYPE) });
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Expect numbers types to be the same size but got {s} and {s}", .{ try types.getTypeLiteral(self.allocator, lhs), try types.getTypeLiteral(self.allocator, rhs) }));
            return Error.Stop;
        }

        if (types.isEnumElementType(lhs) and types.isEnumElementType(rhs)) {
            if (are_types_equals) {
                return self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I1_TYPE) });
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "You can't compare elements from different enums {s} and {s}", .{ try types.getTypeLiteral(self.allocator, lhs), try types.getTypeLiteral(self.allocator, rhs) }));
            return Error.Stop;
        }

        if (types.isPointerType(lhs) and types.isPointerType(rhs)) {
            if (are_types_equals) {
                return self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I1_TYPE) });
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "You can't compare pointers to different types {s} and {s}", .{ try types.getTypeLiteral(self.allocator, lhs), try types.getTypeLiteral(self.allocator, rhs) }));
            return Error.Stop;
        }

        if (types.isPointerType(lhs) and types.isNullType(rhs)) {
            node.right.null_expression.null_base_type = lhs;
            return self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I1_TYPE) });
        }

        if (types.isNullType(lhs) and types.isPointerType(rhs)) {
            node.left.null_expression.null_base_type = rhs;
            return self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I1_TYPE) });
        }

        if (types.isNullType(lhs) and types.isNullType(rhs)) {
            return self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I1_TYPE) });
        }

        if (types.isVectorType(lhs) and types.isVectorType(rhs)) {
            if (types.isTypesEquals(lhs, rhs)) {
                node.setTypeNode(lhs);
                return self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I1_TYPE) });
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Expect vector types to be the same size and type but got {s} and {s}", .{ try types.getTypeLiteral(self.allocator, lhs), try types.getTypeLiteral(self.allocator, rhs) }));
            return Error.Stop;
        }

        if (types.isNullType(lhs) or types.isNullType(rhs)) {
            try self.context.diagnostics.reportError(node.operator_token.position, "Can't compare non pointer type with null value");
            return Error.Stop;
        }
        var types_ = [2]*types.Type{ lhs, rhs };
        const function_name = try types.mangleOperatorFunction(self.allocator, op.kind, &types_);
        if (self.types_table.isDefined(function_name)) {
            const function = self.types_table.lookup(function_name).?;
            const type_ = self.nodeType(function);
            std.debug.assert(type_.typeKind() == .Function);
            const function_type = type_.Function;
            return self.allocReturn(ds.Any, ds.Any{ .Type = function_type.return_type });
        }

        const op_literal = try tokenizer.overloadingOperatorLiteral(op.kind);
        const lhs_str = try types.getTypeLiteral(self.allocator, lhs);
        const rhs_str = try types.getTypeLiteral(self.allocator, rhs);
        try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Can't find operator overloading operator {s}({s}, {s})", .{ op_literal, lhs_str, rhs_str }));
        return Error.Stop;
    }

    pub fn visitLogicalExpression(self: *TypeChecker, node: *ast.LogicalExpression) !*ds.Any {
        log("Visiting logical expression", .{}, .{ .module = .TypeChecker });
        const lhs = self.nodeType(try node.left.accept(self.visitor));
        const rhs = self.nodeType(try node.right.accept(self.visitor));

        if (types.isInteger1Type(lhs) and types.isInteger1Type(rhs)) {
            return self.allocReturn(ds.Any, ds.Any{ .Type = lhs });
        }

        const op = node.operator_token;

        var types_ = [2]*types.Type{ lhs, rhs };
        const function_name = try types.mangleOperatorFunction(self.allocator, op.kind, &types_);
        if (self.types_table.isDefined(function_name)) {
            const function = self.types_table.lookup(function_name).?;
            const type_ = self.nodeType(function);
            std.debug.assert(type_.typeKind() == .Function);
            const function_type = type_.Function;
            return self.allocReturn(ds.Any, ds.Any{ .Type = function_type.return_type });
        }

        const op_literal = try tokenizer.overloadingOperatorLiteral(op.kind);
        const lhs_str = try types.getTypeLiteral(self.allocator, lhs);
        const rhs_str = try types.getTypeLiteral(self.allocator, rhs);
        try self.context.diagnostics.reportError(op.position, try std.fmt.allocPrint(self.allocator, "Can't find operator overloading operator {s}({s}, {s})", .{ op_literal, lhs_str, rhs_str }));
        return error.Stop;
    }

    pub fn visitPrefixUnaryExpression(self: *TypeChecker, node: *ast.PrefixUnaryExpression) !*ds.Any {
        log("Visiting prefix unary expression", .{}, .{ .module = .TypeChecker });
        const rhs = self.nodeType(try node.right.accept(self.visitor));
        const op = node.operator_token;
        const position = op.position;

        if (op.kind == .Minus) {
            if (types.isNumberType(rhs)) {
                node.setTypeNode(rhs);
                return self.allocReturn(ds.Any, ds.Any{ .Type = rhs });
            }
            var types_ = [1]*types.Type{rhs};
            const function_name = try std.fmt.allocPrint(self.allocator, "_prefix{s}", .{try types.mangleOperatorFunction(self.allocator, op.kind, &types_)});

            if (self.types_table.isDefined(function_name)) {
                const function = self.types_table.lookup(function_name).?;
                const type_ = self.nodeType(function);
                std.debug.assert(type_.typeKind() == .Function);
                const function_type = type_.Function;
                return self.allocReturn(ds.Any, ds.Any{ .Type = function_type.return_type });
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Unary Minus `-` expect numbers or to override operators {s}", .{try types.getTypeLiteral(self.allocator, rhs)}));
            return Error.Stop;
        }

        if (op.kind == .Bang) {
            if (types.isNumberType(rhs)) {
                node.setTypeNode(rhs);
                return self.allocReturn(ds.Any, ds.Any{ .Type = rhs });
            }
            var types_ = [1]*types.Type{rhs};
            const function_name = try std.fmt.allocPrint(self.allocator, "_prefix{s}", .{try types.mangleOperatorFunction(self.allocator, op.kind, &types_)});

            if (self.types_table.isDefined(function_name)) {
                const function = self.types_table.lookup(function_name).?;
                const type_ = self.nodeType(function);
                std.debug.assert(type_.typeKind() == .Function);
                const function_type = type_.Function;
                return self.allocReturn(ds.Any, ds.Any{ .Type = function_type.return_type });
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Bang `!` expect numbers or to override operators {s}", .{try types.getTypeLiteral(self.allocator, rhs)}));
            return Error.Stop;
        }

        if (op.kind == .Not) {
            if (types.isNumberType(rhs)) {
                node.setTypeNode(rhs);
                return self.allocReturn(ds.Any, ds.Any{ .Type = rhs });
            }

            var types_ = [1]*types.Type{rhs};
            const function_name = try std.fmt.allocPrint(self.allocator, "_prefix{s}", .{try types.mangleOperatorFunction(self.allocator, op.kind, &types_)});

            if (self.types_table.isDefined(function_name)) {
                const function = self.types_table.lookup(function_name).?;
                const type_ = self.nodeType(function);
                std.debug.assert(type_.typeKind() == .Function);
                const function_type = type_.Function;
                return self.allocReturn(ds.Any, ds.Any{ .Type = function_type.return_type });
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Not `~` expect numbers or to override operators {s}", .{try types.getTypeLiteral(self.allocator, rhs)}));
            return Error.Stop;
        }

        if (op.kind == .Star) {
            if (rhs.typeKind() == .Pointer) {
                const pointer_type = rhs.Pointer;
                const type_ = pointer_type.base_type;
                node.setTypeNode(type_);
                return self.allocReturn(ds.Any, ds.Any{ .Type = type_ });
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Derefernse operator require pointer as an right operand but got {s}", .{try types.getTypeLiteral(self.allocator, rhs)}));
            return Error.Stop;
        }

        if (op.kind == .And) {
            const pointer_type = types.PointerType.init(rhs);
            if (types.isFunctionPointerType(&types.Type{ .Pointer = pointer_type })) {
                const function_type = pointer_type.base_type.Function;
                if (function_type.is_intrinsic) {
                    try self.context.diagnostics.reportError(function_type.name.position, "Can't take address of an intrinsic function");
                    return Error.Stop;
                }
            }
            const ptr_type = try self.allocReturn(types.Type, types.Type{ .Pointer = pointer_type });
            node.setTypeNode(ptr_type);
            return self.allocReturn(ds.Any, ds.Any{ .Type = ptr_type });
        }

        if (op.kind == .PlusPlus or op.kind == .MinusMinus) {
            if (rhs.typeKind() == .Number) {
                node.setTypeNode(rhs);
                return self.allocReturn(ds.Any, ds.Any{ .Type = rhs });
            }

            var types_ = [1]*types.Type{rhs};
            const function_name = try std.fmt.allocPrint(self.allocator, "_prefix{s}", .{try types.mangleOperatorFunction(self.allocator, op.kind, &types_)});
            if (self.types_table.isDefined(function_name)) {
                const function = self.types_table.lookup(function_name).?;
                const type_ = self.nodeType(function);
                std.debug.assert(type_.typeKind() == .Function);
                const function_type = type_.Function;
                return self.allocReturn(ds.Any, ds.Any{ .Type = function_type.return_type });
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Unary ++ or -- expect numbers or to override operators {s}", .{try types.getTypeLiteral(self.allocator, rhs)}));
            return Error.Stop;
        }

        try self.context.diagnostics.reportError(position, "Unsupported unary expression");

        return Error.Stop;
    }

    pub fn visitPostfixUnaryExpression(self: *TypeChecker, node: *ast.PostfixUnaryExpression) !*ds.Any {
        log("Visiting postfix unary expression", .{}, .{ .module = .TypeChecker });
        const rhs = self.nodeType(try node.right.accept(self.visitor));
        const op_kind = node.operator_token.kind;
        const position = node.operator_token.position;

        if (op_kind == .PlusPlus or op_kind == .MinusMinus) {
            if (types.isNumberType(rhs)) {
                return self.allocReturn(ds.Any, ds.Any{ .Type = rhs });
            }

            var types_ = [1]*types.Type{rhs};
            const function_name = try std.fmt.allocPrint(self.allocator, "_postfix{s}", .{try types.mangleOperatorFunction(self.allocator, op_kind, &types_)});
            if (self.types_table.isDefined(function_name)) {
                const function = self.types_table.lookup(function_name).?;
                const type_ = self.nodeType(function);
                std.debug.assert(type_.typeKind() == .Function);
                const function_type = type_.Function;
                return self.allocReturn(ds.Any, ds.Any{ .Type = function_type.return_type });
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Unary ++ or -- expect numbers or to override operators {s}", .{try types.getTypeLiteral(self.allocator, rhs)}));
            return Error.Stop;
        }

        try self.context.diagnostics.reportError(position, "Unsupported unary expression");
        return Error.Stop;
    }

    pub fn visitInitializeExpression(self: *TypeChecker, node: *ast.InitExpression) !*ds.Any {
        log("Visiting initialize expression", .{}, .{ .module = .TypeChecker });
        log("Initialize expression value : {any}", .{node.value_type.?}, .{ .module = .TypeChecker });
        const type_ = try self.resolveGenericType(node.value_type.?, null, null);
        node.setTypeNode(type_);

        if (type_.typeKind() == .Struct) {
            const struct_type = type_.Struct;
            const parameters = struct_type.field_types;
            const arguments = node.arguments;

            try self.checkParametersTypes(node.position.position, arguments, parameters, false, null, 0);
            return self.allocReturn(ds.Any, ds.Any{ .Type = type_ });
        }

        try self.context.diagnostics.reportError(node.position.position, "InitializeExpression work only with structures");
        return Error.Stop;
    }
    pub fn visitLambdaExpression(self: *TypeChecker, node: *ast.LambdaExpression) !*ds.Any {
        log("Visiting lambda expression", .{}, .{ .module = .TypeChecker });
        var function_ptr_type = node.getTypeNode().?.Pointer;
        var function_type = function_ptr_type.base_type.Function;

        function_type.return_type = try self.resolveGenericType(function_type.return_type, null, null);
        try self.return_types_stack.append(function_type.return_type);
        self.is_inside_lambda_body = true;
        try self.lambda_implicit_parameters.append(std.ArrayList(*Pair).init(self.allocator));

        try self.pushNewScope();
        function_type.parameters.clearRetainingCapacity();
        for (node.explicit_parameters.items) |parameter| {
            parameter.parameter_type = try self.resolveGenericType(parameter.parameter_type, null, null);
            _ = self.types_table.define(parameter.name.literal, try self.allocReturn(ds.Any, ds.Any{ .Type = parameter.parameter_type }));
            try function_type.parameters.append(parameter.parameter_type);
        }

        _ = try node.body.accept(self.visitor);
        self.popCurrentScope();

        self.is_inside_lambda_body = false;

        const extra_parameter_pairs = self.lambda_implicit_parameters.getLast();

        for (extra_parameter_pairs.items) |pair| {
            try node.implicit_parameter_names.append(pair.first);
            try node.implicit_parameter_types.append(pair.second);
            function_type.implicit_parameters_count += 1;
        }

        try function_type.parameters.insertSlice(0, node.implicit_parameter_types.items);

        function_ptr_type.base_type = try self.allocReturn(types.Type, types.Type{ .Function = function_type });
        const type_ = try self.allocReturn(types.Type, types.Type{ .Pointer = function_ptr_type });
        node.setTypeNode(type_);

        _ = self.lambda_implicit_parameters.pop();
        _ = self.return_types_stack.pop();

        return self.allocReturn(ds.Any, ds.Any{ .Type = type_ });
    }

    pub fn visitDotExpression(self: *TypeChecker, node: *ast.DotExpression) !*ds.Any {
        log("Visiting dot expression", .{}, .{ .module = .TypeChecker });
        const callee = try node.callee.accept(self.visitor);
        const callee_type = self.nodeType(callee);
        const callee_type_kind = callee_type.typeKind();
        const node_position = node.dot_token.position;

        if (callee_type_kind == .Struct) {
            if (node.field_name.kind != .Identifier) {
                try self.context.diagnostics.reportError(node_position, "Can't access struct member using index, only tuples can do this");
                return Error.Stop;
            }

            const struct_type = callee_type.Struct;
            const field_name = node.field_name.literal;
            if (ds.contains([]const u8, struct_type.field_names.items, field_name)) {
                const member_index = ds.indexOf(struct_type.field_names.items, field_name);
                const field_type = struct_type.field_types.items[@intCast(member_index.?)];
                node.setTypeNode(field_type);
                node.field_index = @intCast(member_index.?);
                return self.allocReturn(ds.Any, ds.Any{ .Type = field_type });
            }

            try self.context.diagnostics.reportError(node_position, try std.fmt.allocPrint(self.allocator, "Can't find a field with name {s} in struct {s}", .{ field_name, struct_type.name }));
            return Error.Stop;
        }

        if (callee_type_kind == .Tuple) {
            if (node.field_name.kind != .Int) {
                try self.context.diagnostics.reportError(node_position, "Tuple must be accessed using position only");
                return Error.Stop;
            }

            const tuple_type = callee_type.Tuple;
            const field_index = node.field_index;

            if (field_index >= tuple_type.field_types.items.len) {
                try self.context.diagnostics.reportError(node_position, try std.fmt.allocPrint(self.allocator, "No tuple field with index {d}", .{field_index}));
                return Error.Stop;
            }
            const field_type = tuple_type.field_types.items[field_index];
            node.setTypeNode(field_type);
            return self.allocReturn(ds.Any, ds.Any{ .Type = field_type });
        }

        if (callee_type_kind == .Pointer) {
            const pointer_type = callee_type.Pointer;
            const pointer_to_type = pointer_type.base_type;
            if (pointer_to_type.typeKind() == .Struct) {
                const struct_type = pointer_to_type.Struct;
                const field_name = node.field_name.literal;
                if (ds.contains([]const u8, struct_type.field_names.items, field_name)) {
                    const member_index = ds.indexOf(struct_type.field_names.items, field_name);
                    const field_type = struct_type.field_types.items[member_index.?];
                    node.setTypeNode(field_type);
                    node.field_index = @intCast(member_index.?);
                    return self.allocReturn(ds.Any, ds.Any{ .Type = field_type });
                }

                try self.context.diagnostics.reportError(node_position, try std.fmt.allocPrint(self.allocator, "Can't find a field with name {s} in struct {s}", .{ field_name, struct_type.name }));

                return Error.Stop;
            }

            if (types.isTypesEquals(pointer_to_type, &types.Type.I8_TYPE)) {
                const attribute_token = node.field_name;
                const literal = attribute_token.literal;

                if (std.mem.eql(u8, literal, "count")) {
                    node.is_constant = node.callee.getAstNodeType() == .String;
                    node.setTypeNode(@constCast(&types.Type.I64_TYPE));
                    return self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I64_TYPE) });
                }

                try self.context.diagnostics.reportError(node_position, try std.fmt.allocPrint(self.allocator, "Unkown String attribute with name {s}", .{literal}));
                return Error.Stop;
            }

            try self.context.diagnostics.reportError(node_position, "Dot expression expect calling member from struct or pointer to struct");
            return Error.Stop;
        }

        if (callee_type_kind == .StaticArray) {
            const attribute_token = node.field_name;
            const literal = attribute_token.literal;

            if (std.mem.eql(u8, literal, "count")) {
                node.is_constant = true;
                node.setTypeNode(@constCast(&types.Type.I64_TYPE));
                return self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I64_TYPE) });
            }

            try self.context.diagnostics.reportError(node_position, try std.fmt.allocPrint(self.allocator, "Unkown Array attribute with name {s}", .{literal}));
            return Error.Stop;
        }

        if (callee_type_kind == .StaticVector) {
            const attribute_token = node.field_name;
            const literal = attribute_token.literal;

            if (std.mem.eql(u8, literal, "count")) {
                node.is_constant = true;
                node.setTypeNode(@constCast(&types.Type.I64_TYPE));
                return self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I64_TYPE) });
            }

            try self.context.diagnostics.reportError(node_position, try std.fmt.allocPrint(self.allocator, "Unkown Vector attribute with name {s}", .{literal}));
            return Error.Stop;
        }

        if (callee_type_kind == .GenericStruct) {
            const resolved_type = try self.resolveGenericType(callee_type, null, null);
            const struct_type = resolved_type.Struct;
            const fields_names = struct_type.field_names;
            const field_name = node.field_name.literal;
            if (ds.contains([]const u8, fields_names.items, field_name)) {
                const member_index = ds.indexOf(fields_names.items, field_name);
                const field_type = struct_type.field_types.items[member_index.?];
                node.setTypeNode(field_type);
                node.field_index = @intCast(member_index.?);
                return self.allocReturn(ds.Any, ds.Any{ .Type = field_type });
            }

            try self.context.diagnostics.reportError(node_position, try std.fmt.allocPrint(self.allocator, "Can't find a field with name {s} in struct {s}", .{ field_name, struct_type.name }));
            return Error.Stop;
        }

        try self.context.diagnostics.reportError(node_position, "Dot expression expect calling member from struct or pointer to struct");
        return Error.Stop;
    }

    pub fn visitCastExpression(self: *TypeChecker, node: *ast.CastExpression) !*ds.Any {
        log("Visiting cast expression", .{}, .{ .module = .TypeChecker });
        const value = node.value;
        const value_type = self.nodeType(try value.accept(self.visitor));
        const target_type = try self.resolveGenericType(node.value_type, null, null);
        const node_position = node.position.position;

        if (types.isTypesEquals(value_type, target_type)) {
            try self.context.diagnostics.reportWarning(node_position, "Unnecessary cast to the same type");
            return self.allocReturn(ds.Any, ds.Any{ .Type = target_type });
        }

        if (!types.canTypesCasted(value_type, target_type)) {
            try self.context.diagnostics.reportError(node_position, try std.fmt.allocPrint(self.allocator, "Can't cast from {s} to {s}", .{ try types.getTypeLiteral(self.allocator, value_type), try types.getTypeLiteral(self.allocator, target_type) }));
            return Error.Stop;
        }

        return self.allocReturn(ds.Any, ds.Any{ .Type = target_type });
    }

    pub fn visitTypeSizeExpression(self: *TypeChecker, node: *ast.TypeSizeExpression) !*ds.Any {
        log("Visiting type size expression", .{}, .{ .module = .TypeChecker });
        const type_ = try self.resolveGenericType(node.value_type.?, null, null);
        node.value_type = type_;
        return self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I64_TYPE) });
    }

    pub fn visitTypeAlignExpression(self: *TypeChecker, node: *ast.TypeAlignExpression) !*ds.Any {
        log("Visiting type align expression", .{}, .{ .module = .TypeChecker });
        const type_ = try self.resolveGenericType(node.value_type.?, null, null);
        node.value_type = type_;
        return self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I64_TYPE) });
    }

    pub fn visitValueSizeExpression(self: *TypeChecker, node: *ast.ValueSizeExpression) !*ds.Any {
        log("Visiting value size expression", .{}, .{ .module = .TypeChecker });
        _ = try node.value.accept(self.visitor);
        return self.allocReturn(ds.Any, ds.Any{ .Type = @constCast(&types.Type.I64_TYPE) });
    }

    pub fn visitIndexExpression(self: *TypeChecker, node: *ast.IndexExpression) !*ds.Any {
        log("Visiting index expression", .{}, .{ .module = .TypeChecker });
        const index = node.index;
        const index_type = self.nodeType(try index.accept(self.visitor));
        const position = node.position.position;

        if (!types.isIntegerType(index_type)) {
            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Index must be an integer but got {s}", .{try types.getTypeLiteral(self.allocator, index_type)}));
            return Error.Stop;
        }

        const has_constant_idx = index.getAstNodeType() == .Number;
        var constant_idx: i32 = -1;

        if (has_constant_idx) {
            const number_expr = index.number_expression;
            const number_literal = number_expr.value.literal;
            constant_idx = try std.fmt.parseInt(i32, number_literal, 10);

            if (constant_idx < 0) {
                try self.context.diagnostics.reportError(position, "Index must be a positive number");
                return Error.Stop;
            }
        }

        const callee_expr = node.value;
        const callee_type = self.nodeType(try callee_expr.accept(self.visitor));

        if (callee_type.typeKind() == .StaticArray) {
            const array_type = callee_type.StaticArray;
            node.setTypeNode(array_type.element_type.?);

            if (has_constant_idx and constant_idx >= array_type.size) {
                try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Index out of bounds {d} >= {d}", .{ constant_idx, array_type.size }));
                return Error.Stop;
            }

            return self.allocReturn(ds.Any, ds.Any{ .Type = array_type.element_type.? });
        }

        if (callee_type.typeKind() == .StaticVector) {
            const vector_type = callee_type.StaticVector;
            node.setTypeNode(vector_type.array.element_type.?);

            if (has_constant_idx and constant_idx >= vector_type.array.size) {
                try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Index out of bounds {d} >= {d}", .{ constant_idx, vector_type.array.size }));
                return Error.Stop;
            }

            return self.allocReturn(ds.Any, ds.Any{ .Type = vector_type.array.element_type.? });
        }

        if (callee_type.typeKind() == .Pointer) {
            const pointer_type = callee_type.Pointer;
            node.setTypeNode(pointer_type.base_type);
            return self.allocReturn(ds.Any, ds.Any{ .Type = pointer_type.base_type });
        }

        try self.context.diagnostics.reportError(position, "Index expression expected array but got");
        return Error.Stop;
    }

    pub fn visitEnumAccessExpression(self: *TypeChecker, node: *ast.EnumAccessExpression) !*ds.Any {
        log("Visiting enum access expression", .{}, .{ .module = .TypeChecker });
        return self.allocReturn(ds.Any, ds.Any{ .Type = node.getTypeNode().? });
    }

    pub fn visitLiteralExpression(self: *TypeChecker, node: *ast.LiteralExpression) !*ds.Any {
        log("Visiting literal expression", .{}, .{ .module = .TypeChecker });
        const name = node.name.literal;
        if (!self.types_table.isDefined(name)) {
            try self.context.diagnostics.reportError(node.name.position, try std.fmt.allocPrint(self.allocator, "Can't resolve variable with name {s}", .{node.name.literal}));
            return Error.Stop;
        }

        var value: *ds.Any = undefined;
        if (self.is_inside_lambda_body) {
            const local_variable = self.types_table.lookupOnCurrent(name);

            if (local_variable == null) {
                const outer_variable_pair = self.types_table.lookupWithLevel(name);
                const declared_scope_level = outer_variable_pair.i;

                value = outer_variable_pair.x.?;

                if (declared_scope_level != 0 and (declared_scope_level < self.types_table.size() - 2)) {
                    const type_ = self.nodeType(value);
                    _ = self.types_table.define(name, try self.allocReturn(ds.Any, ds.Any{ .Type = type_ }));
                    const len = self.lambda_implicit_parameters.items.len;
                    try self.lambda_implicit_parameters.items[len - 1].append(try self.allocReturn(Pair, Pair{ .first = name, .second = type_ }));
                }
            } else {
                value = local_variable.?;
            }
        } else {
            value = self.types_table.lookup(name).?;
        }

        const type_ = self.nodeType(value);
        node.value_type = type_;

        if (type_.typeKind() == .Number or type_.typeKind() == .EnumElement) {
            node.setConstant(true);
        }

        return self.allocReturn(ds.Any, ds.Any{ .Type = type_ });
    }

    pub fn visitNumberExpression(self: *TypeChecker, node: *ast.NumberExpression) !*ds.Any {
        log("Visiting number expression", .{}, .{ .module = .TypeChecker });

        const number_type = node.getTypeNode().?.Number;
        const number_kind = number_type.number_kind;
        const number_literal = node.value.literal;

        const is_valid_range = try self.checkNumberLimits(number_literal, number_kind);

        if (!is_valid_range) {
            try self.context.diagnostics.reportError(node.value.position, try std.fmt.allocPrint(self.allocator, "Number Value {s} Can't be represented using type {s}", .{ number_literal, try types.getTypeLiteral(self.allocator, node.getTypeNode().?) }));
            return Error.Stop;
        }

        return self.allocReturn(ds.Any, ds.Any{ .Type = node.getTypeNode().? });
    }

    pub fn visitArrayExpression(self: *TypeChecker, node: *ast.ArrayExpression) !*ds.Any {
        log("Visiting array expression", .{}, .{ .module = .TypeChecker });
        const values = node.values;
        const values_size = values.items.len;
        if (values_size == 0) {
            return self.allocReturn(ds.Any, ds.Any{ .Type = node.getTypeNode().? });
        }
        var last_element_type = self.nodeType(try values.items[0].accept(self.visitor));
        for (1..values_size) |i| {
            var value = values.items[i];
            const current_element_type = self.nodeType(try value.accept(self.visitor));
            if (types.isTypesEquals(current_element_type, last_element_type)) {
                last_element_type = current_element_type;
                continue;
            }

            try self.context.diagnostics.reportError(node.position.position, try std.fmt.allocPrint(self.allocator, "Array elements with index {d} and {d} are not the same types", .{ i - 1, i }));
            return Error.Stop;
        }

        var array_type = node.getTypeNode().?.StaticArray;
        array_type.element_type = last_element_type;
        const new_type = try self.allocReturn(types.Type, types.Type{ .StaticArray = array_type });
        node.setTypeNode(new_type);
        return self.allocReturn(ds.Any, ds.Any{ .Type = new_type });
    }

    pub fn visitVectorExpression(self: *TypeChecker, node: *ast.VectorExpression) !*ds.Any {
        log("Visiting vector expression", .{}, .{ .module = .TypeChecker });
        const array = node.array;
        const array_type = array.value_type.?.StaticArray;
        const element_type = array_type.element_type.?;

        if (element_type.typeKind() != .Number or types.isSignedIntegerType(element_type)) {
            try self.context.diagnostics.reportError(node.array.position.position, "Vector type accept only unsinged number or float types");
            return Error.Stop;
        }

        return self.allocReturn(ds.Any, ds.Any{ .Type = node.getTypeNode().? });
    }

    pub fn visitStringExpression(self: *TypeChecker, node: *ast.StringExpression) !*ds.Any {
        log("Visiting string expression", .{}, .{ .module = .TypeChecker });
        return self.allocReturn(ds.Any, ds.Any{ .Type = node.getTypeNode().? });
    }

    pub fn visitCharacterExpression(self: *TypeChecker, node: *ast.CharacterExpression) !*ds.Any {
        log("Visiting character expression", .{}, .{ .module = .TypeChecker });
        return self.allocReturn(ds.Any, ds.Any{ .Type = node.getTypeNode().? });
    }

    pub fn visitBooleanExpression(self: *TypeChecker, node: *ast.BoolExpression) !*ds.Any {
        log("Visiting boolean expression", .{}, .{ .module = .TypeChecker });
        return self.allocReturn(ds.Any, ds.Any{ .Type = node.getTypeNode().? });
    }

    pub fn visitNullExpression(self: *TypeChecker, node: *ast.NullExpression) !*ds.Any {
        log("Visiting null expression", .{}, .{ .module = .TypeChecker });
        return self.allocReturn(ds.Any, ds.Any{ .Type = node.getTypeNode().? });
    }

    pub fn visitUndefinedExpression(self: *TypeChecker, node: *ast.UndefinedExpression) !*ds.Any {
        log("Visiting undefined expression", .{}, .{ .module = .TypeChecker });
        return self.allocReturn(ds.Any, ds.Any{ .Type = node.getTypeNode().? });
    }

    pub fn visitInfinityExpression(self: *TypeChecker, node: *ast.InfinityExpression) !*ds.Any {
        log("Visiting infinity expression", .{}, .{ .module = .TypeChecker });
        return self.allocReturn(ds.Any, ds.Any{ .Type = node.getTypeNode().? });
    }

    pub fn nodeType(self: *TypeChecker, any_type: *ds.Any) *types.Type {
        _ = self;
        return switch (any_type.*) {
            .Type => any_type.Type,
            else => unreachable,
        };
    }

    pub fn isSameType(self: *TypeChecker, left: types.Type, right: types.Type) bool {
        _ = self;
        _ = self;
        return left.typeKind() == right.typeKind();
    }

    pub fn resolveGenericType(self: *TypeChecker, type_: *types.Type, generic_names: ?std.ArrayList([]const u8), generic_parameters: ?std.ArrayList(*types.Type)) !*types.Type {
        log("Resolving generic type", .{}, .{ .module = .TypeChecker });
        if (type_.typeKind() == .GenericParameter) {
            const generic = type_.GenericParameter;
            var position: ?usize = null;
            if (generic_names != null) {
                position = ds.indexOf(generic_names.?.items, generic.name);
            }
            if (position != null) {
                const resolved_type = generic_parameters.?.items[position.?];
                try self.generic_types.put(generic.name, resolved_type);
                return resolved_type;
            }
            return self.generic_types.get(generic.name).?;
        }

        if (type_.typeKind() == .Pointer) {
            const pointer = type_.Pointer;
            const new_base = try self.resolveGenericType(pointer.base_type, generic_names, generic_parameters);
            const new_ptr = try self.allocReturn(types.Type, types.Type{ .Pointer = types.PointerType.init(new_base) });
            return new_ptr;
        }

        if (type_.typeKind() == .StaticArray) {
            const array = type_.StaticArray;
            const element_type = try self.resolveGenericType(array.element_type.?, generic_names, generic_parameters);
            return try self.allocReturn(types.Type, types.Type{ .StaticArray = types.StaticArrayType.init(element_type, array.size, array.element_type.?) });
        }

        if (type_.typeKind() == .Function) {
            // var function = type_.Function;
            // function.return_type = try self.resolveGenericType(function.return_type, generic_names, generic_parameters);
            // const parameters = function.parameters;
            // const parameters_count = parameters.items.len;
            // for (0..parameters_count) |i| {
            //     function.parameters.items[i] = try self.resolveGenericType(function.parameters.items[i], generic_names, generic_parameters);
            // }

            const function = type_.Function;
            const return_type = try self.resolveGenericType(function.return_type, generic_names, generic_parameters);
            var parameters = std.ArrayList(*types.Type).init(self.allocator);
            for (function.parameters.items) |parameter| {
                const resolved_parameter = try self.resolveGenericType(parameter, generic_names, generic_parameters);
                try parameters.append(resolved_parameter);
            }

            const new_function = types.FunctionType.init(function.name, parameters, return_type, function.has_varargs, function.varargs_type, function.is_intrinsic, function.is_generic, function.generic_names);

            return self.allocReturn(types.Type, types.Type{ .Function = new_function });
        }

        if (type_.typeKind() == .GenericStruct) {
            const generic_struct = type_.GenericStruct;
            const structure = generic_struct.struct_type;
            const generic_struct_param = generic_struct.parameters;
            var i: usize = 0;
            for (generic_struct_param.items) |parameter| {
                if (parameter.typeKind() == .GenericParameter) {
                    const generic_type = parameter.GenericParameter;
                    var index: ?usize = null;
                    if (generic_names != null) {
                        index = ds.indexOf(generic_names.?.items, generic_type.name);
                    }
                    if (index) |j| {
                        // generic_struct.parameters.items[i] = generic_parameters.?.items[j];
                        generic_struct_param.items[i] = generic_parameters.?.items[j];
                    } else {
                        // generic_struct.parameters.items[i] = self.generic_types.get(generic_type.name).?;
                        generic_struct_param.items[i] = self.generic_types.get(generic_type.name).?;
                    }
                }
                i += 1;
            }
            const mangled_parameters = try types.mangleTypes(self.allocator, generic_struct.parameters.items);
            const mangled_name = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ structure.name, mangled_parameters });

            if (self.types_table.isDefined(mangled_name)) {
                return self.types_table.lookup(mangled_name).?.Type;
            }
            var fields_names = std.ArrayList([]const u8).init(self.allocator);
            for (structure.field_names.items) |name| {
                try fields_names.append(name);
            }
            var types1 = std.ArrayList(*types.Type).init(self.allocator);
            for (structure.field_types.items) |type_1| {
                // try types1.append(try self.resolveGenericType(type_1, structure.generic_parameters, generic_struct.parameters));
                try types1.append(try self.resolveGenericType(type_1, structure.generic_parameters, generic_struct_param));
            }

            const new_struct = try self.allocReturn(types.Type, types.Type{
                .Struct = types.StructType.init(
                    mangled_name,
                    fields_names,
                    types1,
                    structure.generic_parameters,
                    // generic_struct.parameters,
                    generic_struct_param,
                    true,
                    true,
                    false,
                ),
            });
            _ = self.types_table.define(mangled_name, try self.allocReturn(ds.Any, ds.Any{ .Type = new_struct }));
            return new_struct;
        }

        if (type_.typeKind() == .Tuple) {
            const tuple = type_.Tuple;
            var fields = std.ArrayList(*types.Type).init(self.allocator);
            for (tuple.field_types.items) |field| {
                const resolved_field = try self.resolveGenericType(field, generic_names, generic_parameters);
                try fields.append(resolved_field);
            }

            const tuple_name = try std.fmt.allocPrint(self.allocator, "_tuple_{s}", .{try types.mangleTypes(self.allocator, fields.items)});
            const new_tuple = types.TupleType.init(tuple_name, fields);
            return self.allocReturn(types.Type, types.Type{ .Tuple = new_tuple });
        }

        return type_;
    }

    pub fn inferTypeByOtherType(self: *TypeChecker, type_: *types.Type, other: *types.Type) !std.StringArrayHashMap(*types.Type) {
        if (type_.typeKind() == .GenericParameter) {
            var resolved_types = std.StringArrayHashMap(*types.Type).init(self.allocator);
            const generic_parameter = type_.GenericParameter;
            try resolved_types.put(generic_parameter.name, other);
            return resolved_types;
        }

        if (types.isFunctionPointerType(type_) and types.isFunctionPointerType(other)) {
            const type_ptr = type_.Pointer;
            const other_ptr = other.Pointer;

            const type_fptr = type_ptr.base_type.Function;
            const other_fptr = other_ptr.base_type.Function;

            if (type_fptr.parameters.items.len == other_fptr.parameters.items.len) {
                const return_type = try self.inferTypeByOtherType(type_fptr.return_type, other_fptr.return_type);
                var resolved_types = std.StringArrayHashMap(*types.Type).init(self.allocator);
                for (return_type.keys()) |key| {
                    try resolved_types.put(key, return_type.get(key).?);
                }

                var index: usize = 0;
                for (type_fptr.parameters.items) |parameter| {
                    const parameter_result = try self.inferTypeByOtherType(parameter, other_fptr.parameters.items[index]);
                    for (parameter_result.keys()) |key| {
                        if (!resolved_types.contains(key)) {
                            try resolved_types.put(key, parameter_result.get(key).?);
                        }
                    }
                    index += 1;
                }

                return resolved_types;
            }

            return std.StringArrayHashMap(*types.Type).init(self.allocator);
        }

        if (types.isPointerType(type_) and types.isPointerType(other)) {
            const type_ptr = type_.Pointer;
            const other_ptr = other.Pointer;
            return self.inferTypeByOtherType(type_ptr.base_type, other_ptr.base_type);
        }

        if (types.isArrayType(type_) and types.isArrayType(other)) {
            const type_arr = type_.StaticArray;
            const other_arr = other.StaticArray;
            return self.inferTypeByOtherType(type_arr.element_type.?, other_arr.element_type.?);
        }

        if (types.isGenericStructType(type_) and types.isStructType(other)) {
            const type_generic_struct = type_.GenericStruct;

            const type_struct = type_generic_struct.struct_type;
            _ = type_struct;
            const other_struct = other.Struct;

            var index: usize = 0;
            var resolved_types = std.StringArrayHashMap(*types.Type).init(self.allocator);
            for (other_struct.generic_parameter_types.items) |t| {
                const result = try self.inferTypeByOtherType(type_generic_struct.parameters.items[index], t);
                for (result.keys()) |key| {
                    if (!resolved_types.contains(key)) {
                        try resolved_types.put(key, result.get(key).?);
                    }
                }
                index += 1;
            }

            return resolved_types;
        }

        if (types.isGenericStructType(type_) and types.isGenericStructType(other)) {
            const type_generic_struct = type_.GenericStruct;
            const other_generic_struct = other.GenericStruct;

            const type_struct = type_generic_struct.struct_type;
            const other_struct = other_generic_struct.struct_type;

            if (std.mem.eql(u8, type_struct.name, other_struct.name) and type_struct.field_types.items.len == other_struct.field_types.items.len) {
                var resolved_types = std.StringArrayHashMap(*types.Type).init(self.allocator);
                var index: usize = 0;
                for (type_generic_struct.parameters.items) |field_type| {
                    const other_type = other_generic_struct.parameters.items[index];
                    const result = try self.inferTypeByOtherType(field_type, other_type);
                    for (result.keys()) |key| {
                        if (!resolved_types.contains(key)) {
                            try resolved_types.put(key, result.get(key).?);
                        }
                    }
                    index += 1;
                }
                return resolved_types;
            }

            return std.StringArrayHashMap(*types.Type).init(self.allocator);
        }

        if (types.isTupleType(type_) and types.isTupleType(other)) {
            const type_tuple = type_.Tuple;
            const other_tuple = other.Tuple;
            if (type_tuple.field_types.items.len == other_tuple.field_types.items.len) {
                var resolved_types = std.StringArrayHashMap(*types.Type).init(self.allocator);
                var index: usize = 0;
                for (type_tuple.field_types.items) |field_type| {
                    const other_type = other_tuple.field_types.items[index];
                    const result = try self.inferTypeByOtherType(field_type, other_type);
                    for (result.keys()) |key| {
                        if (!resolved_types.contains(key)) {
                            try resolved_types.put(key, result.get(key).?);
                        }
                    }
                    index += 1;
                }
                return resolved_types;
            }

            return std.StringArrayHashMap(*types.Type).init(self.allocator);
        }
        return std.StringArrayHashMap(*types.Type).init(self.allocator);
    }

    pub fn checkCompleteSwitchCases(self: *TypeChecker, enum_type: *types.EnumType, cases_values: std.StringArrayHashMap(void), has_else_branch: bool, span: tokenizer.TokenSpan) !void {
        const enum_name = enum_type.name;
        const enum_members_map = enum_type.values;
        const enum_members_size = enum_members_map.count();

        const switch_cases_size = cases_values.count();
        const missing_cases_count = enum_members_size - switch_cases_size;

        if (has_else_branch or missing_cases_count == 0) {
            return;
        }

        var string_stream = std.ArrayList(u8).init(self.allocator);
        try string_stream.appendSlice("Incomplete switch, missing ");
        try string_stream.appendSlice(try std.fmt.allocPrint(self.allocator, "{d}", .{missing_cases_count}));
        try string_stream.appendSlice(" cases\n\n");
        try string_stream.appendSlice("You forget to cover the following cases:\n");

        for (enum_members_map.keys()) |key| {
            const value = try std.fmt.allocPrint(self.allocator, "{d}", .{enum_members_map.get(key).?});
            if (!cases_values.contains(value)) {
                const enum_element_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ enum_name, key });
                try string_stream.appendSlice("- ");
                try string_stream.appendSlice(enum_element_name);
                try string_stream.appendSlice("\n");
            }
        }

        try self.context.diagnostics.reportError(span, string_stream.items);
        return error.Stop;
    }

    pub fn checkParametersTypes(self: *TypeChecker, location: tokenizer.TokenSpan, arguments: std.ArrayList(*ast.Expression), parameters: std.ArrayList(*types.Type), has_varargs: bool, varargs_type: ?*types.Type, implicit_parameters_count: usize) !void {
        log("Checking parameters types", .{}, .{ .module = .TypeChecker });
        const arguments_size = arguments.items.len;
        const all_arguments_size: usize = arguments_size + implicit_parameters_count;
        const parameters_size = parameters.items.len;
        log("Arguments: {any}", .{arguments.items}, .{ .module = .TypeChecker });
        log("Parameters: {any}", .{parameters.items}, .{ .module = .TypeChecker });

        if (!has_varargs and all_arguments_size != parameters_size) {
            try self.context.diagnostics.reportError(location, try std.fmt.allocPrint(self.allocator, "Invalid number of arguments, expect {d} but got {d}", .{ parameters_size, all_arguments_size }));
            return error.Stop;
        }

        if (has_varargs and parameters_size > all_arguments_size) {
            try self.context.diagnostics.reportError(location, try std.fmt.allocPrint(self.allocator, "Invalid number of arguments, expect at last {d} but got {d}", .{ parameters_size, all_arguments_size }));
            return error.Stop;
        }

        var arguments_types = std.ArrayList(*types.Type).init(self.allocator);

        for (arguments.items) |argument| {
            try self.checkLambdaHasInvalidCapturing(argument);
            const argument_type = self.nodeType(try argument.accept(self.visitor));
            if (argument_type.typeKind() == .GenericStruct) {
                try arguments_types.append(try self.resolveGenericType(argument_type, null, null));
            } else {
                try arguments_types.append(argument_type);
            }
        }

        // Save the generic parameters to reset them after
        // var generic_parameters = std.AutoArrayHashMap(usize, *types.Type).init(self.allocator);
        for (0..parameters.items.len) |i| {
            if (parameters.items[i].typeKind() == .GenericStruct) {
                // I can resolve it here but i have to reset the generic types after, but where?
                parameters.items[i] = try self.resolveGenericType(parameters.items[i], null, null);
                // try generic_parameters.put(i, parameters.items[i]);
            }
        }

        const count = if (parameters_size > arguments_size) arguments_size else parameters_size;

        for (0..count) |i| {
            const p = i + implicit_parameters_count;
            if (!types.isTypesEquals(parameters.items[p], arguments_types.items[i])) {
                if (types.isPointerType(parameters.items[p]) and types.isNullType(arguments_types.items[i])) {
                    arguments.items[i].null_expression.null_base_type = parameters.items[p];
                    continue;
                }

                if (types.isArrayType(parameters.items[p]) and arguments.items[i].getAstNodeType() == .Array) {
                    const array_expr = arguments.items[i].array_expression;
                    const array_type = array_expr.value_type.?.StaticArray;
                    const param_type = parameters.items[p].StaticArray;
                    if (array_type.size == 0) {
                        arguments.items[i].array_expression.value_type.?.StaticArray.element_type = param_type.element_type;
                    }
                    continue;
                }
                try self.context.diagnostics.reportError(location, try std.fmt.allocPrint(self.allocator, "Argument type didn't match parameter type expect {s} got {s}", .{ try types.getTypeLiteral(self.allocator, parameters.items[p]), try types.getTypeLiteral(self.allocator, arguments_types.items[i]) }));
                return error.Stop;
            }
        }

        // Reset the generic parameters to the original values, here??
        // for (generic_parameters.keys()) |key| {
        //     parameters.items[key] = generic_parameters.get(key).?;
        // }
        // generic_parameters.deinit();

        if (varargs_type == null) {
            return;
        }

        for (parameters_size..arguments_size) |i| {
            if (!types.isTypesEquals(arguments_types.items[i], varargs_type.?)) {
                try self.context.diagnostics.reportError(location, try std.fmt.allocPrint(self.allocator, "Argument type didn't match varargs type expect {s} got {s}", .{ try types.getTypeLiteral(self.allocator, varargs_type.?), try types.getTypeLiteral(self.allocator, arguments_types.items[i]) }));
                return error.Stop;
            }
        }
    }

    pub fn checkLambdaHasInvalidCapturing(self: *TypeChecker, expression: *ast.Expression) !void {
        if (expression.getAstNodeType() == .Lambda) {
            const lambda = expression.lambda_expression;
            const location = lambda.position.position;
            if (lambda.implicit_parameter_names.items.len != 0) {
                var error_message = std.ArrayList(u8).init(self.allocator);
                try error_message.appendSlice("Function argument lambda expression can't capture variables from non global scopes\n\n");
                try error_message.appendSlice("Captured variables:\n");
                for (lambda.implicit_parameter_names.items) |name| {
                    try error_message.appendSlice("-> ");
                    try error_message.appendSlice(name);
                    try error_message.appendSlice("\n");
                }
                try self.context.diagnostics.reportError(location, error_message.items);
                return error.Stop;
            }
        }
    }

    pub fn checkNumberLimits(self: *TypeChecker, literal: []const u8, kind: types.NumberKind) !bool {
        log("Checking number limits: {s}", .{literal}, .{ .module = .TypeChecker });
        _ = self;
        switch (kind) {
            types.NumberKind.Integer1 => {
                const value = try std.fmt.parseInt(i64, literal, 10);
                return value == 0 or value == 1;
            },
            types.NumberKind.Integer8 => {
                const value = try std.fmt.parseInt(i64, literal, 10);
                return value >= std.math.minInt(i8) and value <= std.math.maxInt(i8);
            },
            types.NumberKind.UInteger8 => {
                const value = try std.fmt.parseInt(u64, literal, 10);
                return value >= 0 and value <= std.math.maxInt(u8);
            },
            types.NumberKind.Integer16 => {
                const value = try std.fmt.parseInt(i64, literal, 10);
                return value >= std.math.minInt(i16) and value <= std.math.maxInt(i16);
            },
            types.NumberKind.UInteger16 => {
                const value = try std.fmt.parseInt(u64, literal, 10);
                return value >= 0 and value <= std.math.maxInt(u16);
            },
            types.NumberKind.Integer32 => {
                const value = try std.fmt.parseInt(i64, literal, 10);
                return value >= std.math.minInt(i32) and value <= std.math.maxInt(i32);
            },
            types.NumberKind.UInteger32 => {
                const value = try std.fmt.parseInt(u64, literal, 10);
                return value >= 0 and value <= std.math.maxInt(u32);
            },
            types.NumberKind.Integer64 => {
                const value = try std.fmt.parseInt(i64, literal, 10);
                return value >= std.math.minInt(i64) and value <= std.math.maxInt(i64);
            },
            types.NumberKind.UInteger64 => {
                const value = try std.fmt.parseInt(u64, literal, 10);
                return value >= 0 and value <= std.math.maxInt(u64);
            },
            types.NumberKind.Float32 => {
                const value = try std.fmt.parseFloat(f32, literal);
                return value >= -std.math.floatMin(f32) and
                    value <= std.math.floatMax(f32);
            },

            types.NumberKind.Float64 => {
                const value = try std.fmt.parseFloat(f64, literal);
                return value >= -std.math.floatMin(f64) and
                    value <= std.math.floatMax(f64);
            },
        }
    }

    pub fn checkValidAssignmentRightSide(self: *TypeChecker, node: *ast.Expression, position: tokenizer.TokenSpan) !void {
        const left_node_type = node.getAstNodeType();

        if (left_node_type == .Literal) {
            return;
        }

        if (left_node_type == .Call) {
            try self.context.diagnostics.reportError(position, "invalid left-hand side of assignment");
            return Error.Stop;
        }

        if (left_node_type == .Cast) {
            try self.context.diagnostics.reportError(position, "invalid left-hand side of assignment");
            return Error.Stop;
        }

        if (left_node_type == .Index) {
            const index_expression = node.index_expression;
            const value_type = index_expression.value.getTypeNode();
            if (std.mem.eql(u8, "*Int8", try types.getTypeLiteral(self.allocator, value_type.?))) {
                const index_position = index_expression.position.position;
                try self.context.diagnostics.reportError(index_position, "String literal are readonly can't modify it using [i]");
                return Error.Stop;
            } else {
                return;
            }
        }

        if (left_node_type == .PrefixUnary) {
            const prefix_unary = node.prefix_unary_expression;
            if (prefix_unary.operator_token.kind == .Star) {
                return;
            }

            try self.context.diagnostics.reportError(position, "invalid left-hand side of assignment");
            return Error.Stop;
        }

        if (left_node_type == .Character) {
            try self.context.diagnostics.reportError(position, "invalid left-hand side of assignment");
            return Error.Stop;
        }

        if (left_node_type == .Bool) {
            try self.context.diagnostics.reportError(position, "invalid left-hand side of assignment");
            return Error.Stop;
        }

        if (left_node_type == .Number) {
            try self.context.diagnostics.reportError(position, "invalid left-hand side of assignment");
            return Error.Stop;
        }

        if (left_node_type == .String) {
            try self.context.diagnostics.reportError(position, "invalid left-hand side of assignment");
            return Error.Stop;
        }

        if (left_node_type == .EnumElement) {
            try self.context.diagnostics.reportError(position, "invalid left-hand side of assignment");
            return Error.Stop;
        }

        if (left_node_type == .Null) {
            try self.context.diagnostics.reportError(position, "invalid left-hand side of assignment");
            return Error.Stop;
        }
    }

    pub fn visitCallExpression(self: *TypeChecker, node: *ast.CallExpression) !*ds.Any {
        log("Visiting call expression", .{}, .{ .module = .TypeChecker });
        const callee = node.callee;
        const callee_type = node.callee.getAstNodeType();
        const node_span = node.position.position;

        if (callee_type == .Literal) {
            const literal = callee.literal_expression;
            const name = literal.name.literal;
            if (self.types_table.isDefined(name)) {
                const lookup = self.types_table.lookup(name).?;
                var value = self.nodeType(lookup);

                if (value.typeKind() == .Pointer) {
                    const pointer_type = value.Pointer;
                    value = pointer_type.base_type;
                }

                if (value.typeKind() == .Function) {
                    const type_ = value.Function;
                    node.setTypeNode(value);
                    const parameters = type_.parameters;
                    const arguments = node.arguments;
                    for (arguments.items) |argument| {
                        argument.setTypeNode(self.nodeType(try argument.accept(self.visitor)));
                    }

                    try self.checkParametersTypes(
                        node_span,
                        arguments,
                        parameters,
                        type_.has_varargs,
                        type_.varargs_type,
                        type_.implicit_parameters_count,
                    );
                    return self.allocReturn(ds.Any, ds.Any{ .Type = type_.return_type });
                } else {
                    try self.context.diagnostics.reportError(node_span, "Call expression work only with function types");
                    return error.Stop;
                }
            } else if (self.generic_functions_declarations.contains(name)) {
                const function_declaration = self.generic_functions_declarations.get(name).?;
                const function_prototype = function_declaration.prototype;
                const prototype_parameters = function_prototype.parameters;
                const prototype_generic_names = function_prototype.generic_parameters;

                const call_arguments = node.arguments;
                var call_generic_arguments = node.generic_arguments;

                if (prototype_parameters.items.len != call_arguments.items.len) {
                    try self.context.diagnostics.reportError(node_span, try std.fmt.allocPrint(self.allocator, "Invalid number of arguments, expect {d} but got {d}", .{ prototype_parameters.items.len, call_arguments.items.len }));
                    return error.Stop;
                }

                const call_has_generic_arguments = call_generic_arguments.items.len == 0;
                if (call_has_generic_arguments) {
                    if (prototype_parameters.items.len == 0) {
                        try self.context.diagnostics.reportError(node_span, "Function prototype doesn't have generic parameters");
                        return error.Stop;
                    }

                    try node.generic_arguments.resize(prototype_generic_names.items.len);

                    var parameter_index: u32 = 0;
                    var generic_arguments_indices = std.AutoArrayHashMap(u32, void).init(self.allocator);
                    for (prototype_parameters.items) |parameter| {
                        const parameter_type = parameter.parameter_type;
                        const resolved_argument = try call_arguments.items[parameter_index].accept(self.visitor);
                        const argument_type = self.nodeType(resolved_argument);

                        if (!types.isTypesEquals(parameter_type, argument_type)) {
                            if (types.isNullType(argument_type)) {
                                try self.context.diagnostics.reportError(node_span, "Can't resolve generic type from null type");
                                return error.Stop;
                            }

                            if (types.isVoidType(argument_type)) {
                                try self.context.diagnostics.reportError(node_span, "Can't pass `void` value as argument");
                                return error.Stop;
                            }

                            const result_map = try self.inferTypeByOtherType(parameter_type, argument_type);
                            for (result_map.keys()) |key| {
                                const index = ds.indexOf(prototype_generic_names.items, key).?;
                                try generic_arguments_indices.put(@intCast(index), {});
                                node.generic_arguments.items[index] = result_map.get(key).?;
                            }
                        }

                        parameter_index += 1;
                    }

                    if (generic_arguments_indices.count() != prototype_generic_names.items.len) {
                        try self.context.diagnostics.reportError(node_span, "Can't resolve generic type from argument");
                        return error.Stop;
                    }
                    call_generic_arguments = node.generic_arguments;
                }

                const generic_arguments_count = prototype_generic_names.items.len;
                const generic_parameters_count = call_generic_arguments.items.len;
                if (generic_parameters_count != generic_arguments_count) {
                    try self.context.diagnostics.reportError(node_span, "Not enough information to infer all generic types");
                    return error.Stop;
                }

                for (0..generic_parameters_count) |i| {
                    try self.generic_types.put(prototype_generic_names.items[i], call_generic_arguments.items[i]);
                }

                const return_type = try self.resolveGenericType(function_prototype.return_type.?, prototype_generic_names, call_generic_arguments);
                try self.return_types_stack.append(return_type);

                var resolved_parameters = std.ArrayList(*types.Type).init(self.allocator);
                for (prototype_parameters.items) |parameter| {
                    try resolved_parameters.append(try self.resolveGenericType(parameter.parameter_type, prototype_generic_names, call_generic_arguments));
                }

                try self.pushNewScope();

                var index: u32 = 0;

                for (prototype_parameters.items) |parameter| {
                    const resolved_parameter = try self.allocReturn(ds.Any, ds.Any{ .Type = resolved_parameters.items[index] });
                    _ = self.types_table.define(parameter.name.literal, resolved_parameter);
                    index += 1;
                }

                _ = try function_declaration.body.accept(self.visitor);
                self.popCurrentScope();

                _ = self.return_types_stack.pop();

                const arguments = call_arguments.items;
                for (arguments) |argument| {
                    var argument_type = self.nodeType(try argument.accept(self.visitor));
                    argument_type = try self.resolveGenericType(argument_type, null, null);
                    argument.setTypeNode(argument_type);
                }

                try self.checkParametersTypes(node_span, call_arguments, resolved_parameters, function_prototype.has_varargs, function_prototype.varargs_type, 0);
                self.generic_types.clearRetainingCapacity();
                return self.allocReturn(ds.Any, ds.Any{ .Type = return_type });
            } else {
                try self.context.diagnostics.reportError(node_span, try std.fmt.allocPrint(self.allocator, "Can't resolve function call with name `{s}`", .{name}));
                return error.Stop;
            }
        }

        if (callee_type == .Call) {
            const call_result = self.nodeType(try callee.call_expression.accept(self.visitor));
            const function_pointer_type = call_result.Pointer;
            const function_type = function_pointer_type.base_type.Function;
            const parameters = function_type.parameters;
            const arguments = node.arguments;
            try self.checkParametersTypes(node_span, arguments, parameters, function_type.has_varargs, function_type.varargs_type, function_type.implicit_parameters_count);
            node.setTypeNode(function_pointer_type.base_type);
            return self.allocReturn(ds.Any, ds.Any{ .Type = function_type.return_type });
        }

        if (callee_type == .Lambda) {
            const lambda_function_type = self.nodeType(try callee.lambda_expression.accept(self.visitor));
            const function_ptr_type = lambda_function_type.Pointer;
            const function_type = function_ptr_type.base_type.Function;

            const parameters = function_type.parameters;
            const arguments = node.arguments;
            for (arguments.items) |argument| {
                argument.setTypeNode(self.nodeType(try argument.accept(self.visitor)));
            }

            try self.checkParametersTypes(node_span, arguments, parameters, function_type.has_varargs, function_type.varargs_type, function_type.implicit_parameters_count);

            node.setTypeNode(function_ptr_type.base_type);
            return self.allocReturn(ds.Any, ds.Any{ .Type = function_type.return_type });
        }

        if (callee_type == .Dot) {
            const dot_function_type = self.nodeType(try callee.dot_expression.accept(self.visitor));
            const function_ptr_type = dot_function_type.Pointer;
            const function_type = function_ptr_type.base_type.Function;

            const parameters = function_type.parameters;
            const arguments = node.arguments;
            for (arguments.items) |argument| {
                argument.setTypeNode(self.nodeType(try argument.accept(self.visitor)));
            }

            try self.checkParametersTypes(node_span, arguments, parameters, function_type.has_varargs, function_type.varargs_type, function_type.implicit_parameters_count);

            node.setTypeNode(function_ptr_type.base_type);
            return self.allocReturn(ds.Any, ds.Any{ .Type = function_type.return_type });
        }

        try self.context.diagnostics.reportError(node_span, "Unexpected callee type for Call Expression");
        return error.Stop;
    }

    fn checkMissingReturnStatement(self: *TypeChecker, node: *ast.Statement) bool {
        log("Checking missing return statement", .{}, .{ .module = .TypeChecker });
        if (node.getAstNodeType() == .Return) {
            return true;
        }

        const body = node.block_statement;
        const statements = body.statements;

        if (statements.items.len == 0) {
            return false;
        }

        if (statements.getLast().getAstNodeType() == .Return) {
            return true;
        }

        const len = statements.items.len;
        var i: usize = len - 1;
        // for (len..0) |i| {
        while (i >= 0) : (i -= 1) {
            const statement = statements.items[i];
            const node_kind = statement.getAstNodeType();
            if (node_kind == .Block and self.checkMissingReturnStatement(statement)) {
                return true;
            } else if (node_kind == .IfStatement) {
                var is_covered = false;
                const if_statement = statement.if_statement;
                for (if_statement.conditional_blocks.items) |branch| {
                    is_covered = self.checkMissingReturnStatement(branch.body);
                    if (!is_covered) {
                        break;
                    }
                }

                if (is_covered and if_statement.has_else) {
                    return true;
                }
            } else if (node_kind == .SwitchStatement) {
                const switch_statement = statement.switch_statement;
                if (!switch_statement.has_default_case) {
                    return false;
                }
                if (!self.checkMissingReturnStatement(switch_statement.cases.items[switch_statement.cases.items.len - 1].body)) {
                    continue;
                }

                var is_cases_covered = false;
                for (switch_statement.cases.items) |switch_case| {
                    is_cases_covered = self.checkMissingReturnStatement(switch_case.body);
                    if (!is_cases_covered) {
                        break;
                    }
                }

                if (is_cases_covered) {
                    return true;
                }
            }
        }
        return false;
    }

    fn allocReturn(self: *TypeChecker, comptime T: type, value: T) Error!*T {
        const ptr = try self.allocator.create(T);
        ptr.* = value;
        return ptr;
    }
};
