const std = @import("std");
const llvm = @import("llvm/llvm-zig.zig");
const llvm_core = llvm.core;
const llvm_types = llvm.types;
const llvm_analysis = llvm.analysis;
const llvm_target = llvm.target;
const ast = @import("ast.zig");
const types = @import("types.zig");
const tokenizer = @import("tokenizer.zig");
const ds = @import("data_structures.zig");
const Error = @import("diagnostics.zig").Error;
const CompilationUnit = ast.CompilationUnit;
const log = ds.log;

const PointerType = enum { Alloca, Load, GEP };

pub const LLVMBackend = struct {
    allocator: std.mem.Allocator,
    llvm_module: llvm_types.LLVMModuleRef,
    functions_table: std.StringArrayHashMap(*ast.FunctionPrototype),
    llvm_functions: std.StringArrayHashMap(llvm_types.LLVMValueRef),
    constants_string_pool: std.StringArrayHashMap(llvm_types.LLVMValueRef),
    structures_types_map: std.StringArrayHashMap(llvm_types.LLVMTypeRef),
    function_declarations: std.StringArrayHashMap(*ast.FunctionDeclaration),
    generic_types: std.StringArrayHashMap(*types.Type),
    defer_calls_stack: std.ArrayList(ds.ScopedList(*DeferCall)),
    alloca_inst_table: ds.ScopedMap(*ds.Any),
    break_blocks_stack: std.ArrayList(llvm_types.LLVMBasicBlockRef),
    continue_blocks_stack: std.ArrayList(llvm_types.LLVMBasicBlockRef),
    current_struct_type: llvm_types.LLVMTypeRef,
    has_return_statement: bool = false,
    has_break_or_continue_statement: bool = false,
    is_on_global_scope: bool = true,
    lambda_unique_id: usize = 0,
    lambda_extra_parameters: std.StringArrayHashMap(std.ArrayList([]const u8)),
    function_types_map: std.StringArrayHashMap(llvm_types.LLVMTypeRef),
    visitor: *ast.TreeVisitor = undefined,

    var llvm_context: llvm_types.LLVMContextRef = undefined;
    var builder: llvm_types.LLVMBuilderRef = undefined;

    var llvm_int1_type: llvm_types.LLVMTypeRef = undefined;
    var llvm_int8_type: llvm_types.LLVMTypeRef = undefined;
    var llvm_int16_type: llvm_types.LLVMTypeRef = undefined;
    var llvm_int32_type: llvm_types.LLVMTypeRef = undefined;
    var llvm_int64_type: llvm_types.LLVMTypeRef = undefined;
    var llvm_int64_ptr_type: llvm_types.LLVMTypeRef = undefined;
    var llvm_int8_ptr_type: llvm_types.LLVMTypeRef = undefined;
    var llvm_float32_type: llvm_types.LLVMTypeRef = undefined;
    var llvm_float64_type: llvm_types.LLVMTypeRef = undefined;
    var llvm_void_type: llvm_types.LLVMTypeRef = undefined;
    var llvm_void_ptr_type: llvm_types.LLVMTypeRef = undefined;

    var zero_int32_value: llvm_types.LLVMValueRef = undefined;
    var false_value: llvm_types.LLVMValueRef = undefined;
    var true_value: llvm_types.LLVMValueRef = undefined;
    var llvm_intrinsics_map: std.StringArrayHashMap(c_uint) = undefined;

    pub fn init(allocator: std.mem.Allocator) !*LLVMBackend {
        llvm_context = llvm_core.LLVMContextCreate();
        builder = llvm_core.LLVMCreateBuilderInContext(llvm_context);

        llvm_int1_type = llvm_core.LLVMInt1TypeInContext(llvm_context);
        llvm_int8_type = llvm_core.LLVMInt8TypeInContext(llvm_context);
        llvm_int16_type = llvm_core.LLVMInt16TypeInContext(llvm_context);
        llvm_int32_type = llvm_core.LLVMInt32TypeInContext(llvm_context);
        llvm_int64_type = llvm_core.LLVMInt64TypeInContext(llvm_context);
        llvm_int64_ptr_type = llvm_core.LLVMPointerType(llvm_int64_type, 0);
        llvm_int8_ptr_type = llvm_core.LLVMPointerType(llvm_int8_type, 0);
        llvm_float32_type = llvm_core.LLVMFloatTypeInContext(llvm_context);
        llvm_float64_type = llvm_core.LLVMDoubleTypeInContext(llvm_context);
        llvm_void_type = llvm_core.LLVMVoidTypeInContext(llvm_context);
        llvm_void_ptr_type = llvm_core.LLVMPointerType(llvm_int8_type, 0);

        zero_int32_value = llvm_core.LLVMConstInt(llvm_int32_type, 0, 0);
        false_value = llvm_core.LLVMConstInt(llvm_int1_type, 0, 0);
        true_value = llvm_core.LLVMConstInt(llvm_int1_type, 1, 0);
        llvm_intrinsics_map = std.StringArrayHashMap(c_uint).init(allocator);

        var alloca_inst_table = ds.ScopedMap(*ds.Any).init(allocator);
        try alloca_inst_table.pushNewScope();
        var self = try allocator.create(LLVMBackend);
        self.* = LLVMBackend{
            .allocator = allocator,
            .llvm_module = null,
            .functions_table = std.StringArrayHashMap(*ast.FunctionPrototype).init(allocator),
            .llvm_functions = std.StringArrayHashMap(llvm_types.LLVMValueRef).init(allocator),
            .constants_string_pool = std.StringArrayHashMap(llvm_types.LLVMValueRef).init(allocator),
            .structures_types_map = std.StringArrayHashMap(llvm_types.LLVMTypeRef).init(allocator),
            .function_declarations = std.StringArrayHashMap(*ast.FunctionDeclaration).init(allocator),
            .generic_types = std.StringArrayHashMap(*types.Type).init(allocator),
            .defer_calls_stack = std.ArrayList(ds.ScopedList(*DeferCall)).init(allocator),
            .alloca_inst_table = alloca_inst_table,
            .break_blocks_stack = std.ArrayList(llvm_types.LLVMBasicBlockRef).init(allocator),
            .continue_blocks_stack = std.ArrayList(llvm_types.LLVMBasicBlockRef).init(allocator),
            .current_struct_type = null,
            .lambda_extra_parameters = std.StringArrayHashMap(std.ArrayList([]const u8)).init(allocator),
            .function_types_map = std.StringArrayHashMap(llvm_types.LLVMTypeRef).init(allocator),
        };

        self.visitor = try self.getVisitor();
        return self;
    }
    fn allocReturn(self: *Self, comptime T: type, value: T) Error!*T {
        const ptr = try self.allocator.create(T);
        ptr.* = value;
        return ptr;
    }

    fn getVisitor(self: *LLVMBackend) !*ast.TreeVisitor {
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

    const Self = @This();

    pub fn updateIntrinsics(self: *Self) !void {
        var param_types = [_]llvm_types.LLVMTypeRef{llvm_float64_type};
        const fn_type = llvm_core.LLVMFunctionType(llvm_float64_type, @ptrCast(&param_types), 1, 0);
        const cos_fn = llvm_core.LLVMAddFunction(self.llvm_module, self.cStr("llvm.cos"), fn_type);
        try self.function_types_map.put("llvm.cos.f64", fn_type);
        const id = llvm_core.LLVMGetIntrinsicID(cos_fn);

        try llvm_intrinsics_map.put("llvm.cos", id);
    }

    pub fn compile(self: *Self, module_name: []const u8, compilation_unit: *CompilationUnit) !llvm_types.LLVMModuleRef {
        log("Compiling module '{s}'", .{module_name});
        self.llvm_module = llvm_core.LLVMModuleCreateWithNameInContext(self.cStr(module_name), llvm_context);

        try self.updateIntrinsics();

        for (compilation_unit.tree_nodes.items) |statement| {
            _ = try statement.accept(self.visitor);
        }

        return self.llvm_module;
    }

    pub fn visitBlockStatement(self: *Self, node: *ast.BlockStatement) !*ds.Any {
        log("Visiting block statement", .{});
        try self.pushAllocaInstScope();
        try self.defer_calls_stack.items[self.defer_calls_stack.items.len - 1].pushNewScope();
        var should_execute_defers = true;
        for (node.statements.items) |statement| {
            const ast_node_type = statement.getAstNodeType();
            if (ast_node_type == .Return) {
                should_execute_defers = false;
                self.executeAllDeferCalls();
            }

            _ = try statement.accept(self.visitor);

            if (ast_node_type == .Return or ast_node_type == .Break or ast_node_type == .Continue) {
                break;
            }
        }

        if (should_execute_defers) {
            self.executeScopeDeferCalls();
        }

        self.defer_calls_stack.items[self.defer_calls_stack.items.len - 1].popCurrentScope();
        self.popAllocaInstScope();
        return self.allocReturn(ds.Any, .Void);
    }

    pub fn visitFieldDeclaration(self: *Self, node: *ast.FieldDeclaration) !*ds.Any {
        log("Visiting field declaration", .{});
        const var_name = node.name.literal;
        var field_type = node.field_type;
        if (field_type.typeKind() == .GenericParameter) {
            const generic = field_type.GenericParameter;
            field_type = self.generic_types.get(generic.name).?;
        }

        var llvm_type: llvm_types.LLVMTypeRef = undefined;
        if (field_type.typeKind() == .GenericStruct) {
            const generic_type = field_type.GenericStruct;
            llvm_type = try self.resolveGenericStruct(&generic_type);
        } else {
            llvm_type = try self.llvmTypeFromLangType(field_type);
        }

        if (node.is_global) {
            var constants_value: llvm_types.LLVMValueRef = undefined;
            if (node.value == null) {
                constants_value = llvm_core.LLVMConstNull(try self.llvmTypeFromLangType(field_type));
            } else {
                constants_value = try self.resolveConstantExpression(node.value);
            }
            const global_variable = llvm_core.LLVMAddGlobal(self.llvm_module, llvm_type, self.cStr(var_name));
            llvm_core.LLVMSetInitializer(global_variable, constants_value);
            llvm_core.LLVMSetLinkage(global_variable, .LLVMExternalLinkage);
            llvm_core.LLVMSetGlobalConstant(global_variable, 0);
            llvm_core.LLVMSetAlignment(global_variable, 0);

            return self.allocReturn(ds.Any, .Void);
        }

        var value: llvm_types.LLVMValueRef = undefined;
        if (node.value == null) {
            value = llvm_core.LLVMConstNull(try self.llvmTypeFromLangType(field_type));
        } else {
            value = try self.llvmNodeValue(try node.value.?.accept(self.visitor));
        }

        debugV(value);

        const current_function = llvm_core.LLVMGetBasicBlockParent(llvm_core.LLVMGetInsertBlock(builder));
        const value_type = llvm_core.LLVMTypeOf(value);

        debugT(llvm_type);
        debugT(value_type);

        //  Very Questionable set of ifs
        const pointer_type = llvm_core.LLVMGetElementType(value_type); // Probably wrong
        debugT(pointer_type);

        if (value_type == llvm_type or pointer_type == llvm_type) {
            var init_value = value;
            const init_value_type = llvm_core.LLVMTypeOf(value);

            if (init_value_type != llvm_type and pointer_type == llvm_type) {
                init_value = dereferencesLLVMPointer(init_value, .Load);
            }
            const alloc_inst = try self.createEntryBlockAlloca(current_function, var_name, llvm_type);
            _ = llvm_core.LLVMBuildStore(builder, init_value, alloc_inst);
            _ = self.alloca_inst_table.define(var_name, try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = alloc_inst }));
        } else if (llvm_core.LLVMIsAPHINode(value) != null or llvm_core.LLVMIsALoadInst(value) != null or llvm_core.LLVMIsAUndefValue(value) != null or llvm_core.LLVMIsAConstantInt(value) != null or llvm_core.LLVMIsAConstant(value) != null or llvm_core.LLVMIsACallInst(value) != null) {
            const alloc_inst = try self.createEntryBlockAlloca(current_function, var_name, llvm_type);
            debugV(value);
            debugV(alloc_inst);
            _ = llvm_core.LLVMBuildStore(builder, value, alloc_inst);
            _ = self.alloca_inst_table.define(var_name, try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = alloc_inst }));
        } else if (llvm_core.LLVMIsAAllocaInst(value) != null) {
            const allocated_type = llvm_core.LLVMGetAllocatedType(value);
            _ = llvm_core.LLVMBuildLoad2(builder, allocated_type, value, self.cStr(var_name));
            _ = self.alloca_inst_table.define(var_name, try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = value }));
        } else if (llvm_core.LLVMIsAFunction(value) != null) {
            try self.llvm_functions.put(var_name, value);
            const func_type = llvm_core.LLVMTypeOf(value);
            const alloc_inst = try self.createEntryBlockAlloca(current_function, var_name, func_type);
            _ = llvm_core.LLVMBuildStore(builder, value, alloc_inst);
            _ = self.alloca_inst_table.define(var_name, try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = alloc_inst }));
        } else {
            self.internalCompilerError("Unknown value type");
        }
        return self.allocReturn(ds.Any, .Void);
    }

    pub fn visitDestructuringDeclaration(self: *Self, node: *ast.DestructuringDeclaration) !*ds.Any {
        log("Visiting destructuring declaration", .{});
        const tuple_value = try self.llvmNodeValue(try node.value.accept(self.visitor));
        const tuple_type = try self.llvmTypeFromLangType(node.value.getTypeNode().?);

        const variable_names = node.names;
        const variable_types = node.value_types;
        const elements_count = variable_names.items.len;
        const current_function = llvm_core.LLVMGetBasicBlockParent(llvm_core.LLVMGetInsertBlock(builder));

        for (0..elements_count) |i| {
            const variable_name = variable_names.items[i].literal;
            const variable_type = try self.llvmTypeFromLangType(variable_types.items[i]);

            const alloc_inst = try self.createEntryBlockAlloca(current_function, variable_name, variable_type);

            const value = try self.accessStructMemberPointer(tuple_value, tuple_type, @intCast(i));
            const loaded_value = dereferencesLLVMPointer(value, .Load);

            _ = llvm_core.LLVMBuildStore(builder, loaded_value, alloc_inst);
            _ = self.alloca_inst_table.define(variable_name, try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = alloc_inst }));
        }

        return self.allocReturn(ds.Any, .Void);
    }

    pub fn visitConstDeclaration(self: *Self, node: *ast.ConstDeclaration) !*ds.Any {
        log("Visiting const declaration", .{});
        _ = node;
        return self.allocReturn(ds.Any, .Void);
    }

    pub fn visitFunctionPrototype(self: *Self, node: *ast.FunctionPrototype) !*ds.Any {
        log("Visiting function prototype", .{});
        const parameters = node.parameters;
        const parameters_size = parameters.items.len;
        var arguments = std.ArrayList(llvm_types.LLVMTypeRef).init(self.allocator);
        try arguments.resize(parameters_size);

        for (0..parameters_size) |i| {
            arguments.items[i] = try self.llvmTypeFromLangType(parameters.items[i].parameter_type);
        }

        const return_type = try self.llvmTypeFromLangType(node.return_type.?);
        const function_type = llvm_core.LLVMFunctionType(return_type, @ptrCast(arguments.items), @intCast(parameters_size), @intFromBool(node.has_varargs));
        const function_name = node.name.literal;
        var linkage = llvm_types.LLVMLinkage.LLVMInternalLinkage;
        if (node.is_external or std.mem.eql(u8, function_name, "main")) {
            linkage = llvm_types.LLVMLinkage.LLVMExternalLinkage;
        }

        const function = llvm_core.LLVMAddFunction(self.llvm_module, self.cStr(function_name), function_type);
        llvm_core.LLVMSetLinkage(function, linkage);
        try self.function_types_map.put(function_name, function_type);

        var index: usize = 0;
        var argument = llvm_core.LLVMGetFirstParam(function);
        while (argument != null) : (argument = llvm_core.LLVMGetNextParam(argument)) {
            if (index >= parameters_size) {
                break;
            }
            llvm_core.LLVMSetValueName2(argument, self.cStr(parameters.items[index].name.literal), parameters.items[index].name.literal.len);
            index += 1;
        }

        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = function });
    }

    pub fn visitOperatorFunctionDeclaration(self: *Self, node: *ast.OperatorFunctionDeclaration) !*ds.Any {
        log("Visiting operator function declaration", .{});
        return node.function.accept(self.visitor);
    }

    pub fn visitIntrinsicPrototype(self: *Self, node: *ast.IntrinsicPrototype) !*ds.Any {
        log("Visiting intrinsic prototype", .{});
        const name = node.name.literal;
        const prototype_parameters = node.parameters;
        var parameters_types = std.ArrayList(llvm_types.LLVMTypeRef).init(self.allocator);

        for (prototype_parameters.items) |parameter| {
            const parameter_type = try self.llvmTypeFromLangType(parameter.parameter_type);
            _ = try parameters_types.append(parameter_type);
        }

        const native_name = node.native_name;
        if (!llvm_intrinsics_map.contains(native_name)) {
            self.internalCompilerError("Intrinsic not found");
        }

        const intrinsic_id = llvm_intrinsics_map.get(native_name).?;
        const function = llvm_core.LLVMGetIntrinsicDeclaration(self.llvm_module, intrinsic_id, @ptrCast(parameters_types.items), @intCast(parameters_types.items.len));
        try self.llvm_functions.put(name, function);

        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = function });
    }

    pub fn visitFunctionDeclaration(self: *Self, node: *ast.FunctionDeclaration) !*ds.Any {
        log("Visiting function declaration", .{});
        self.is_on_global_scope = false;
        const prototype = node.prototype;
        const name = prototype.name.literal;
        if (prototype.is_generic) {
            try self.function_declarations.put(name, node);
            return self.allocReturn(ds.Any, ds.Any{ .U32 = 0 });
        }

        try self.functions_table.put(name, prototype);

        const function = (try prototype.accept(self.visitor)).LLVMValue;

        const entry_block = llvm_core.LLVMAppendBasicBlock(function, @ptrCast("entry"));
        llvm_core.LLVMPositionBuilderAtEnd(builder, entry_block);

        try self.defer_calls_stack.append(ds.ScopedList(*DeferCall).init(self.allocator));
        try self.pushAllocaInstScope();

        var arg = llvm_core.LLVMGetFirstParam(function);
        while (arg != null) : (arg = llvm_core.LLVMGetNextParam(arg)) {
            const arg_name = llvm_core.LLVMGetValueName(arg);
            const arg_type = llvm_core.LLVMTypeOf(arg);
            const alloca_inst = try self.createEntryBlockAlloca(function, std.mem.span(arg_name), arg_type);
            _ = self.alloca_inst_table.define(std.mem.span(arg_name), try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = alloca_inst }));
            _ = llvm_core.LLVMBuildStore(builder, arg, alloca_inst);
        }

        const body = node.body;
        _ = try body.accept(self.visitor);

        self.popAllocaInstScope();
        _ = self.defer_calls_stack.pop();

        _ = self.alloca_inst_table.define(name, try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = function }));

        if (body.getAstNodeType() == .Block) {
            const statements = body.block_statement.statements;
            log("Return Statement: {any}", .{statements.getLast().getAstNodeType()});
            if (statements.items.len == 0 or (statements.getLast().getAstNodeType() != .Return)) {
                _ = llvm_core.LLVMBuildUnreachable(builder);
            }
        }
        self.debugModule();
        _ = llvm_analysis.LLVMVerifyFunction(function, .LLVMAbortProcessAction);
        // _ = llvm_analysis.LLVMVerifyFunction(function, .LLVMPrintMessageAction);

        self.has_return_statement = false;
        self.is_on_global_scope = true;
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = function });
    }

    pub fn visitStructDeclaration(self: *Self, node: *ast.StructDeclaration) !*ds.Any {
        log("Visiting struct declaration", .{});
        const struct_type = node.struct_type;
        if (struct_type.Struct.is_generic) {
            return self.allocReturn(ds.Any, .Void);
        }

        const struct_name = struct_type.Struct.name;
        const ret_type = try self.createLLVMStructType(struct_name, struct_type.Struct.field_types.items, struct_type.Struct.is_packed, struct_type.Struct.is_extern);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMType = ret_type });
    }

    pub fn visitEnumDeclaration(self: *Self, node: *ast.EnumDeclaration) !*ds.Any {
        _ = node;
        log("Visiting enum declaration", .{});
        return self.allocReturn(ds.Any, .Void);
    }

    pub fn visitIfStatement(self: *Self, node: *ast.IfStatement) !*ds.Any {
        log("Visiting if statement", .{});
        const current_function = llvm_core.LLVMGetBasicBlockParent(llvm_core.LLVMGetInsertBlock(builder));
        const start_block = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("if.start"));
        const end_block = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("if.end"));

        _ = llvm_core.LLVMBuildBr(builder, start_block);
        llvm_core.LLVMAppendExistingBasicBlock(current_function, start_block);
        llvm_core.LLVMPositionBuilderAtEnd(builder, start_block);

        const conditional_blocks = node.conditional_blocks;
        const conditional_blocks_size = conditional_blocks.items.len;
        for (0..conditional_blocks_size) |i| {
            const true_block = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("if.true"));
            llvm_core.LLVMAppendExistingBasicBlock(current_function, true_block);

            var false_branch = end_block;
            if (i + 1 < conditional_blocks_size) {
                false_branch = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("if.false"));
                llvm_core.LLVMAppendExistingBasicBlock(current_function, false_branch);
            }

            const condition = try self.llvmResolveValue(try conditional_blocks.items[i].condition.accept(self.visitor));
            _ = llvm_core.LLVMBuildCondBr(builder, condition, true_block, false_branch);
            llvm_core.LLVMPositionBuilderAtEnd(builder, true_block);

            try self.pushAllocaInstScope();
            _ = try conditional_blocks.items[i].body.accept(self.visitor);
            self.popAllocaInstScope();
            if (!self.has_break_or_continue_statement and !self.has_return_statement) {
                _ = llvm_core.LLVMBuildBr(builder, end_block);
            } else {
                self.has_return_statement = false;
            }

            llvm_core.LLVMPositionBuilderAtEnd(builder, false_branch);
        }

        llvm_core.LLVMAppendExistingBasicBlock(current_function, end_block);

        if (self.has_break_or_continue_statement) {
            self.has_break_or_continue_statement = false;
        } else {
            llvm_core.LLVMPositionBuilderAtEnd(builder, end_block);
        }

        return self.allocReturn(ds.Any, .Void);
    }

    pub fn visitSwitchExpression(self: *Self, node: *ast.SwitchExpression) !*ds.Any {
        log("Visiting switch expression", .{});
        if (self.isGlobalBlock() and node.isConstant()) {
            const ret = try self.resolveConstantSwitchExpression(node);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        const cases = node.switch_cases;
        const values = node.switch_case_values;
        const else_branch = node.default_value;

        const block_counts = cases.items.len;

        var total_blocks_counts = block_counts;
        if (else_branch != null) {
            total_blocks_counts += 1;
        }

        const value_type = try self.llvmTypeFromLangType(node.getTypeNode().?);
        const function = llvm_core.LLVMGetBasicBlockParent(llvm_core.LLVMGetInsertBlock(builder));
        const argument = try self.llvmResolveValue(try node.argument.accept(self.visitor));
        var llvm_values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);
        var llvm_branches = std.ArrayList(llvm_types.LLVMBasicBlockRef).init(self.allocator);
        try llvm_values.resize(block_counts);
        try llvm_branches.resize(total_blocks_counts);

        for (0..block_counts) |i| {
            llvm_branches.items[i] = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("case"));
            llvm_values.items[i] = try self.llvmResolveValue(try values.items[i].accept(self.visitor));
        }

        if (else_branch != null) {
            try llvm_values.append(try self.llvmResolveValue(try else_branch.?.accept(self.visitor)));
            llvm_branches.items[block_counts] = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("else"));
        }

        const merge_branch = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr(""));

        const first_branch = llvm_branches.items[0];

        _ = llvm_core.LLVMBuildBr(builder, first_branch);
        llvm_core.LLVMAppendExistingBasicBlock(function, first_branch);
        llvm_core.LLVMPositionBuilderAtEnd(builder, first_branch);

        for (1..total_blocks_counts) |i| {
            const current_branch = llvm_branches.items[i];
            const case_value = try self.llvmNodeValue(try cases.items[i - 1].accept(self.visitor));
            const condition = self.createLLVMIntegersComparison(node.op, argument, case_value);
            _ = llvm_core.LLVMBuildCondBr(builder, condition, current_branch, merge_branch);
            llvm_core.LLVMAppendExistingBasicBlock(function, current_branch);
            llvm_core.LLVMPositionBuilderAtEnd(builder, current_branch);
        }

        _ = llvm_core.LLVMBuildBr(builder, merge_branch);
        llvm_core.LLVMAppendExistingBasicBlock(function, merge_branch);
        llvm_core.LLVMPositionBuilderAtEnd(builder, merge_branch);

        const phi_node = llvm_core.LLVMBuildPhi(builder, value_type, self.cStr(""));
        for (0..total_blocks_counts) |i| {
            llvm_core.LLVMAddIncoming(phi_node, @ptrCast(&llvm_values.items[i]), @ptrCast(&llvm_branches.items[i]), 1);
        }
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = phi_node });
    }

    pub fn visitForRangeStatement(self: *Self, node: *ast.ForRangeStatement) !*ds.Any {
        log("Visiting for range statement", .{});
        var start = try self.llvmResolveValue(try node.range_start.accept(self.visitor));
        var end = try self.llvmResolveValue(try node.range_end.accept(self.visitor));

        var step: llvm_types.LLVMValueRef = undefined;
        if (node.step != null) {
            step = try self.llvmResolveValue(try node.step.?.accept(self.visitor));
        } else {
            const node_type = node.range_start.getTypeNode().?;
            const number_type = node_type.Number;
            step = try self.llvmNumberValue("1", number_type.number_kind);
        }

        start = try self.createLLVMNumbersBinary(.Minus, start, step);
        end = try self.createLLVMNumbersBinary(.Minus, end, step);

        const element_llvm_type = llvm_core.LLVMTypeOf(start);

        const condition_block = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("for.cond"));
        const body_block = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("for.body"));
        const end_block = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("for.end"));

        try self.break_blocks_stack.append(end_block);
        try self.continue_blocks_stack.append(condition_block);

        try self.pushAllocaInstScope();

        const var_name = node.element_name;
        const current_function = llvm_core.LLVMGetBasicBlockParent(llvm_core.LLVMGetInsertBlock(builder));
        const alloc_inst = try self.createEntryBlockAlloca(current_function, var_name, element_llvm_type);
        _ = llvm_core.LLVMBuildStore(builder, start, alloc_inst);
        _ = self.alloca_inst_table.define(var_name, try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = alloc_inst }));
        _ = llvm_core.LLVMBuildBr(builder, condition_block);

        llvm_core.LLVMAppendExistingBasicBlock(current_function, condition_block);
        llvm_core.LLVMPositionBuilderAtEnd(builder, condition_block);
        const variable = dereferencesLLVMPointer(alloc_inst, .Alloca);
        const condition = self.createLLVMIntegersComparison(.SmallerEqual, variable, end);
        _ = llvm_core.LLVMBuildCondBr(builder, condition, body_block, end_block);

        llvm_core.LLVMAppendExistingBasicBlock(current_function, body_block);
        llvm_core.LLVMPositionBuilderAtEnd(builder, body_block);

        const value_ptr = llvm_core.LLVMBuildLoad2(builder, llvm_core.LLVMGetAllocatedType(alloc_inst), alloc_inst, self.cStr(""));
        const new_value = try self.createLLVMNumbersBinary(.Plus, value_ptr, step);
        _ = llvm_core.LLVMBuildStore(builder, new_value, alloc_inst);

        _ = try node.body.accept(self.visitor);

        if (self.has_break_or_continue_statement) {
            self.has_break_or_continue_statement = false;
        } else {
            _ = llvm_core.LLVMBuildBr(builder, condition_block);
        }

        llvm_core.LLVMAppendExistingBasicBlock(current_function, end_block);
        llvm_core.LLVMPositionBuilderAtEnd(builder, end_block);

        _ = self.break_blocks_stack.pop();
        _ = self.continue_blocks_stack.pop();

        return self.allocReturn(ds.Any, .Void);
    }

    pub fn visitForEachStatement(self: *Self, node: *ast.ForEachStatement) !*ds.Any {
        log("Visiting for each statement", .{});
        var collection_expression = node.collection;
        const collection_exp_type = collection_expression.getTypeNode().?;
        const collection_value = try collection_expression.accept(self.visitor);
        const collection = try self.llvmResolveValue(collection_value);
        const collection_type = llvm_core.LLVMTypeOf(collection);

        if (isArrayTy(collection_type) and llvm_core.LLVMGetArrayLength(collection_type) == 0) {
            return self.allocReturn(ds.Any, .Void);
        }

        const is_foreach_string = types.isTypesEquals(collection_exp_type, &types.Type.I8_PTR_TYPE);
        const zero_value = llvm_core.LLVMConstInt(llvm_int64_type, 0, 1);
        const step = llvm_core.LLVMConstInt(llvm_int64_type, 1, 1);

        var length: llvm_types.LLVMValueRef = undefined;
        if (is_foreach_string) {
            length = try self.createLLVMStringLength(collection);
        } else if (isVectorTy(collection_type)) {
            const vector_type = collection_exp_type.StaticVector;
            const array_count = vector_type.array.size;
            length = llvm_core.LLVMConstInt(llvm_int64_type, array_count, 1);
        } else {
            const num_elements = llvm_core.LLVMGetArrayLength(collection_type);
            length = llvm_core.LLVMConstInt(llvm_int64_type, num_elements, 1);
        }

        const end = self.createLLVMIntegersBinary(.Minus, length, step);
        const condition_block = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("for.cond"));
        const body_block = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("for.body"));
        const end_block = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("for.end"));

        try self.break_blocks_stack.append(end_block);
        try self.continue_blocks_stack.append(condition_block);

        try self.pushAllocaInstScope();

        const index_name = node.index_name;
        const current_function = llvm_core.LLVMGetBasicBlockParent(llvm_core.LLVMGetInsertBlock(builder));
        const index_alloca = try self.createEntryBlockAlloca(current_function, index_name, llvm_int64_type);
        _ = llvm_core.LLVMBuildStore(builder, zero_value, index_alloca);
        _ = self.alloca_inst_table.define(index_name, try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = index_alloca }));

        var element_alloca: llvm_types.LLVMValueRef = undefined;
        const element_name = node.element_name;

        var element_type: llvm_types.LLVMTypeRef = undefined;
        if (collection_exp_type.typeKind() == .StaticVector) {
            const vector_type = collection_exp_type.StaticVector;
            element_type = try self.llvmTypeFromLangType(vector_type.array.element_type.?);
        } else if (isArrayTy(collection_type)) {
            element_type = llvm_core.LLVMGetElementType(collection_type);
        } else {
            element_type = llvm_int8_type;
        }

        if (!std.mem.eql(u8, "_", node.element_name)) {
            element_alloca = try self.createEntryBlockAlloca(current_function, element_name, element_type);
        }

        _ = llvm_core.LLVMBuildBr(builder, condition_block);
        llvm_core.LLVMAppendExistingBasicBlock(current_function, condition_block);
        llvm_core.LLVMPositionBuilderAtEnd(builder, condition_block);

        const variable = dereferencesLLVMPointer(index_alloca, .Alloca);
        const condition = self.createLLVMIntegersComparison(.Smaller, variable, end);
        _ = llvm_core.LLVMBuildCondBr(builder, condition, body_block, end_block);

        llvm_core.LLVMAppendExistingBasicBlock(current_function, body_block);
        llvm_core.LLVMPositionBuilderAtEnd(builder, body_block);

        const index_alloca_type = llvm_core.LLVMGetAllocatedType(index_alloca);
        const value_ptr = llvm_core.LLVMBuildLoad2(builder, index_alloca_type, index_alloca, self.cStr("value"));
        const new_value = try self.createLLVMNumbersBinary(.Plus, value_ptr, step);
        _ = llvm_core.LLVMBuildStore(builder, new_value, index_alloca);

        if (node.collection.getAstNodeType() == .Array) {
            const temp_name = "temp";
            const temp_alloca = try self.createEntryBlockAlloca(current_function, temp_name, collection_type);
            _ = llvm_core.LLVMBuildStore(builder, collection, temp_alloca);
            _ = self.alloca_inst_table.define(temp_name, try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = temp_alloca }));
            const location = tokenizer.TokenSpan{ .file_id = 0, .line_number = 1, .column_end = 1, .column_start = 1 };
            const token = tokenizer.Token{ .kind = .Identifier, .position = location, .literal = temp_name };
            collection_expression = try self.allocReturn(ast.Expression, ast.Expression{ .literal_expression = ast.LiteralExpression.init(token) });
            collection_expression.setTypeNode(node.collection.getTypeNode().?);
        }

        if (!std.mem.eql(u8, "_", element_name)) {
            const current_index = dereferencesLLVMPointer(index_alloca, .Alloca);
            const value = try self.accessArrayElement(collection_expression, current_index);
            _ = llvm_core.LLVMBuildStore(builder, value, element_alloca);
            _ = self.alloca_inst_table.define(element_name, try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = element_alloca }));
        }

        _ = try node.body.accept(self.visitor);
        self.popAllocaInstScope();

        if (self.has_break_or_continue_statement) {
            self.has_break_or_continue_statement = false;
        } else {
            _ = llvm_core.LLVMBuildBr(builder, condition_block);
        }

        _ = llvm_core.LLVMAppendExistingBasicBlock(current_function, end_block);
        llvm_core.LLVMPositionBuilderAtEnd(builder, end_block);

        _ = self.break_blocks_stack.pop();
        _ = self.continue_blocks_stack.pop();

        return self.allocReturn(ds.Any, .Void);
    }

    pub fn visitForeverStatement(self: *Self, node: *ast.ForEverStatement) !*ds.Any {
        log("Visiting forever statement", .{});
        _ = node;
        _ = self;
        return Error.NotImplemented;
    }

    pub fn visitWhileStatement(self: *Self, node: *ast.WhileStatement) !*ds.Any {
        log("Visiting while statement", .{});
        const current_function = llvm_core.LLVMGetBasicBlockParent(llvm_core.LLVMGetInsertBlock(builder));
        const condition_branch = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("while.condition"));
        const loop_branch = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("while.loop"));
        const end_branch = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("while.end"));

        try self.break_blocks_stack.append(end_branch);
        try self.continue_blocks_stack.append(condition_branch);

        _ = llvm_core.LLVMBuildBr(builder, condition_branch);
        llvm_core.LLVMAppendExistingBasicBlock(current_function, condition_branch);
        llvm_core.LLVMPositionBuilderAtEnd(builder, condition_branch);

        const condition = try self.llvmResolveValue(try node.condition.accept(self.visitor));
        _ = llvm_core.LLVMBuildCondBr(builder, condition, loop_branch, end_branch);

        llvm_core.LLVMAppendExistingBasicBlock(current_function, loop_branch);
        llvm_core.LLVMPositionBuilderAtEnd(builder, loop_branch);

        try self.pushAllocaInstScope();
        _ = try node.body.accept(self.visitor);
        self.popAllocaInstScope();

        if (self.has_break_or_continue_statement) {
            self.has_break_or_continue_statement = false;
        } else {
            _ = llvm_core.LLVMBuildBr(builder, condition_branch);
        }

        _ = llvm_core.LLVMAppendExistingBasicBlock(current_function, end_branch);
        llvm_core.LLVMPositionBuilderAtEnd(builder, end_branch);

        if (self.break_blocks_stack.items.len > 0) {
            _ = self.break_blocks_stack.pop(); // Undefied behavior in C++ so we need to check if the stack is empty
        }
        if (self.continue_blocks_stack.items.len > 0) {
            _ = self.continue_blocks_stack.pop(); // Undefied behavior in C++ so we need to check if the stack is empty
        }

        return self.allocReturn(ds.Any, .Void);
    }

    pub fn visitSwitchStatement(self: *Self, node: *ast.SwitchStatement) !*ds.Any {
        log("Visiting switch statement", .{});
        const blocks_count = node.cases.items.len;
        var llvm_branches = std.ArrayList(llvm_types.LLVMBasicBlockRef).init(self.allocator);
        var llvm_values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);
        var bodies = std.ArrayList(*ast.Statement).init(self.allocator);

        for (0..blocks_count) |i| {
            const current_case = node.cases.items[i].values;
            for (current_case.items) |case_value| {
                try llvm_branches.append(llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("case")));
                try llvm_values.append(try self.llvmResolveValue(try case_value.accept(self.visitor)));
                try bodies.append(node.cases.items[i].body);
            }
        }

        const start_block = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("switch.start"));
        const end_block = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("switch.end"));
        const current_function = llvm_core.LLVMGetBasicBlockParent(llvm_core.LLVMGetInsertBlock(builder));

        _ = llvm_core.LLVMBuildBr(builder, start_block);
        llvm_core.LLVMAppendExistingBasicBlock(current_function, start_block);
        llvm_core.LLVMPositionBuilderAtEnd(builder, start_block);

        const argument = try self.llvmResolveValue(try node.argument.accept(self.visitor));

        for (0..blocks_count) |i| {
            const true_block = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("switch.true"));
            llvm_core.LLVMAppendExistingBasicBlock(current_function, true_block);

            var false_branch = end_block;
            if (i + 1 < blocks_count) {
                false_branch = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, self.cStr("switch.false"));
                llvm_core.LLVMAppendExistingBasicBlock(current_function, false_branch);
            }

            var condition: llvm_types.LLVMValueRef = undefined;
            if (node.has_default_case and (i == blocks_count - 1)) {
                condition = llvm_core.LLVMConstInt(llvm_int1_type, 1, 1);
            } else {
                condition = self.createLLVMIntegersComparison(node.op, argument, llvm_values.items[i]);
            }

            _ = llvm_core.LLVMBuildCondBr(builder, condition, true_block, false_branch);
            llvm_core.LLVMPositionBuilderAtEnd(builder, true_block);

            try self.pushAllocaInstScope();
            _ = try bodies.items[i].accept(self.visitor);
            self.popAllocaInstScope();

            if (!self.has_break_or_continue_statement and !self.has_return_statement) {
                _ = llvm_core.LLVMBuildBr(builder, end_block);
            } else {
                self.has_return_statement = false;
            }

            llvm_core.LLVMPositionBuilderAtEnd(builder, false_branch);
        }

        llvm_core.LLVMAppendExistingBasicBlock(current_function, end_block);

        if (self.has_break_or_continue_statement) {
            self.has_break_or_continue_statement = false;
        } else {
            llvm_core.LLVMPositionBuilderAtEnd(builder, end_block);
        }

        return self.allocReturn(ds.Any, .Void);
    }

    pub fn visitReturnStatement(self: *Self, node: *ast.ReturnStatement) !*ds.Any {
        log("Visiting return statement", .{});
        self.has_return_statement = true;

        if (!node.has_value) {
            const ret = llvm_core.LLVMBuildRetVoid(builder);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        const value = try self.llvmNodeValue(try node.value.?.accept(self.visitor));
        const value_kind = llvm_core.LLVMGetValueKind(value);

        if (llvm_core.LLVMIsAAllocaInst(value) != null) {
            const value_literal = llvm_core.LLVMBuildLoad2(builder, llvm_core.LLVMGetAllocatedType(value), value, @ptrCast(""));
            const ret = llvm_core.LLVMBuildRet(builder, value_literal);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        } else if (value_kind == .LLVMGlobalVariableValueKind) {
            const value_type = llvm_core.LLVMGetElementType(llvm_core.LLVMTypeOf(value));
            const value_literal = llvm_core.LLVMBuildLoad2(builder, value_type, value, @ptrCast(""));
            const ret = llvm_core.LLVMBuildRet(builder, value_literal);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        } else if (llvm_core.LLVMIsAPHINode(value) != null) {
            const expected_type = node.value.?.getTypeNode().?;
            const expected_llvm_type = try self.llvmTypeFromLangType(expected_type);

            if (llvm_core.LLVMTypeOf(value) == expected_llvm_type) {
                const ret = llvm_core.LLVMBuildRet(builder, value);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            }

            const phi_value = dereferencesLLVMPointer(value, .Load);
            const ret = llvm_core.LLVMBuildRet(builder, phi_value);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        } else {
            const ret = llvm_core.LLVMBuildRet(builder, value);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        self.internalCompilerError("Unexpected return type");

        unreachable;
    }

    pub fn visitDeferStatement(self: *Self, node: *ast.DeferStatement) !*ds.Any {
        log("Visiting defer statement", .{});
        const call_expression = node.call_expression;
        const callee = call_expression.call_expression.callee.literal_expression;
        const callee_literal = callee.name.literal;
        const function = try self.lookupFunction(callee_literal);
        if (function == null) {
            const value = try self.llvmNodeValue(self.alloca_inst_table.lookup(callee_literal).?);
            if (llvm_core.LLVMIsAAllocaInst(value) != null) {
                const loaded = llvm_core.LLVMBuildLoad2(builder, llvm_core.LLVMGetAllocatedType(value), value, self.cStr(""));
                const function_type = try self.llvmTypeFromLangType(call_expression.call_expression.getTypeNode().?);
                if (call_expression.call_expression.getTypeNode().?.typeKind() == .Function) {
                    const arguments = call_expression.call_expression.arguments;
                    const arguments_size = arguments.items.len;
                    var arguments_values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);
                    var param_types = std.ArrayList(llvm_types.LLVMTypeRef).init(self.allocator);
                    try param_types.resize(arguments_size);
                    llvm_core.LLVMGetParamTypes(function_type, @ptrCast(param_types.items));

                    for (0..arguments_size) |i| {
                        const value_ = try self.llvmNodeValue(try arguments.items[i].accept(self.visitor));
                        if (llvm_core.LLVMTypeOf(value_) == param_types.items[i]) {
                            _ = try arguments_values.append(value);
                        } else {
                            const expected_type = param_types.items[i];
                            const loaded_value = llvm_core.LLVMBuildLoad2(builder, expected_type, value, self.cStr(""));
                            _ = try arguments_values.append(loaded_value);
                        }
                    }
                    const defer_function_call = DeferFunctionPtrCall.init(function_type, loaded, arguments_values);
                    try self.defer_calls_stack.items[self.defer_calls_stack.items.len - 1].pushFront(try self.allocReturn(DeferCall, DeferCall{ .FunctionPtrCall = defer_function_call }));
                }
            }
            return self.allocReturn(ds.Any, .Void);
        }

        const arguments = call_expression.call_expression.arguments;
        const arguments_size = arguments.items.len;
        const parameter_size = llvm_core.LLVMCountParams(function.?);
        var arguments_values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);
        for (0..arguments_size) |i| {
            const argument = arguments.items[i];
            const value = try self.llvmNodeValue(try argument.accept(self.visitor));

            if (i >= parameter_size) {
                if (argument.getAstNodeType() == .Literal) {
                    const argument_type = try self.llvmTypeFromLangType(argument.getTypeNode().?);
                    const loaded_value = llvm_core.LLVMBuildLoad2(builder, argument_type, value, self.cStr(""));
                    _ = try arguments_values.append(loaded_value);
                    continue;
                }
                try arguments_values.append(value);
                continue;
            }

            const parameter = llvm_core.LLVMGetParam(function.?, @intCast(i));
            const parameter_type = llvm_core.LLVMTypeOf(parameter);
            if (llvm_core.LLVMTypeOf(value) == parameter_type) {
                _ = try arguments_values.append(value);
                continue;
            }

            const loaded_value = llvm_core.LLVMBuildLoad2(builder, parameter_type, value, self.cStr(""));
            _ = try arguments_values.append(loaded_value);
        }

        const defer_function_call = DeferFunctionCall.init(function.?, arguments_values);
        try self.defer_calls_stack.items[self.defer_calls_stack.items.len - 1].pushFront(try self.allocReturn(DeferCall, DeferCall{ .FunctionCall = defer_function_call }));
        return self.allocReturn(ds.Any, .Void);
    }

    pub fn visitBreakStatement(self: *Self, node: *ast.BreakStatement) !*ds.Any {
        log("Visiting break statement", .{});
        self.has_break_or_continue_statement = true;
        for (1..node.times) |_| {
            _ = self.break_blocks_stack.pop();
        }
        _ = llvm_core.LLVMBuildBr(builder, self.break_blocks_stack.items[self.break_blocks_stack.items.len - 1]);
        return self.allocReturn(ds.Any, .Void);
    }

    pub fn visitContinueStatement(self: *Self, node: *ast.ContinueStatement) !*ds.Any {
        log("Visiting continue statement", .{});
        self.has_break_or_continue_statement = true;
        for (1..node.times) |_| {
            _ = self.continue_blocks_stack.pop();
        }

        _ = llvm_core.LLVMBuildBr(builder, self.continue_blocks_stack.items[self.continue_blocks_stack.items.len - 1]);
        return self.allocReturn(ds.Any, .Void);
    }

    pub fn visitExpressionStatement(self: *Self, node: *ast.ExpressionStatement) !*ds.Any {
        log("Visiting expression statement", .{});
        _ = try node.expression.accept(self.visitor);
        return self.allocReturn(ds.Any, .Void);
    }

    pub fn visitIfExpression(self: *Self, node: *ast.IfExpression) !*ds.Any {
        log("Visiting if expression", .{});
        if (self.isGlobalBlock() and node.isConstant()) {
            const ret = try self.resolveConstantIfExpression(node);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }
        const blocks_count = node.tokens.items.len;
        const value_type = try self.llvmTypeFromLangType(node.getTypeNode().?);

        var llvm_branches = std.ArrayList(llvm_types.LLVMBasicBlockRef).init(self.allocator);
        var llvm_values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);
        try llvm_branches.resize(blocks_count);
        try llvm_values.resize(blocks_count);

        for (0..blocks_count) |i| {
            llvm_branches.items[i] = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, "");
            llvm_values.items[i] = try self.llvmResolveValue(try node.values.items[i].accept(self.visitor));
        }
        const function = llvm_core.LLVMGetBasicBlockParent(llvm_core.LLVMGetInsertBlock(builder));
        const merge_branch = llvm_core.LLVMCreateBasicBlockInContext(llvm_context, @ptrCast(""));

        const first_branch = llvm_branches.items[0];
        _ = llvm_core.LLVMBuildBr(builder, first_branch);
        llvm_core.LLVMAppendExistingBasicBlock(function, first_branch);
        llvm_core.LLVMPositionBuilderAtEnd(builder, first_branch);

        for (1..blocks_count) |i| {
            const current_branch = llvm_branches.items[i];
            const condition = try self.llvmResolveValue(try node.conditions.items[i - 1].accept(self.visitor));

            _ = llvm_core.LLVMBuildCondBr(builder, condition, merge_branch, current_branch);
            llvm_core.LLVMAppendExistingBasicBlock(function, current_branch);
            llvm_core.LLVMPositionBuilderAtEnd(builder, current_branch);
        }

        _ = llvm_core.LLVMBuildBr(builder, merge_branch);
        llvm_core.LLVMAppendExistingBasicBlock(function, merge_branch);
        llvm_core.LLVMPositionBuilderAtEnd(builder, merge_branch);

        const phi_node = llvm_core.LLVMBuildPhi(builder, value_type, self.cStr(""));

        for (0..blocks_count) |i| {
            llvm_core.LLVMAddIncoming(phi_node, @ptrCast(&llvm_values.items[i]), @ptrCast(&llvm_branches.items[i]), 1);
        }

        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = phi_node });
    }

    pub fn visitTupleExpression(self: *Self, node: *ast.TupleExpression) !*ds.Any {
        log("Visiting tuple expression", .{});
        const tuple_type = try self.llvmTypeFromLangType(node.value_type.?);
        const alloc_inst = llvm_core.LLVMBuildAlloca(builder, tuple_type, self.cStr("tuple"));

        var argument_index: usize = 0;
        for (node.values.items) |argument| {
            const argument_value = try self.llvmResolveValue(try argument.accept(self.visitor));
            const index = llvm_core.LLVMConstInt(llvm_int32_type, @intCast(argument_index), 1);
            var values = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
            const member_ptr = llvm_core.LLVMBuildGEP2(builder, tuple_type, alloc_inst, &values, 2, "");
            _ = llvm_core.LLVMBuildStore(builder, argument_value, member_ptr);
            argument_index += 1;
        }

        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = alloc_inst });
    }

    pub fn visitAssignExpression(self: *Self, node: *ast.AssignExpression) !*ds.Any {
        log("Visiting assign expression", .{});
        const left_node = node.left;

        switch (left_node.*) {
            .literal_expression => |literal| {
                const name = literal.name.literal;
                const value = try node.right.accept(self.visitor);
                var right_value = try self.llvmResolveValue(value);
                const left_value = try node.left.accept(self.visitor);

                if (llvm_core.LLVMIsAAllocaInst(left_value.LLVMValue) != null) {
                    if (llvm_core.LLVMTypeOf(left_value.LLVMValue) == llvm_core.LLVMTypeOf(right_value)) {
                        right_value = dereferencesLLVMPointer(right_value, .Load);
                    }
                    try self.alloca_inst_table.update(name, left_value);
                    _ = llvm_core.LLVMBuildStore(builder, right_value, left_value.LLVMValue);
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = right_value });
                }

                if (llvm_core.LLVMIsAGlobalVariable(left_value.LLVMValue) != null) {
                    _ = llvm_core.LLVMBuildStore(builder, right_value, left_value.LLVMValue);
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = right_value });
                }
            },

            .index_expression => |index_expr| {
                const node_value = index_expr.value;
                const index = try self.llvmResolveValue(try index_expr.index.accept(self.visitor));
                var right_value = try self.llvmNodeValue(try node.right.accept(self.visitor));

                switch (node_value.*) {
                    .literal_expression => |*array_literal| {
                        const array = try array_literal.accept(self.visitor);
                        if (llvm_core.LLVMIsAAllocaInst(array.LLVMValue) != null) {
                            const alloca = try self.llvmNodeValue(self.alloca_inst_table.lookup(array_literal.name.literal).?);

                            const allocated_type = llvm_core.LLVMGetAllocatedType(alloca);
                            var types_ = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
                            const ptr = llvm_core.LLVMBuildGEP2(builder, allocated_type, alloca, &types_, 2, self.cStr(""));
                            _ = llvm_core.LLVMBuildStore(builder, right_value, ptr);
                            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = right_value });
                        }

                        if (llvm_core.LLVMIsAGlobalVariable(array.LLVMValue) != null) {
                            const global_variable_array = try self.llvmNodeValue(array);
                            const allocated_type = llvm_core.LLVMGlobalGetValueType(global_variable_array);
                            var types_ = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
                            const ptr = llvm_core.LLVMBuildGEP2(builder, allocated_type, global_variable_array, &types_, 2, self.cStr(""));
                            _ = llvm_core.LLVMBuildStore(builder, right_value, ptr);
                            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = right_value });
                        }

                        self.internalCompilerError("Assign value index expression");
                    },
                    .index_expression => {
                        const array = try self.llvmNodeValue(try node_value.accept(self.visitor));
                        const allocated_type = llvm_core.LLVMTypeOf(array);
                        var types_ = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
                        const ptr = llvm_core.LLVMBuildGEP2(builder, allocated_type, array, &types_, 2, self.cStr(""));
                        _ = llvm_core.LLVMBuildStore(builder, right_value, ptr);
                        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = right_value });
                    },
                    .dot_expression => |*struct_access| {
                        const struct_field = try struct_access.accept(self.visitor);
                        if (llvm_core.LLVMIsALoadInst(struct_field.LLVMValue) != null) {
                            const load_inst = try self.llvmNodeValue(struct_field);
                            const pointer_operand = llvm_core.LLVMGetOperand(load_inst, 0);
                            var types_ = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
                            const ptr = llvm_core.LLVMBuildGEP2(builder, llvm_core.LLVMTypeOf(load_inst), pointer_operand, &types_, 2, self.cStr(""));

                            if (llvm_core.LLVMTypeOf(right_value) == llvm_core.LLVMTypeOf(ptr)) {
                                right_value = dereferencesLLVMPointer(right_value, .Load);
                            }
                            _ = llvm_core.LLVMBuildStore(builder, right_value, ptr);
                            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = right_value });
                        }
                    },
                    else => {},
                }
            },
            .dot_expression => |*dot_expression| {
                const member_ptr = try self.accessStructMemberPointer3(dot_expression);
                const rvalue = try self.llvmResolveValue(try node.right.accept(self.visitor));
                _ = llvm_core.LLVMBuildStore(builder, rvalue, member_ptr);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = rvalue });
            },
            .prefix_unary_expression => |unary_expression| {
                const opt = unary_expression.operator_token.kind;
                if (opt == .Star) {
                    const rvalue = try self.llvmResolveValue(try node.right.accept(self.visitor));
                    const unary_right_type = unary_expression.right.getTypeNode().?;
                    const pointer_type = unary_right_type.Pointer;
                    const pointer_base_type = try self.llvmTypeFromLangType(pointer_type.base_type);
                    const pointer = try self.llvmNodeValue(try unary_expression.right.accept(self.visitor));
                    const load = llvm_core.LLVMBuildLoad2(builder, pointer_base_type, pointer, @ptrCast(""));
                    _ = llvm_core.LLVMBuildStore(builder, rvalue, load);
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = rvalue });
                }
            },
            else => {},
        }

        self.internalCompilerError("Invalid assignments expression with unexpected lvalue type");
        unreachable;
    }

    pub fn visitBinaryExpression(self: *Self, node: *ast.BinaryExpression) !*ds.Any {
        log("Visiting binary expression", .{});
        const lhs = try self.llvmResolveValue(try node.left.accept(self.visitor));
        const rhs = try self.llvmResolveValue(try node.right.accept(self.visitor));

        const op = node.operator_token.kind;
        const lhs_type = llvm_core.LLVMTypeOf(lhs);
        const rhs_type = llvm_core.LLVMTypeOf(rhs);

        if (llvm_core.LLVMGetTypeKind(lhs_type) == .LLVMIntegerTypeKind and llvm_core.LLVMGetTypeKind(rhs_type) == .LLVMIntegerTypeKind) {
            const ret = self.createLLVMIntegersBinary(op, lhs, rhs);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        if (isFloatingPointTy(lhs_type) and isFloatingPointTy(rhs_type)) {
            const ret = self.createLLVMFloatsBinary(op, lhs, rhs);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        if (llvm_core.LLVMGetTypeKind(lhs_type) == .LLVMVectorTypeKind and llvm_core.LLVMGetTypeKind(rhs_type) == .LLVMVectorTypeKind) {
            const vector_type = node.value_type.?.StaticVector;
            const element_type = vector_type.array.element_type.?;
            if (types.isUnsignedIntegerType(element_type)) {
                const ret = self.createLLVMIntegersVectorsBinary(op, lhs, rhs);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            }
            const ret = self.createLLVMFloatsVectorsBinary(op, lhs, rhs);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        const lhs_type_ = node.left.getTypeNode().?;
        const rhs_type_ = node.right.getTypeNode().?;
        var types_ = [2]*types.Type{ lhs_type_, rhs_type_ };
        const name = try types.mangleOperatorFunction(self.allocator, op, &types_);
        var types_b = [2]llvm_types.LLVMValueRef{ lhs, rhs };
        const ret = try self.createOverloadingFunctionCall(name, &types_b);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
    }

    pub fn visitBitwiseExpression(self: *Self, node: *ast.BitwiseExpression) !*ds.Any {
        log("Visiting bitwise expression", .{});
        const lhs = try self.llvmResolveValue(try node.left.accept(self.visitor));
        const rhs = try self.llvmResolveValue(try node.right.accept(self.visitor));

        const op = node.operator_token.kind;
        const lhs_type = node.left.getTypeNode().?;
        const rhs_type = node.right.getTypeNode().?;

        if ((types.isIntegerType(lhs_type) and types.isIntegerType(rhs_type)) or (types.isVectorType(lhs_type) and types.isVectorType(rhs_type))) {
            switch (op) {
                .Or => {
                    const ret = llvm_core.LLVMBuildOr(builder, lhs, rhs, self.cStr(""));
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
                },
                .And => {
                    const ret = llvm_core.LLVMBuildAnd(builder, lhs, rhs, self.cStr(""));
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
                },
                .Xor => {
                    const ret = llvm_core.LLVMBuildXor(builder, lhs, rhs, self.cStr(""));
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
                },
                .LeftShift => {
                    const ret = llvm_core.LLVMBuildShl(builder, lhs, rhs, self.cStr(""));
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
                },
                .RightShift => {
                    if (types.isUnsignedIntegerType(lhs_type)) {
                        const ret = llvm_core.LLVMBuildLShr(builder, lhs, rhs, self.cStr(""));
                        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
                    }
                    const ret = llvm_core.LLVMBuildAShr(builder, lhs, rhs, self.cStr(""));
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
                },
                else => {},
            }
        }

        const name = try types.mangleOperatorFunction(self.allocator, op, &.{ lhs_type, rhs_type });
        var args = [2]llvm_types.LLVMValueRef{ lhs, rhs };
        const ret = try self.createOverloadingFunctionCall(name, &args);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
    }

    pub fn visitComparisonExpression(self: *Self, node: *ast.ComparisonExpression) !*ds.Any {
        log("Visiting comparison expression", .{});
        const lhs = try self.llvmResolveValue(try node.left.accept(self.visitor));
        const rhs = try self.llvmResolveValue(try node.right.accept(self.visitor));
        const op = node.operator_token.kind;

        const lhs_type = llvm_core.LLVMTypeOf(lhs);
        const rhs_type = llvm_core.LLVMTypeOf(rhs);

        if (llvm_core.LLVMGetTypeKind(lhs_type) == .LLVMIntegerTypeKind and llvm_core.LLVMGetTypeKind(rhs_type) == .LLVMIntegerTypeKind) {
            if (types.isUnsignedIntegerType(node.left.getTypeNode().?)) {
                const ret = self.createLLVMUnsignedIntegersComparison(op, lhs, rhs);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            }
            const ret = self.createLLVMIntegersComparison(op, lhs, rhs);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        if (isFloatingPointTy(lhs_type) and isFloatingPointTy(rhs_type)) {
            const ret = self.createLLVMFloatsComparison(op, lhs, rhs);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        if (llvm_core.LLVMGetTypeKind(lhs_type) == .LLVMPointerTypeKind and llvm_core.LLVMGetTypeKind(rhs_type) == .LLVMPointerTypeKind) {
            if (node.left.getAstNodeType() == .String and node.right.getAstNodeType() == .String) {
                const lhs_str = node.left.string_expression.value.literal;
                const rhs_str = node.right.string_expression.value.literal;
                const compare = @intFromBool(std.mem.eql(u8, lhs_str, rhs_str));
                const result_llvm = llvm_core.LLVMConstInt(llvm_int8_type, @intCast(compare), 1);
                const ret = self.createLLVMIntegersComparison(op, result_llvm, zero_int32_value);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            }

            if (types.isTypesEquals(node.left.getTypeNode().?, &types.Type.I8_PTR_TYPE) and types.isTypesEquals(node.right.getTypeNode().?, &types.Type.I8_PTR_TYPE)) {
                const ret = try self.createLLVMStringsComparison(op, lhs, rhs);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            }

            const ret = self.createLLVMIntegersComparison(op, lhs, rhs);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        if (llvm_core.LLVMGetTypeKind(lhs_type) == .LLVMVectorTypeKind and llvm_core.LLVMGetTypeKind(rhs_type) == .LLVMVectorTypeKind) {
            const vector_type = node.value_type.?.StaticVector;
            const element_type = vector_type.array.element_type.?;
            if (types.isUnsignedIntegerType(element_type)) {
                const ret = self.createLLVMUnsignedIntegersComparison(op, lhs, rhs);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            }
            const ret = self.createLLVMIntegersComparison(op, lhs, rhs);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        const lhs_type_ = node.left.getTypeNode().?;
        const rhs_type_ = node.right.getTypeNode().?;
        var types_ = [2]*types.Type{ lhs_type_, rhs_type_ };
        const name = try types.mangleOperatorFunction(self.allocator, op, &types_);
        var types_1 = [2]llvm_types.LLVMValueRef{ lhs, rhs };
        const ret = try self.createOverloadingFunctionCall(name, &types_1);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
    }

    pub fn visitLogicalExpression(self: *Self, node: *ast.LogicalExpression) !*ds.Any {
        log("Visiting logical expression", .{});
        const lhs = try self.llvmResolveValue(try node.left.accept(self.visitor));
        const rhs = try self.llvmResolveValue(try node.right.accept(self.visitor));

        const lhs_type = node.left.getTypeNode().?;
        const rhs_type = node.right.getTypeNode().?;
        const op = node.operator_token.kind;

        if (types.isInteger1Type(lhs_type) and types.isInteger1Type(rhs_type)) {
            if (op == .AndAnd) {
                // const ret = llvm_core.LLVMBuildAnd(builder, lhs, rhs, self.cStr("and"));
                const ret = llvm_core.LLVMBuildSelect(builder, lhs, rhs, false_value, self.cStr(""));
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            }

            if (op == .OrOr) {
                // const ret = llvm_core.LLVMBuildOr(builder, lhs, rhs, self.cStr("or"));
                const ret = llvm_core.LLVMBuildSelect(builder, lhs, true_value, rhs, self.cStr(""));
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            }
        }

        const name = try types.mangleOperatorFunction(self.allocator, op, &[2]*types.Type{ lhs_type, rhs_type });
        var types_ = [2]llvm_types.LLVMValueRef{ lhs, rhs };
        const ret = try self.createOverloadingFunctionCall(name, &types_);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
    }

    pub fn visitPrefixUnaryExpression(self: *Self, node: *ast.PrefixUnaryExpression) !*ds.Any {
        log("Visiting prefix unary expression", .{});
        const operand = node.right;
        const operator_kind = node.operator_token.kind;

        switch (operator_kind) {
            .Minus => {
                const rhs = try self.llvmResolveValue(try operand.accept(self.visitor));
                const rhs_type = llvm_core.LLVMTypeOf(rhs);
                if (isFloatingPointTy(rhs_type)) {
                    const ret = llvm_core.LLVMBuildFNeg(builder, rhs, @ptrCast("neg"));
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
                }
                if (llvm_core.LLVMGetTypeKind(rhs_type) == .LLVMIntegerTypeKind) {
                    const ret = llvm_core.LLVMBuildNeg(builder, rhs, @ptrCast("neg"));
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
                }
                var types_ = [1]*types.Type{operand.getTypeNode().?};
                const name = try std.fmt.allocPrint(self.allocator, "_prefix{s}", .{try types.mangleOperatorFunction(self.allocator, operator_kind, &types_)});
                var types_a = [1]llvm_types.LLVMValueRef{rhs};
                const ret = try self.createOverloadingFunctionCall(name, &types_a);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            },
            .Bang => {
                const rhs = try self.llvmResolveValue(try operand.accept(self.visitor));
                const rhs_type = llvm_core.LLVMTypeOf(rhs);
                if (rhs_type == llvm_int1_type) {
                    const ret = llvm_core.LLVMBuildICmp(builder, .LLVMIntEQ, rhs, false_value, @ptrCast(""));
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
                }

                const name = try std.fmt.allocPrint(self.allocator, "_prefix{s}", .{try types.mangleOperatorFunction(self.allocator, operator_kind, &[1]*types.Type{operand.getTypeNode().?})});
                var types_ = [1]llvm_types.LLVMValueRef{rhs};
                const ret = try self.createOverloadingFunctionCall(name, &types_);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            },
            .Star => {
                const right = try self.llvmNodeValue(try operand.accept(self.visitor));
                const is_expect_struct_type = node.getTypeNode().?.typeKind() == .Struct;

                if (is_expect_struct_type) {
                    const ret = dereferencesLLVMPointer(right, .Load);
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
                }

                const dereference_right = dereferencesLLVMPointer(right, .Load);
                const ret = dereferencesLLVMPointer(dereference_right, .Load);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            },
            .And => {
                const right = try self.llvmNodeValue(try operand.accept(self.visitor));
                const right_type = llvm_core.LLVMTypeOf(right);
                const ptr = llvm_core.LLVMBuildAlloca(builder, right_type, @ptrCast(""));
                _ = llvm_core.LLVMBuildStore(builder, right, ptr);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ptr });
            },
            .Not => {
                const rhs = try self.llvmResolveValue(try operand.accept(self.visitor));
                if (operand.getTypeNode().?.typeKind() == .Number) {
                    const ret = llvm_core.LLVMBuildNot(builder, rhs, @ptrCast(""));
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
                }

                const name = try std.fmt.allocPrint(self.allocator, "_prefix{s}", .{try types.mangleOperatorFunction(self.allocator, operator_kind, &[1]*types.Type{operand.getTypeNode().?})});
                var types_ = [1]llvm_types.LLVMValueRef{rhs};
                const ret = try self.createOverloadingFunctionCall(name, &types_);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            },
            .PlusPlus => {
                if (operand.getTypeNode().?.typeKind() == .Number) {
                    const ret = try self.createLLVMValueIncrement(operand, true);
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
                }
                const name = try std.fmt.allocPrint(self.allocator, "_prefix{s}", .{try types.mangleOperatorFunction(self.allocator, operator_kind, &[1]*types.Type{operand.getTypeNode().?})});
                const llvm_rhs = try self.llvmResolveValue(try operand.accept(self.visitor));
                var types_ = [1]llvm_types.LLVMValueRef{llvm_rhs};
                const ret = try self.createOverloadingFunctionCall(name, &types_);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            },
            .MinusMinus => {
                if (operand.getTypeNode().?.typeKind() == .Number) {
                    const ret = try self.createLLVMValueDecrement(operand, true);
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
                }
                const name = try std.fmt.allocPrint(self.allocator, "_prefix{s}", .{try types.mangleOperatorFunction(self.allocator, operator_kind, &[1]*types.Type{operand.getTypeNode().?})});
                const llvm_rhs = try self.llvmResolveValue(try operand.accept(self.visitor));
                var types_ = [1]llvm_types.LLVMValueRef{llvm_rhs};
                const ret = try self.createOverloadingFunctionCall(name, &types_);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            },
            else => {},
        }
        self.internalCompilerError("Unexpected prefix unary expression");
        unreachable;
    }

    pub fn visitPostfixUnaryExpression(self: *Self, node: *ast.PostfixUnaryExpression) !*ds.Any {
        log("Visiting postfix unary expression", .{});
        const operand = node.right;
        const operator_kind = node.operator_token.kind;

        if (operator_kind == .PlusPlus) {
            if (operand.getTypeNode().?.typeKind() == .Number) {
                const ret = try self.createLLVMValueIncrement(operand, false);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            }
            const name = try std.fmt.allocPrint(self.allocator, "_postfix{s}", .{try types.mangleOperatorFunction(self.allocator, operator_kind, &[1]*types.Type{operand.getTypeNode().?})});
            const llvm_rhs = try self.llvmResolveValue(try operand.accept(self.visitor));
            var values = [1]llvm_types.LLVMValueRef{llvm_rhs};
            const ret = try self.createOverloadingFunctionCall(name, &values);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        if (operator_kind == .MinusMinus) {
            if (operand.getTypeNode().?.typeKind() == .Number) {
                const ret = try self.createLLVMValueDecrement(operand, false);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            }
            const name = try std.fmt.allocPrint(self.allocator, "_postfix{s}", .{try types.mangleOperatorFunction(self.allocator, operator_kind, &[1]*types.Type{operand.getTypeNode().?})});
            const llvm_rhs = try self.llvmResolveValue(try operand.accept(self.visitor));
            var values = [1]llvm_types.LLVMValueRef{llvm_rhs};
            const ret = try self.createOverloadingFunctionCall(name, &values);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        self.internalCompilerError("Invalid postfix unary expression");
        unreachable;
    }

    pub fn visitCallExpression(self: *Self, node: *ast.CallExpression) !*ds.Any {
        log("Visiting call expression", .{});
        const callee_ast_node_type = node.callee.getAstNodeType();

        if (callee_ast_node_type == .Call) {
            const callee_function = try self.llvmNodeValue(try node.callee.accept(self.visitor));
            const callee_function_type = llvm_core.LLVMGetCalledFunctionType(callee_function);

            const return_ptr_type = llvm_core.LLVMGetElementType(llvm_core.LLVMGetReturnType(callee_function_type));

            const arguments = node.arguments;
            const arguments_size = arguments.items.len;
            var arguments_values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);
            var params = std.ArrayList(llvm_types.LLVMTypeRef).init(self.allocator);
            try params.resize(arguments_size);
            llvm_core.LLVMGetParamTypes(return_ptr_type, @ptrCast(params.items));
            for (0..arguments_size) |i| {
                const value = try self.llvmNodeValue(try arguments.items[i].accept(self.visitor));
                const param_type = params.items[i];
                const value_type = llvm_core.LLVMTypeOf(value);
                // TODO: might be wrong ?
                if (value_type == param_type) {
                    try arguments_values.append(value);
                } else {
                    const loaded_value = llvm_core.LLVMBuildLoad2(builder, param_type, value, @ptrCast(""));
                    try arguments_values.append(loaded_value);
                }
            }

            const call = llvm_core.LLVMBuildCall2(builder, return_ptr_type, callee_function, @ptrCast(arguments_values.items), @intCast(arguments_size), @ptrCast(""));
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = call });
        }

        if (callee_ast_node_type == .Literal) {
            const callee = node.callee.literal_expression;
            var callee_name = callee.name.literal;
            log("Callee name: {s}", .{callee_name});
            var function = try self.lookupFunction(callee_name);

            if (function == null and self.function_declarations.contains(callee_name)) {
                const declaration = self.function_declarations.get(callee_name).?;
                function = try self.resolveGenericFunction(declaration, node.generic_arguments.items);
                callee_name = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ callee_name, try types.mangleTypes(self.allocator, node.generic_arguments.items) });
            }

            if (function == null) {
                const value = try self.llvmNodeValue(self.alloca_inst_table.lookup(callee_name).?);
                if (llvm_core.LLVMIsAAllocaInst(value) != null) {
                    const allocated = llvm_core.LLVMGetAllocatedType(value);
                    const loaded = llvm_core.LLVMBuildLoad2(builder, allocated, value, @ptrCast(""));
                    const function_type = try self.llvmTypeFromLangType(node.getTypeNode().?);
                    debugT(function_type);

                    if (llvm_core.LLVMGetTypeKind(function_type) == .LLVMFunctionTypeKind) {
                        const arguments = node.arguments;
                        const arguments_size = arguments.items.len;
                        var arguments_values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);
                        var params = std.ArrayList(llvm_types.LLVMTypeRef).init(self.allocator);
                        try params.resize(arguments_size + 1); // Add +1 to avoid segfault

                        llvm_core.LLVMGetParamTypes(function_type, @ptrCast(params.items));

                        for (0..arguments_size) |i| {
                            const value_ = try self.llvmNodeValue(try arguments.items[i].accept(self.visitor));
                            debugV(value_);
                            debugV(loaded);
                            const value_type = llvm_core.LLVMTypeOf(value_);
                            const param_type = params.items[i];
                            if (value_type == param_type) {
                                try arguments_values.append(value_);
                            } else {
                                const loaded_value = llvm_core.LLVMBuildLoad2(builder, param_type, value_, @ptrCast(""));
                                try arguments_values.append(loaded_value);
                            }
                        }
                        const call_ = llvm_core.LLVMBuildCall2(builder, function_type, loaded, @ptrCast(arguments_values.items), @intCast(arguments_size), @ptrCast(""));
                        debugV(call_);
                        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = call_ });
                    }
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = loaded });
                }
            }

            const arguments = node.arguments;
            const arguments_size = arguments.items.len;
            const parameter_size = llvm_core.LLVMCountParams(function.?);
            var arguments_values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);
            var implicit_arguments_count: usize = 0;
            const function_name = llvm_core.LLVMGetValueName(function.?);
            if (try self.isLambdaFunctionName(std.mem.span(function_name))) {
                const extra_literal_parameters = self.lambda_extra_parameters.get(std.mem.span(function_name)).?;
                implicit_arguments_count = extra_literal_parameters.items.len;

                var implicit_values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);
                for (extra_literal_parameters.items) |outer_variable_name| {
                    const value = try self.llvmResolveVariable(outer_variable_name);
                    const resolved_value = try self.llvmResolveValue(try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = value }));
                    try implicit_values.append(resolved_value);
                }

                try arguments_values.insertSlice(0, implicit_values.items);
            } else {
                try arguments_values.ensureTotalCapacity(arguments_size);
            }

            for (0..arguments_size) |i| {
                const argument = arguments.items[i];
                const value = try self.llvmNodeValue(try argument.accept(self.visitor));
                debugV(value);

                if (i >= parameter_size) {
                    if (argument.getAstNodeType() == .Literal) {
                        const arguments_type = try self.llvmTypeFromLangType(argument.getTypeNode().?);
                        const loaded_value = llvm_core.LLVMBuildLoad2(builder, arguments_type, value, @ptrCast(""));

                        // Check loaded value type is float
                        if (llvm_core.LLVMGetTypeKind(llvm_core.LLVMTypeOf(loaded_value)) == .LLVMFloatTypeKind) {
                            const double_value = llvm_core.LLVMBuildFPCast(builder, loaded_value, llvm_float64_type, @ptrCast("float_to_double"));
                            try arguments_values.append(double_value);
                            continue;
                        }

                        try arguments_values.append(loaded_value);
                        continue;
                    }

                    if (llvm_core.LLVMGetTypeKind(llvm_core.LLVMTypeOf(value)) == .LLVMFloatTypeKind) {
                        const double_value = llvm_core.LLVMBuildFPCast(builder, value, llvm_float64_type, @ptrCast("float_to_double"));
                        try arguments_values.append(double_value);
                    }

                    try arguments_values.append(value);
                    continue;
                }
                const function_argument = llvm_core.LLVMGetParam(function.?, @intCast(i + implicit_arguments_count));
                const function_argument_type = llvm_core.LLVMTypeOf(function_argument);

                // Can I comment this out
                if (function_argument_type == llvm_core.LLVMTypeOf(value)) {
                    try arguments_values.append(value);
                    continue;
                }
                const resolved_value = llvm_core.LLVMBuildLoad2(builder, function_argument_type, value, @ptrCast(""));

                try arguments_values.append(resolved_value);
            }

            const function_type = self.function_types_map.get(std.mem.span(function_name)).?;

            const call = llvm_core.LLVMBuildCall2(builder, function_type, function.?, @ptrCast(arguments_values.items), @intCast(arguments_values.items.len), "");
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = call });
        }

        if (callee_ast_node_type == .Lambda) {
            const lambda_value = try self.llvmNodeValue(try node.callee.lambda_expression.accept(self.visitor));

            const arguments = node.arguments;
            const arguments_size = arguments.items.len;
            const parameter_size = llvm_core.LLVMCountParams(lambda_value);
            var arguments_values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);
            for (0..arguments_size) |i| {
                const argument = arguments.items[i];
                const value = try self.llvmNodeValue(try argument.accept(self.visitor));

                if (i >= parameter_size) {
                    if (argument.getAstNodeType() == .Literal) {
                        const argument_type = try self.llvmTypeFromLangType(argument.getTypeNode().?);
                        const loaded_value = llvm_core.LLVMBuildLoad2(builder, argument_type, value, @ptrCast(""));
                        try arguments_values.append(loaded_value);
                        continue;
                    }

                    try arguments_values.append(value);
                    continue;
                }

                if (llvm_core.LLVMTypeOf(value) == llvm_core.LLVMTypeOf(llvm_core.LLVMGetParam(lambda_value, @intCast(i)))) {
                    try arguments_values.append(value);
                    continue;
                }

                const expected_type = llvm_core.LLVMTypeOf(llvm_core.LLVMGetParam(lambda_value, @intCast(i)));
                const loaded_value = llvm_core.LLVMBuildLoad2(builder, expected_type, value, @ptrCast(""));
                try arguments_values.append(loaded_value);
            }
            const return_type = llvm_core.LLVMGetReturnType(llvm_core.LLVMTypeOf(lambda_value));
            const call = llvm_core.LLVMBuildCall2(builder, return_type, lambda_value, @ptrCast(arguments_values.items), @intCast(arguments_values.items.len), @ptrCast(""));
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = call });
        }

        if (callee_ast_node_type == .Dot) {
            var dot = node.callee.dot_expression;
            const struct_fun_ptr = try self.llvmNodeValue(try dot.accept(self.visitor));
            const function_value = dereferencesLLVMPointer(struct_fun_ptr, .Load);
            const function_ptr_type = dot.getTypeNode().?.Pointer;

            const llvm_type = try self.llvmTypeFromLangType(function_ptr_type.base_type);

            const arguments = node.arguments;
            const arguments_size = arguments.items.len;
            const parameter_size = llvm_core.LLVMCountParams(function_value);
            var arguments_values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);

            for (0..arguments_size) |i| {
                const argument = arguments.items[i];
                const value = try self.llvmNodeValue(try argument.accept(self.visitor));

                if (i >= parameter_size) {
                    if (argument.getAstNodeType() == .Literal) {
                        const argument_type = try self.llvmTypeFromLangType(argument.getTypeNode().?);
                        const loaded_value = llvm_core.LLVMBuildLoad2(builder, argument_type, value, @ptrCast(""));
                        try arguments_values.append(loaded_value);
                        continue;
                    }

                    try arguments_values.append(value);
                    continue;
                }

                if (llvm_core.LLVMTypeOf(value) == llvm_core.LLVMTypeOf(llvm_core.LLVMGetParam(function_value, @intCast(i)))) {
                    try arguments_values.append(value);
                    continue;
                }

                const expected_type = llvm_core.LLVMTypeOf(llvm_core.LLVMGetParam(function_value, @intCast(i)));
                const loaded_value = llvm_core.LLVMBuildLoad2(builder, expected_type, value, @ptrCast(""));
                try arguments_values.append(loaded_value);
            }

            const call = llvm_core.LLVMBuildCall2(builder, llvm_type, function_value, @ptrCast(arguments_values.items), @intCast(arguments_values.items.len), @ptrCast(""));
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = call });
        }

        self.internalCompilerError("Invalid call expression");
        unreachable;
    }

    pub fn visitInitializeExpression(self: *Self, node: *ast.InitExpression) !*ds.Any {
        log("Visiting initialize expression", .{});
        var struct_type: llvm_types.LLVMTypeRef = undefined;
        if (node.value_type.?.typeKind() == .GenericStruct) {
            const generic = node.value_type.?.GenericStruct;
            struct_type = try self.resolveGenericStruct(&generic);
        } else {
            struct_type = try self.llvmTypeFromLangType(node.value_type.?);
        }

        if (self.isGlobalBlock()) {
            var constants_arguments = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);
            for (node.arguments.items) |argument| {
                try constants_arguments.append(try self.resolveConstantExpression(argument));
            }
            const ret = llvm_core.LLVMConstNamedStruct(struct_type, @ptrCast(constants_arguments.items), @intCast(constants_arguments.items.len));
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }
        const alloc_inst = llvm_core.LLVMBuildAlloca(builder, struct_type, @ptrCast("alloca"));
        var argument_idx: usize = 0;
        for (node.arguments.items) |argument| {
            const argument_value = try self.llvmResolveValue(try argument.accept(self.visitor));
            const index = llvm_core.LLVMConstInt(llvm_int32_type, @intCast(argument_idx), 0);
            var values = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
            const member_ptr = llvm_core.LLVMBuildGEP2(builder, struct_type, alloc_inst, &values, 2, "");
            _ = llvm_core.LLVMBuildStore(builder, argument_value, member_ptr);
            argument_idx += 1;
        }

        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = alloc_inst });
    }

    pub fn visitLambdaExpression(self: *Self, node: *ast.LambdaExpression) !*ds.Any {
        log("Visiting lambda expression", .{});
        const lambda_name = try std.fmt.allocPrint(self.allocator, "_lambda{d}", .{self.lambda_unique_id});
        self.lambda_unique_id += 1;
        const function_ptr_type = node.getTypeNode().?.Pointer;

        const node_llvm_type = try self.llvmTypeFromLangType(function_ptr_type.base_type);
        const function_type = node_llvm_type;
        const function = llvm_core.LLVMAddFunction(self.llvm_module, self.cStr(lambda_name), function_type);
        debugT(function_type);
        llvm_core.LLVMSetLinkage(function, .LLVMInternalLinkage);
        // try self.function_types_map.put(function_name, function_type);

        const previous_insert_block = llvm_core.LLVMGetInsertBlock(builder);
        const entry_block = llvm_core.LLVMAppendBasicBlockInContext(llvm_context, function, self.cStr("entry"));
        llvm_core.LLVMPositionBuilderAtEnd(builder, entry_block);

        try self.pushAllocaInstScope();

        const outer_parameter_names = node.implicit_parameter_names;
        const outer_parameters_size = outer_parameter_names.items.len;
        var implicit_parameters = std.ArrayList([]const u8).init(self.allocator);
        for (outer_parameter_names.items) |outer_parameter_name| {
            try implicit_parameters.append(outer_parameter_name);
        }

        try self.lambda_extra_parameters.put(lambda_name, implicit_parameters);

        var explicit_parameter_index: usize = 0;
        var i: usize = 0;
        const args = llvm_core.LLVMCountParams(function);
        for (0..args) |arg_idx| {
            const arg = llvm_core.LLVMGetParam(function, @intCast(arg_idx));
            var arg_name: []const u8 = undefined;
            if (i < outer_parameters_size) {
                arg_name = implicit_parameters.items[i];
                i += 1;
            } else {
                arg_name = node.explicit_parameters.items[explicit_parameter_index].name.literal;
                explicit_parameter_index += 1;
            }
            llvm_core.LLVMSetValueName(arg, self.cStr(arg_name));
            const alloca_inst = try self.createEntryBlockAlloca(function, arg_name, llvm_core.LLVMTypeOf(arg));
            _ = self.alloca_inst_table.define(arg_name, try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = alloca_inst }));
            _ = llvm_core.LLVMBuildStore(builder, arg, alloca_inst);
        }

        try self.defer_calls_stack.append(ds.ScopedList(*DeferCall).init(self.allocator));
        _ = try node.body.accept(self.visitor);
        _ = self.defer_calls_stack.pop();
        self.popAllocaInstScope();

        _ = self.alloca_inst_table.define(lambda_name, try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = function }));
        self.debugModule();
        _ = llvm_analysis.LLVMVerifyFunction(function, .LLVMAbortProcessAction);
        // _ = llvm_analysis.LLVMVerifyFunction(function, .LLVMPrintMessageAction);

        llvm_core.LLVMPositionBuilderAtEnd(builder, previous_insert_block);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = function });
    }

    pub fn visitDotExpression(self: *Self, node: *ast.DotExpression) !*ds.Any {
        log("Visiting dot expression", .{});
        const callee = node.callee;
        const callee_type = callee.getTypeNode().?;
        const callee_llvm_type = try self.llvmTypeFromLangType(callee_type);
        const expected_llvm_type = try self.llvmTypeFromLangType(node.getTypeNode().?);

        if (isArrayTy(callee_llvm_type)) {
            if (std.mem.eql(u8, node.field_name.literal, "count")) {
                const length = llvm_core.LLVMGetArrayLength(callee_llvm_type);
                const ret = llvm_core.LLVMConstInt(llvm_int64_type, @intCast(length), 1);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            }

            self.internalCompilerError("Invalid Array Attribute");
        }

        if (isVectorTy(callee_llvm_type)) {
            if (std.mem.eql(u8, node.field_name.literal, "count")) {
                const length = llvm_core.LLVMGetVectorSize(callee_llvm_type);
                const ret = llvm_core.LLVMConstInt(llvm_int64_type, @intCast(length), 1);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            }
            self.internalCompilerError("Invalid Vector Attribute");
        }

        if (types.isPointerOfType(callee_type, &types.Type.I8_TYPE)) {
            if (std.mem.eql(u8, node.field_name.literal, "count")) {
                if (node.callee.getAstNodeType() == .String) {
                    const string = node.callee.string_expression;
                    const length = string.value.literal.len;
                    const ret = llvm_core.LLVMConstInt(llvm_int64_type, @intCast(length), 1);
                    return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
                }

                var string_ptr = try self.llvmNodeValue(try callee.accept(self.visitor));
                if (llvm_core.LLVMTypeOf(string_ptr) != llvm_int8_ptr_type) {
                    string_ptr = dereferencesLLVMPointer(string_ptr, .Load);
                }

                const ret = try self.createLLVMStringLength(string_ptr);
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            }

            self.internalCompilerError("Invalid String Attribute");
        }

        const member_ptr = try self.accessStructMemberPointer3(node);

        if (llvm_core.LLVMGetTypeKind(expected_llvm_type) == .LLVMPointerTypeKind) {
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = member_ptr });
        }

        const ret = llvm_core.LLVMBuildLoad2(builder, expected_llvm_type, member_ptr, @ptrCast(""));
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
    }

    pub fn visitCastExpression(self: *Self, node: *ast.CastExpression) !*ds.Any {
        log("Visiting cast expression", .{});
        const value = try self.llvmResolveValue(try node.value.accept(self.visitor));
        const value_type = try self.llvmTypeFromLangType(node.value.getTypeNode().?);
        const target_type = try self.llvmTypeFromLangType(node.getTypeNode().?);

        if (value_type == target_type) {
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = value });
        }

        if (llvm_core.LLVMGetTypeKind(target_type) == .LLVMIntegerTypeKind and llvm_core.LLVMGetTypeKind(value_type) == .LLVMIntegerTypeKind) {
            const ret = llvm_core.LLVMBuildIntCast2(builder, value, target_type, 1, @ptrCast(""));
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        if (isFloatingPointTy(target_type) and isFloatingPointTy(value_type)) {
            const ret = llvm_core.LLVMBuildFPCast(builder, value, target_type, @ptrCast(""));
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        if (isFloatingPointTy(value_type) and llvm_core.LLVMGetTypeKind(target_type) == .LLVMIntegerTypeKind) {
            const ret = llvm_core.LLVMBuildFPToSI(builder, value, target_type, @ptrCast(""));
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        if (llvm_core.LLVMGetTypeKind(value_type) == .LLVMIntegerTypeKind and isFloatingPointTy(target_type)) {
            const ret = llvm_core.LLVMBuildSIToFP(builder, value, target_type, @ptrCast(""));
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        if (llvm_core.LLVMGetTypeKind(value_type) == .LLVMIntegerTypeKind and llvm_core.LLVMGetTypeKind(target_type) == .LLVMPointerTypeKind) {
            const ret = llvm_core.LLVMBuildIntToPtr(builder, value, target_type, @ptrCast(""));
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        if (llvm_core.LLVMGetTypeKind(value_type) == .LLVMPointerTypeKind and llvm_core.LLVMGetTypeKind(target_type) == .LLVMIntegerTypeKind) {
            const ret = llvm_core.LLVMBuildPtrToInt(builder, value, target_type, @ptrCast(""));
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        if (llvm_core.LLVMGetTypeKind(value_type) == .LLVMArrayTypeKind and llvm_core.LLVMGetTypeKind(target_type) == .LLVMPointerTypeKind) {
            if (llvm_core.LLVMIsALoadInst(value) != null) {
                const load_inst = llvm_core.LLVMGetOperand(value, 0);
                debugV(load_inst);
                var values = [2]llvm_types.LLVMValueRef{ zero_int32_value, zero_int32_value };
                const ret = llvm_core.LLVMBuildGEP2(builder, llvm_core.LLVMTypeOf(value), load_inst, &values, 2, "");
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            }

            const alloca = llvm_core.LLVMBuildAlloca(builder, value_type, @ptrCast(""));
            _ = llvm_core.LLVMBuildStore(builder, value, alloca);
            const load = llvm_core.LLVMBuildLoad2(builder, llvm_core.LLVMGetAllocatedType(alloca), alloca, @ptrCast(""));
            const ptr_operand = llvm_core.LLVMGetOperand(load, 0);
            var values = [2]llvm_types.LLVMValueRef{ zero_int32_value, zero_int32_value };
            const ret = llvm_core.LLVMBuildGEP2(builder, value_type, ptr_operand, &values, 2, "");
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        const ret = llvm_core.LLVMBuildBitCast(builder, value, target_type, @ptrCast(""));
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
    }

    pub fn visitTypeSizeExpression(self: *Self, node: *ast.TypeSizeExpression) !*ds.Any {
        log("Visiting type size expression", .{});
        const llvm_type = try self.llvmTypeFromLangType(node.value_type.?);
        const data_layout = llvm_target.LLVMGetModuleDataLayout(self.llvm_module);
        const type_alloc_size = llvm_target.LLVMSizeOfTypeInBits(data_layout, llvm_type);
        const ret = llvm_core.LLVMConstInt(llvm_int64_type, @intCast(type_alloc_size / 8), 1);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
    }

    pub fn visitTypeAlignExpression(self: *Self, node: *ast.TypeAlignExpression) !*ds.Any {
        log("Visiting type align expression", .{});
        const llvm_type = try self.llvmTypeFromLangType(node.value_type.?);
        const data_layout = llvm_target.LLVMGetModuleDataLayout(self.llvm_module);
        const align_ = llvm_target.LLVMABIAlignmentOfType(data_layout, llvm_type);
        const ret = llvm_core.LLVMConstInt(llvm_int32_type, @intCast(align_), 1);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
    }

    pub fn visitValueSizeExpression(self: *Self, node: *ast.ValueSizeExpression) !*ds.Any {
        log("Visiting value size expression", .{});
        const llvm_type = try self.llvmTypeFromLangType(node.value.getTypeNode().?);
        const data_layout = llvm_target.LLVMGetModuleDataLayout(self.llvm_module);
        const type_alloc_size = llvm_target.LLVMSizeOfTypeInBits(data_layout, llvm_type);
        const type_size = llvm_core.LLVMConstInt(llvm_int64_type, @intCast(type_alloc_size / 8), 1);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = type_size });
    }

    pub fn visitIndexExpression(self: *Self, node: *ast.IndexExpression) !*ds.Any {
        log("Visiting index expression", .{});
        const index = try self.llvmResolveValue(try node.index.accept(self.visitor));
        const ret = try self.accessArrayElement(node.value, index);
        log("Index expression resolved", .{});
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
    }

    pub fn visitEnumAccessExpression(self: *Self, node: *ast.EnumAccessExpression) !*ds.Any {
        log("Visiting enum access expression", .{});
        const element_type = try self.llvmTypeFromLangType(node.getTypeNode().?);
        const element_index = llvm_core.LLVMConstInt(element_type, @intCast(node.enum_element_index), 0);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = element_index });
    }

    pub fn visitLiteralExpression(self: *Self, node: *ast.LiteralExpression) !*ds.Any {
        log("Visiting literal expression", .{});
        const name = node.name.literal;
        self.alloca_inst_table.printKeys();
        log("Literal name: {s}", .{name});
        const alloca_inst = self.alloca_inst_table.lookup(name);
        if (alloca_inst != null) {
            return alloca_inst.?;
        }

        const ret = llvm_core.LLVMGetNamedGlobal(self.llvm_module, self.cStr(name));
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
    }

    pub fn visitNumberExpression(self: *Self, node: *ast.NumberExpression) !*ds.Any {
        log("Visiting number expression", .{});
        const number_type = node.getTypeNode().?;
        const value = try self.llvmNumberValue(node.value.literal, number_type.Number.number_kind);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = value });
    }

    pub fn visitArrayExpression(self: *Self, node: *ast.ArrayExpression) !*ds.Any {
        log("Visiting array expression", .{});
        const node_values = node.values;
        const size = node_values.items.len;
        if (node.isConstant()) {
            const llvm_type = try self.llvmTypeFromLangType(node.getTypeNode().?);
            const array_type = llvm_type;
            var values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);
            for (node_values.items) |value| {
                const llvm_value = try self.llvmResolveValue(try value.accept(self.visitor));
                try values.append(llvm_value);
            }
            const ret = llvm_core.LLVMConstArray(array_type, @ptrCast(values.items), @intCast(values.items.len));
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
        }

        const array_type = try self.llvmTypeFromLangType(node.getTypeNode().?);
        const array_element_type = llvm_core.LLVMGetElementType(array_type);

        var values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);
        for (node_values.items) |value| {
            try values.append(try self.llvmResolveValue(try value.accept(self.visitor)));
        }

        const alloca = llvm_core.LLVMBuildAlloca(builder, array_type, @ptrCast("alloca"));
        for (0..size) |i| {
            const index = llvm_core.LLVMConstInt(llvm_int32_type, @intCast(i), 1);
            const allocated_type = llvm_core.LLVMGetAllocatedType(alloca);
            var values_ = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
            const ptr = llvm_core.LLVMBuildGEP2(builder, allocated_type, alloca, &values_, 2, "");
            var value = values.items[i];
            if (llvm_core.LLVMTypeOf(value) == llvm_core.LLVMTypeOf(ptr)) {
                value = llvm_core.LLVMBuildLoad2(builder, array_element_type, value, @ptrCast(""));
            }
            _ = llvm_core.LLVMBuildStore(builder, value, ptr);
        }

        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = alloca });
    }

    pub fn visitVectorExpression(self: *Self, node: *ast.VectorExpression) !*ds.Any {
        log("Visiting vector expression", .{});
        const array = node.array;
        const array_type = array.value_type.?.StaticArray;
        const element_type = array_type.element_type.?;
        const number_type = element_type.Number;
        const number_kind = number_type.number_kind;
        const array_values = array.values;

        switch (number_kind) {
            .UInteger8 => {
                var values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);

                for (array_values.items) |value| {
                    const number = value.number_expression;
                    const number_value = try std.fmt.parseInt(u8, number.value.literal, 10);
                    const llvm_value = llvm_core.LLVMConstInt(llvm_int8_type, @intCast(number_value), 0);
                    try values.append(llvm_value);
                }
                const ret = llvm_core.LLVMConstVector(@ptrCast(values.items), @intCast(values.items.len));
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            },

            .UInteger16 => {
                var values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);

                for (array_values.items) |value| {
                    const number = value.number_expression;
                    const number_value = try std.fmt.parseInt(i16, number.value.literal, 10);
                    const llvm_value = llvm_core.LLVMConstInt(llvm_int16_type, @intCast(number_value), 0);
                    try values.append(llvm_value);
                }
                const ret = llvm_core.LLVMConstVector(@ptrCast(values.items), @intCast(values.items.len));
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            },
            .UInteger32 => {
                var values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);

                for (array_values.items) |value| {
                    const number = value.number_expression;
                    const number_value = try std.fmt.parseInt(i32, number.value.literal, 10);
                    const llvm_value = llvm_core.LLVMConstInt(llvm_int32_type, @intCast(number_value), 0);
                    try values.append(llvm_value);
                }
                const ret = llvm_core.LLVMConstVector(@ptrCast(values.items), @intCast(values.items.len));
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            },
            .UInteger64 => {
                var values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);

                for (array_values.items) |value| {
                    const number = value.number_expression;
                    const number_value = try std.fmt.parseInt(i64, number.value.literal, 10);
                    const llvm_value = llvm_core.LLVMConstInt(llvm_int64_type, @intCast(number_value), 0);
                    try values.append(llvm_value);
                }
                const ret = llvm_core.LLVMConstVector(@ptrCast(values.items), @intCast(values.items.len));
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            },
            .Float32 => {
                var values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);

                for (array_values.items) |value| {
                    const number = value.number_expression;
                    const number_value = try std.fmt.parseFloat(f32, number.value.literal);
                    const llvm_value = llvm_core.LLVMConstReal(llvm_float32_type, number_value);
                    try values.append(llvm_value);
                }
                const ret = llvm_core.LLVMConstVector(@ptrCast(values.items), @intCast(values.items.len));
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            },
            .Float64 => {
                var values = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);

                for (array_values.items) |value| {
                    const number = value.number_expression;
                    const number_value = try std.fmt.parseFloat(f64, number.value.literal);
                    const llvm_value = llvm_core.LLVMConstReal(llvm_float64_type, number_value);
                    try values.append(llvm_value);
                }
                const ret = llvm_core.LLVMConstVector(@ptrCast(values.items), @intCast(values.items.len));
                return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
            },
            else => {
                self.internalCompilerError("Invalid vector element type");
            },
        }
        self.internalCompilerError("Invalid vector element type");

        unreachable;
    }

    pub fn visitStringExpression(self: *Self, node: *ast.StringExpression) !*ds.Any {
        log("Visiting string expression", .{});
        return self.resolveConstantStringExpression(node.value.literal);
    }

    pub fn visitCharacterExpression(self: *Self, node: *ast.CharacterExpression) !*ds.Any {
        log("Visiting character expression", .{});
        const value = node.value.literal[0];
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = llvm_core.LLVMConstInt(llvm_int8_type, @intCast(value), 0) });
    }

    pub fn visitBooleanExpression(self: *Self, node: *ast.BoolExpression) !*ds.Any {
        log("Visiting boolean expression", .{});
        const ret = llvm_core.LLVMConstInt(llvm_int1_type, @intFromBool(node.value.kind == .True), 0);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
    }

    pub fn visitNullExpression(self: *Self, node: *ast.NullExpression) !*ds.Any {
        log("Visiting null expression", .{});
        const llvm_type = try self.llvmTypeFromLangType(node.null_base_type);
        const ret = llvm_core.LLVMConstNull(llvm_type);
        debugV(ret);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
    }

    pub fn visitUndefinedExpression(self: *Self, node: *ast.UndefinedExpression) !*ds.Any {
        log("Visiting undefined expression", .{});
        const llvm_type = try self.llvmTypeFromLangType(node.base_type.?);
        const ret = llvm_core.LLVMGetUndef(llvm_type);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = ret });
    }

    pub fn visitInfinityExpression(self: *Self, node: *ast.InfinityExpression) !*ds.Any {
        log("Visiting infinity expression", .{});
        const type_ = try self.llvmTypeFromLangType(node.getTypeNode().?);
        const value = llvm_core.LLVMConstReal(type_, std.math.inf(f64));
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = value });
    }

    fn llvmNodeValue(self: *Self, any_value: *ds.Any) !llvm_types.LLVMValueRef {
        _ = self;
        log("Resolving LLVM Node Value", .{});
        return any_value.LLVMValue;
    }

    fn llvmResolveValue(self: *Self, any_value: *ds.Any) !llvm_types.LLVMValueRef {
        log("Resolving value", .{});
        const llvm_value = try self.llvmNodeValue(any_value);

        if (llvm_core.LLVMIsAAllocaInst(llvm_value) != null) {
            return llvm_core.LLVMBuildLoad2(builder, llvm_core.LLVMGetAllocatedType(llvm_value), llvm_value, @ptrCast(""));
        }

        if (llvm_core.LLVMIsAGlobalVariable(llvm_value) != null) {
            return llvm_core.LLVMGetInitializer(llvm_value);
        }

        return llvm_value;
    }

    fn llvmResolveVariable(self: *Self, name: []const u8) !llvm_types.LLVMValueRef {
        log("Resolving variable", .{});
        _ = name;
        _ = self;
        return Error.NotImplemented;
    }

    fn llvmNumberValue(self: *Self, value_literal: []const u8, size: types.NumberKind) !llvm_types.LLVMValueRef {
        _ = self;
        log("Resolving LLVM Number Value", .{});

        switch (size) {
            .Integer1 => {
                const value = try std.fmt.parseInt(i64, value_literal, 10);
                return llvm_core.LLVMConstInt(llvm_int1_type, @intCast(value), 1);
            },
            .Integer8 => {
                const value = try std.fmt.parseInt(i64, value_literal, 10);
                return llvm_core.LLVMConstInt(llvm_int8_type, @intCast(value), 1);
            },
            .Integer16 => {
                const value = try std.fmt.parseInt(i64, value_literal, 10);
                return llvm_core.LLVMConstInt(llvm_int16_type, @intCast(value), 1);
            },
            .Integer32 => {
                const value = try std.fmt.parseInt(i64, value_literal, 10);
                return llvm_core.LLVMConstInt(llvm_int32_type, @intCast(value), 1);
            },
            .Integer64 => {
                const value = try std.fmt.parseInt(i64, value_literal, 10);
                return llvm_core.LLVMConstInt(llvm_int64_type, @intCast(value), 1);
            },
            .UInteger8 => {
                const value = try std.fmt.parseInt(u64, value_literal, 10);
                return llvm_core.LLVMConstInt(llvm_int8_type, @intCast(value), 0);
            },
            .UInteger16 => {
                const value = try std.fmt.parseInt(u64, value_literal, 10);
                return llvm_core.LLVMConstInt(llvm_int16_type, @intCast(value), 0);
            },
            .UInteger32 => {
                const value = try std.fmt.parseInt(u64, value_literal, 10);
                return llvm_core.LLVMConstInt(llvm_int32_type, @intCast(value), 0);
            },
            .UInteger64 => {
                const value = try std.fmt.parseInt(u64, value_literal, 10);
                return llvm_core.LLVMConstInt(llvm_int64_type, @intCast(value), 0);
            },
            .Float32 => {
                const value = try std.fmt.parseFloat(f32, value_literal);
                return llvm_core.LLVMConstReal(llvm_float32_type, value);
            },
            .Float64 => {
                const value = try std.fmt.parseFloat(f64, value_literal);
                return llvm_core.LLVMConstReal(llvm_float64_type, value);
            },
        }
    }

    fn llvmTypeFromLangType(self: *Self, type_: *types.Type) Error!llvm_types.LLVMTypeRef {
        log("Resolving LLVM Type from Lang Type", .{});
        const type_kind = type_.typeKind();
        if (type_kind == .Number) {
            const number_type = type_.Number;
            switch (number_type.number_kind) {
                .Integer1 => return llvm_int1_type,
                .Integer8 => return llvm_int8_type,
                .Integer16 => return llvm_int16_type,
                .Integer32 => return llvm_int32_type,
                .Integer64 => return llvm_int64_type,
                .UInteger8 => return llvm_int8_type,
                .UInteger16 => return llvm_int16_type,
                .UInteger32 => return llvm_int32_type,
                .UInteger64 => return llvm_int64_type,
                .Float32 => return llvm_float32_type,
                .Float64 => return llvm_float64_type,
            }
        }

        if (type_kind == .StaticArray) {
            const array_type = type_.StaticArray;
            const element_type = try self.llvmTypeFromLangType(array_type.element_type.?);
            return llvm_core.LLVMArrayType(element_type, @intCast(array_type.size));
        }

        if (type_kind == .StaticVector) {
            const vector_type = type_.StaticVector;
            const array_type = vector_type.array;
            const element_type = try self.llvmTypeFromLangType(array_type.element_type.?);
            return llvm_core.LLVMVectorType(element_type, @intCast(array_type.size));
        }

        if (type_kind == .Pointer) {
            const pointer_type = type_.Pointer;
            const pointer_base = pointer_type.base_type;
            if (pointer_base.typeKind() == .Void) {
                return llvm_void_ptr_type;
            }

            if (pointer_base.typeKind() == .Struct) {
                const struct_type = pointer_base.Struct;
                if (std.mem.eql(u8, struct_type.name, std.mem.span(llvm_core.LLVMGetStructName(self.current_struct_type)))) {
                    return llvm_core.LLVMPointerType(self.current_struct_type, 0);
                }
            }

            const point_to_type = try self.llvmTypeFromLangType(pointer_base);
            return llvm_core.LLVMPointerType(point_to_type, 0);
        }

        if (type_kind == .Function) {
            const function_type = type_.Function;
            const parameters = function_type.parameters;
            const parameters_size = parameters.items.len;
            var arguments = std.ArrayList(llvm_types.LLVMTypeRef).init(self.allocator);
            try arguments.resize(parameters_size);

            for (0..parameters_size) |i| {
                arguments.items[i] = try self.llvmTypeFromLangType(parameters.items[i]);
            }
            const return_type = try self.llvmTypeFromLangType(function_type.return_type);
            return llvm_core.LLVMFunctionType(return_type, @ptrCast(arguments.items), @intCast(parameters_size), @intFromBool(function_type.has_varargs));
        }

        if (type_kind == .Struct) {
            const struct_type = type_.Struct;
            const struct_name = struct_type.name;
            if (self.structures_types_map.contains(struct_name)) {
                return self.structures_types_map.get(struct_name).?;
            }

            return self.createLLVMStructType(struct_name, struct_type.field_types.items, struct_type.is_packed, struct_type.is_extern);
        }

        if (type_kind == .Tuple) {
            var tuple_type = type_.Tuple;
            if (std.mem.eql(u8, tuple_type.name, "_tuple_")) {
                var resolved_fields = std.ArrayList(*types.Type).init(self.allocator);
                for (tuple_type.field_types.items) |field| {
                    if (field.typeKind() == .GenericParameter) {
                        const generic_type = field.GenericParameter;
                        if (self.generic_types.contains(generic_type.name)) {
                            try resolved_fields.append(self.generic_types.get(generic_type.name).?);
                            continue;
                        }
                    }
                    try resolved_fields.append(field);
                }
                const new_tuple = try std.fmt.allocPrint(self.allocator, "_tuple_{s}", .{try types.mangleTypes(self.allocator, resolved_fields.items)});
                tuple_type = types.TupleType.init(new_tuple, resolved_fields);
            }
            return self.createLLVMStructType(tuple_type.name, tuple_type.field_types.items, false, false);
        }

        if (type_kind == .EnumElement) {
            return self.llvmTypeFromLangType(type_.EnumElement.element_type);
        }

        if (type_kind == .Void) {
            return llvm_void_type;
        }

        if (type_kind == .GenericStruct) {
            return self.resolveGenericStruct(&type_.GenericStruct);
        }

        if (type_kind == .GenericParameter) {
            const generic_parameter = type_.GenericParameter;
            const generic_name = generic_parameter.name;
            if (!self.generic_types.contains(generic_name)) {
                self.internalCompilerError("Trying to resolve an invalid generic parameter name");
            }
            return self.llvmTypeFromLangType(self.generic_types.get(generic_name).?);
        }
        log("Can't find LLVM Type for this Type: {any}", .{type_});
        self.internalCompilerError("Can't find LLVM Type for  this Type");

        unreachable;
    }

    fn createGlobalFieldDeclaration(self: *Self, name: []const u8, value: *ast.Expression, type_: *types.Type) !void {
        log("Creating global field declaration", .{});
        _ = name;
        _ = value;
        _ = type_;
        _ = self;
        return Error.NotImplemented;
    }

    fn createLLVMNumbersBinary(self: *Self, op: tokenizer.TokenKind, left: llvm_types.LLVMValueRef, right: llvm_types.LLVMValueRef) !llvm_types.LLVMValueRef {
        log("Creating LLVM numbers binary", .{});
        const lhs_type = llvm_core.LLVMTypeOf(left);
        const rhs_type = llvm_core.LLVMTypeOf(right);
        if (llvm_core.LLVMGetTypeKind(lhs_type) == .LLVMIntegerTypeKind and llvm_core.LLVMGetTypeKind(rhs_type) == .LLVMIntegerTypeKind) {
            return self.createLLVMIntegersBinary(op, left, right);
        }

        if (isFloatingPointTy(lhs_type) and isFloatingPointTy(rhs_type)) {
            return self.createLLVMFloatsBinary(op, left, right);
        }

        self.internalCompilerError("Invalid binary operator for numbers types");
        unreachable;
    }

    fn createLLVMIntegersBinary(self: *Self, op: tokenizer.TokenKind, left: llvm_types.LLVMValueRef, right: llvm_types.LLVMValueRef) llvm_types.LLVMValueRef {
        log("Creating LLVM integers binary", .{});
        switch (op) {
            .Plus => return llvm_core.LLVMBuildAdd(builder, left, right, @ptrCast("addtmp")),
            .Minus => return llvm_core.LLVMBuildSub(builder, left, right, @ptrCast("subtmp")),
            .Star => return llvm_core.LLVMBuildMul(builder, left, right, @ptrCast("multmp")),
            .Slash => return llvm_core.LLVMBuildUDiv(builder, left, right, @ptrCast("divtmp")),
            .Percent => return llvm_core.LLVMBuildURem(builder, left, right, @ptrCast("remtmp")),
            else => self.internalCompilerError("Invalid binary operator for integers types"),
        }
        unreachable;
    }

    fn createLLVMFloatsBinary(self: *Self, op: tokenizer.TokenKind, left: llvm_types.LLVMValueRef, right: llvm_types.LLVMValueRef) llvm_types.LLVMValueRef {
        log("Creating LLVM floats binary", .{});
        switch (op) {
            .Plus => return llvm_core.LLVMBuildFAdd(builder, left, right, @ptrCast("addtmp")),
            .Minus => return llvm_core.LLVMBuildFSub(builder, left, right, @ptrCast("subtmp")),
            .Star => return llvm_core.LLVMBuildFMul(builder, left, right, @ptrCast("multmp")),
            .Slash => return llvm_core.LLVMBuildFDiv(builder, left, right, @ptrCast("divtmp")),
            .Percent => return llvm_core.LLVMBuildFRem(builder, left, right, @ptrCast("remtmp")),
            else => self.internalCompilerError("Invalid binary operator for floats types"),
        }
        unreachable;
    }

    fn createLLVMIntegersVectorsBinary(self: *Self, op: tokenizer.TokenKind, left: llvm_types.LLVMValueRef, right: llvm_types.LLVMValueRef) llvm_types.LLVMValueRef {
        log("Creating LLVM integers vectors binary {any}", .{op});
        switch (op) {
            .Plus => return llvm_core.LLVMBuildAdd(builder, left, right, @ptrCast("addtmp")),
            .Minus => return llvm_core.LLVMBuildSub(builder, left, right, @ptrCast("subtmp")),
            .Star => return llvm_core.LLVMBuildMul(builder, left, right, @ptrCast("multmp")),
            .Slash => return llvm_core.LLVMBuildUDiv(builder, left, right, @ptrCast("divtmp")),
            .Percent => return llvm_core.LLVMBuildURem(builder, left, right, @ptrCast("remtmp")),
            else => self.internalCompilerError("Invalid binary operator for integers vectors types"),
        }
        unreachable;
    }

    fn createLLVMFloatsVectorsBinary(self: *Self, op: tokenizer.TokenKind, left: llvm_types.LLVMValueRef, right: llvm_types.LLVMValueRef) llvm_types.LLVMValueRef {
        log("Creating LLVM floats vectors binary", .{});
        switch (op) {
            .Plus => return llvm_core.LLVMBuildFAdd(builder, left, right, @ptrCast("addtmp")),
            .Minus => return llvm_core.LLVMBuildFSub(builder, left, right, @ptrCast("subtmp")),
            .Star => return llvm_core.LLVMBuildFMul(builder, left, right, @ptrCast("multmp")),
            .Slash => return llvm_core.LLVMBuildFDiv(builder, left, right, @ptrCast("divtmp")),
            .Percent => return llvm_core.LLVMBuildFRem(builder, left, right, @ptrCast("remtmp")),
            else => self.internalCompilerError("Invalid binary operator for floats vectors types"),
        }
        unreachable;
    }

    fn createLLVMNumbersComparison(self: *Self, op: tokenizer.TokenKind, left: llvm_types.LLVMValueRef, right: llvm_types.LLVMValueRef) !llvm_types.LLVMValueRef {
        log("Creating LLVM numbers comparison", .{});
        _ = op;
        _ = left;
        _ = right;
        _ = self;
        return Error.NotImplemented;
    }

    fn createLLVMIntegersComparison(self: *Self, op: tokenizer.TokenKind, left: llvm_types.LLVMValueRef, right: llvm_types.LLVMValueRef) llvm_types.LLVMValueRef {
        log("Creating LLVM integers comparison", .{});
        switch (op) {
            .EqualEqual => return llvm_core.LLVMBuildICmp(builder, .LLVMIntEQ, left, right, @ptrCast("")),
            .BangEqual => return llvm_core.LLVMBuildICmp(builder, .LLVMIntNE, left, right, @ptrCast("")),
            .Greater => return llvm_core.LLVMBuildICmp(builder, .LLVMIntSGT, left, right, @ptrCast("")),
            .GreaterEqual => return llvm_core.LLVMBuildICmp(builder, .LLVMIntSGE, left, right, @ptrCast("")),
            .Smaller => return llvm_core.LLVMBuildICmp(builder, .LLVMIntSLT, left, right, @ptrCast("")),
            .SmallerEqual => return llvm_core.LLVMBuildICmp(builder, .LLVMIntSLE, left, right, @ptrCast("")),
            else => self.internalCompilerError("Invalid comparison operator for integers types"),
        }
        unreachable;
    }

    fn createLLVMUnsignedIntegersComparison(self: *Self, op: tokenizer.TokenKind, left: llvm_types.LLVMValueRef, right: llvm_types.LLVMValueRef) llvm_types.LLVMValueRef {
        log("Creating LLVM unsigned integers comparison", .{});
        switch (op) {
            .EqualEqual => return llvm_core.LLVMBuildICmp(builder, .LLVMIntEQ, left, right, @ptrCast("")),
            .BangEqual => return llvm_core.LLVMBuildICmp(builder, .LLVMIntNE, left, right, @ptrCast("")),
            .Greater => return llvm_core.LLVMBuildICmp(builder, .LLVMIntUGT, left, right, @ptrCast("")),
            .GreaterEqual => return llvm_core.LLVMBuildICmp(builder, .LLVMIntUGE, left, right, @ptrCast("")),
            .Smaller => return llvm_core.LLVMBuildICmp(builder, .LLVMIntULT, left, right, @ptrCast("")),
            .SmallerEqual => return llvm_core.LLVMBuildICmp(builder, .LLVMIntULE, left, right, @ptrCast("")),
            else => self.internalCompilerError("Invalid comparison operator for unsigned integers types"),
        }
        unreachable;
    }

    fn createLLVMFloatsComparison(self: *Self, op: tokenizer.TokenKind, left: llvm_types.LLVMValueRef, right: llvm_types.LLVMValueRef) llvm_types.LLVMValueRef {
        log("Creating LLVM floats comparison", .{});
        switch (op) {
            .EqualEqual => return llvm_core.LLVMBuildFCmp(builder, .LLVMRealOEQ, left, right, @ptrCast("")),
            .BangEqual => return llvm_core.LLVMBuildFCmp(builder, .LLVMRealONE, left, right, @ptrCast("")),
            .Greater => return llvm_core.LLVMBuildFCmp(builder, .LLVMRealOGT, left, right, @ptrCast("")),
            .GreaterEqual => return llvm_core.LLVMBuildFCmp(builder, .LLVMRealOGE, left, right, @ptrCast("")),
            .Smaller => return llvm_core.LLVMBuildFCmp(builder, .LLVMRealOLT, left, right, @ptrCast("")),
            .SmallerEqual => return llvm_core.LLVMBuildFCmp(builder, .LLVMRealOLE, left, right, @ptrCast("")),
            else => self.internalCompilerError("Invalid comparison operator for floats types"),
        }
        unreachable;
    }

    fn createLLVMStringsComparison(self: *Self, op: tokenizer.TokenKind, left: llvm_types.LLVMValueRef, right: llvm_types.LLVMValueRef) !llvm_types.LLVMValueRef {
        log("Creating LLVM strings comparison", .{});
        const function_name = "strcmp";
        var function = (try self.lookupFunction(function_name)).?;

        if (function == null) {
            var param_types = [2]llvm_types.LLVMTypeRef{ llvm_core.LLVMPointerType(llvm_int8_type, 0), llvm_core.LLVMPointerType(llvm_int8_type, 0) };
            const fun_type = llvm_core.LLVMFunctionType(llvm_int32_type, &param_types, 2, 0);
            function = llvm_core.LLVMAddFunction(self.llvm_module, self.cStr(function_name), fun_type);
            llvm_core.LLVMSetLinkage(function, .LLVMExternalLinkage);
        }
        var types_ = [2]llvm_types.LLVMValueRef{ left, right };
        const function_call = llvm_core.LLVMBuildCall2(builder, llvm_core.LLVMGetElementType(llvm_core.LLVMTypeOf(function)), function, &types_, 2, "");

        switch (op) {
            .EqualEqual => return llvm_core.LLVMBuildICmp(builder, .LLVMIntEQ, function_call, zero_int32_value, @ptrCast("")),
            .BangEqual => return llvm_core.LLVMBuildICmp(builder, .LLVMIntNE, function_call, zero_int32_value, @ptrCast("")),
            .Greater => return llvm_core.LLVMBuildICmp(builder, .LLVMIntSGT, function_call, zero_int32_value, @ptrCast("")),
            .GreaterEqual => return llvm_core.LLVMBuildICmp(builder, .LLVMIntSGE, function_call, zero_int32_value, @ptrCast("")),
            .Smaller => return llvm_core.LLVMBuildICmp(builder, .LLVMIntSLT, function_call, zero_int32_value, @ptrCast("")),
            .SmallerEqual => return llvm_core.LLVMBuildICmp(builder, .LLVMIntSLE, function_call, zero_int32_value, @ptrCast("")),
            else => self.internalCompilerError("Invalid comparison operator for strings types"),
        }
        unreachable;
    }

    fn createLLVMValueIncrement(self: *Self, operand: *ast.Expression, is_prefix: bool) !llvm_types.LLVMValueRef {
        log("Creating LLVM value increment", .{});
        const number_type = operand.getTypeNode().?.Number;
        const constants_one = try self.llvmNumberValue("1", number_type.number_kind);
        var right: llvm_types.LLVMValueRef = undefined;

        if (operand.getAstNodeType() == .Dot) {
            right = try self.accessStructMemberPointer3(&operand.dot_expression);
        } else {
            right = try self.llvmNodeValue(try operand.accept(self.visitor));
        }

        if (llvm_core.LLVMIsALoadInst(right) != null) {
            const new_value = self.createLLVMIntegersBinary(.Plus, right, constants_one);
            _ = llvm_core.LLVMBuildStore(builder, new_value, llvm_core.LLVMGetOperand(right, 0));
            if (is_prefix) {
                return new_value;
            } else {
                return right;
            }
        }

        if (llvm_core.LLVMIsAAllocaInst(right) != null) {
            const current_value = llvm_core.LLVMBuildLoad2(builder, llvm_core.LLVMGetAllocatedType(right), right, @ptrCast(""));
            const new_value = self.createLLVMIntegersBinary(.Plus, current_value, constants_one);
            _ = llvm_core.LLVMBuildStore(builder, new_value, right);
            if (is_prefix) {
                return new_value;
            } else {
                return current_value;
            }
        }

        if (llvm_core.LLVMIsAGlobalVariable(right) != null) {
            const global_variable_type = llvm_core.LLVMGlobalGetValueType(right);
            const current_value = llvm_core.LLVMBuildLoad2(builder, global_variable_type, right, @ptrCast(""));
            const new_value = self.createLLVMIntegersBinary(.Plus, current_value, constants_one);
            _ = llvm_core.LLVMBuildStore(builder, new_value, right);
            if (is_prefix) {
                return new_value;
            } else {
                return current_value;
            }
        }

        // More than likely wrong
        // if (llvm_core.LLVMTypeOf(right) == number_llvm_type) {
        if (llvm_core.LLVMGetTypeKind(llvm_core.LLVMTypeOf(right)) == .LLVMPointerTypeKind) {
            const number_llvm_type = try self.llvmTypeFromLangType(operand.getTypeNode().?);

            const current_value = llvm_core.LLVMBuildLoad2(builder, number_llvm_type, right, @ptrCast(""));
            const new_value = self.createLLVMIntegersBinary(.Plus, current_value, constants_one);
            _ = llvm_core.LLVMBuildStore(builder, new_value, right);
            if (is_prefix) {
                return new_value;
            } else {
                return current_value;
            }
        }
        self.internalCompilerError("Invalid operand for increment");
        unreachable;
    }

    fn createLLVMValueDecrement(self: *Self, operand: *ast.Expression, is_prefix: bool) !llvm_types.LLVMValueRef {
        log("Creating LLVM value decrement", .{});
        const number_type = operand.getTypeNode().?.Number;
        const constants_one = try self.llvmNumberValue("1", number_type.number_kind);

        var right: llvm_types.LLVMValueRef = undefined;
        if (operand.getAstNodeType() == .Dot) {
            right = try self.accessStructMemberPointer3(&operand.dot_expression);
        } else {
            right = try self.llvmNodeValue(try operand.accept(self.visitor));
        }

        if (llvm_core.LLVMIsALoadInst(right) != null) {
            const new_value = self.createLLVMIntegersBinary(.Minus, right, constants_one);
            _ = llvm_core.LLVMBuildStore(builder, new_value, llvm_core.LLVMGetOperand(right, 0));
            if (is_prefix) {
                return new_value;
            } else {
                return right;
            }
        }

        if (llvm_core.LLVMIsAAllocaInst(right) != null) {
            const current_value = llvm_core.LLVMBuildLoad2(builder, llvm_core.LLVMGetAllocatedType(right), right, @ptrCast(""));
            const new_value = self.createLLVMIntegersBinary(.Minus, current_value, constants_one);
            _ = llvm_core.LLVMBuildStore(builder, new_value, right);
            if (is_prefix) {
                return new_value;
            } else {
                return current_value;
            }
        }

        if (llvm_core.LLVMIsAGlobalVariable(right) != null) {
            const global_variable_type = llvm_core.LLVMGlobalGetValueType(right);
            const current_value = llvm_core.LLVMBuildLoad2(builder, global_variable_type, right, @ptrCast(""));
            const new_value = self.createLLVMIntegersBinary(.Minus, current_value, constants_one);
            _ = llvm_core.LLVMBuildStore(builder, new_value, right);
            if (is_prefix) {
                return new_value;
            } else {
                return current_value;
            }
        }

        // if (llvm_core.LLVMTypeOf(right) == llvm_core.LLVMTypeOf(constants_one)) {
        if (llvm_core.LLVMGetTypeKind(llvm_core.LLVMTypeOf(right)) == .LLVMPointerTypeKind) {
            const number_llvm_type = try self.llvmTypeFromLangType(operand.getTypeNode().?);
            const current_value = llvm_core.LLVMBuildLoad2(builder, number_llvm_type, right, @ptrCast(""));
            const new_value = self.createLLVMIntegersBinary(.Minus, current_value, constants_one);
            _ = llvm_core.LLVMBuildStore(builder, new_value, right);
            if (is_prefix) {
                return new_value;
            } else {
                return current_value;
            }
        }

        self.internalCompilerError("Invalid operand for decrement");

        unreachable;
    }

    fn createLLVMStringLength(self: *Self, string: llvm_types.LLVMValueRef) !llvm_types.LLVMValueRef {
        log("Creating LLVM string length", .{});
        _ = string;
        _ = self;
        return Error.NotImplemented;
    }

    fn createLLVMStructType(self: *Self, name: []const u8, members: []const *types.Type, is_packed: bool, is_extern: bool) !llvm_types.LLVMTypeRef {
        log("Creating LLVM struct type", .{});
        if (self.structures_types_map.contains(name)) {
            return self.structures_types_map.get(name).?;
        }

        const struct_llvm_type = llvm_core.LLVMStructCreateNamed(llvm_context, self.cStr(name));

        if (name.len < 6 or !std.mem.eql(u8, "_tuple", name[0..6])) {
            self.current_struct_type = struct_llvm_type;
        }

        if (is_extern) {
            try self.structures_types_map.put(name, struct_llvm_type);
            return struct_llvm_type;
        }

        var struct_fields = std.ArrayList(llvm_types.LLVMTypeRef).init(self.allocator);

        for (members) |field| {
            if (field.typeKind() == .Pointer) {
                const pointer_type = field.Pointer;
                const base = pointer_type.base_type;
                if (base.typeKind() == .Struct) {
                    const struct_type = base.Struct;
                    if (self.current_struct_type != null and std.mem.eql(u8, struct_type.name, std.mem.span(llvm_core.LLVMGetStructName(self.current_struct_type)))) {
                        try struct_fields.append(llvm_core.LLVMPointerType(self.current_struct_type, 0));
                        continue;
                    }
                }
            }

            try struct_fields.append(try self.llvmTypeFromLangType(field));
        }
        llvm_core.LLVMStructSetBody(struct_llvm_type, @ptrCast(struct_fields.items), @intCast(struct_fields.items.len), @intFromBool(is_packed));
        try self.structures_types_map.put(name, struct_llvm_type);

        return struct_llvm_type;
    }

    fn createOverloadingFunctionCall(self: *Self, name: []const u8, args: []llvm_types.LLVMValueRef) !llvm_types.LLVMValueRef {
        log("Creating overloading function call {s}", .{name});
        const function = (try self.lookupFunction(name)).?;
        const call = llvm_core.LLVMBuildCall2(builder, llvm_core.LLVMGetElementType(llvm_core.LLVMTypeOf(function)), function, @ptrCast(args), @intCast(args.len), "");
        return call;
    }

    fn accessStructMemberPointer(self: *Self, callee_value: llvm_types.LLVMValueRef, type_: llvm_types.LLVMTypeRef, field_index: u32) !llvm_types.LLVMValueRef {
        log("Accessing struct member pointer", .{});
        const callee_llvm_type = type_;
        const index = llvm_core.LLVMConstInt(llvm_int32_type, @intCast(field_index), 1);
        if (llvm_core.LLVMGetTypeKind(callee_llvm_type) == .LLVMStructTypeKind) {
            if (llvm_core.LLVMIsAPHINode(callee_value) != null) {
                const struct_type = llvm_core.LLVMTypeOf(callee_value);
                const alloca = llvm_core.LLVMBuildAlloca(builder, struct_type, self.cStr("alloca"));
                _ = llvm_core.LLVMBuildStore(builder, callee_value, alloca);
                var values = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
                return llvm_core.LLVMBuildGEP2(builder, callee_llvm_type, alloca, &values, 2, "");
            }

            if (llvm_core.LLVMIsAAllocaInst(callee_value) != null) {
                var values = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
                return llvm_core.LLVMBuildGEP2(builder, callee_llvm_type, callee_value, &values, 2, "");
            }

            if (llvm_core.LLVMIsALoadInst(callee_value) != null) {
                const operand = llvm_core.LLVMGetOperand(callee_value, 0);
                if (llvm_core.LLVMIsAGetElementPtrInst(operand) != null) {
                    var values = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
                    return llvm_core.LLVMBuildGEP2(builder, callee_llvm_type, operand, &values, 2, "");
                }
            }
            var values = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
            return llvm_core.LLVMBuildGEP2(builder, callee_llvm_type, callee_value, &values, 2, "");
        }

        if (llvm_core.LLVMGetTypeKind(callee_llvm_type) == .LLVMPointerTypeKind) {
            const struct_type = llvm_core.LLVMGetElementType(callee_llvm_type);
            const struct_value = dereferencesLLVMPointer(callee_value, .Load);
            var values = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
            return llvm_core.LLVMBuildGEP2(builder, struct_type, struct_value, &values, 2, "");
        }

        if (llvm_core.LLVMGetTypeKind(callee_llvm_type) == .LLVMFunctionTypeKind) {
            const struct_type = llvm_core.LLVMGetElementType(callee_llvm_type);
            const alloca = llvm_core.LLVMBuildAlloca(builder, struct_type, "");
            var values = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
            return llvm_core.LLVMBuildGEP2(builder, struct_type, alloca, &values, 2, "");
        }
        unreachable;
    }

    fn accessStructMemberPointer2(self: *Self, callee: *ast.Expression, field_index: u32) !llvm_types.LLVMValueRef {
        log("Accessing struct member pointer 2", .{});
        const callee_value = try self.llvmNodeValue(try callee.accept(self.visitor));
        const callee_type = try self.llvmTypeFromLangType(callee.getTypeNode().?);
        return self.accessStructMemberPointer(callee_value, callee_type, field_index);
    }

    fn accessStructMemberPointer3(self: *Self, expression: *const ast.DotExpression) !llvm_types.LLVMValueRef {
        log("Accessing struct member pointer 3", .{});
        const callee = expression.callee;
        return self.accessStructMemberPointer2(callee, expression.field_index);
    }

    fn accessArrayElement(self: *Self, node_value: *ast.Expression, index: llvm_types.LLVMValueRef) !llvm_types.LLVMValueRef {
        log("Accessing array element", .{});
        const values = node_value.getTypeNode().?;

        if (values.typeKind() == .Pointer) {
            const pointer_type = values.Pointer;
            const element_type = try self.llvmTypeFromLangType(pointer_type.base_type);
            const value = try self.llvmResolveValue(try node_value.accept(self.visitor));
            var values_ = [1]llvm_types.LLVMValueRef{index};
            const ptr = llvm_core.LLVMBuildGEP2(builder, element_type, value, &values_, 1, "");
            return llvm_core.LLVMBuildLoad2(builder, element_type, ptr, "");
        }

        switch (node_value.*) {
            .literal_expression => |*array_literal| {
                const array = try array_literal.accept(self.visitor);
                if (llvm_core.LLVMIsAAllocaInst(array.LLVMValue) != null) {
                    const alloca = try self.llvmNodeValue(array);
                    const alloca_type = llvm_core.LLVMGetAllocatedType(alloca);
                    var values_ = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
                    const ptr = llvm_core.LLVMBuildGEP2(builder, alloca_type, alloca, &values_, 2, "");
                    const element_type = llvm_core.LLVMGetElementType(alloca_type);
                    if (llvm_core.LLVMGetTypeKind(element_type) == .LLVMPointerTypeKind or llvm_core.LLVMGetTypeKind(element_type) == .LLVMStructTypeKind) {
                        return ptr;
                    }

                    return dereferencesLLVMPointer(ptr, .Load);
                }

                if (llvm_core.LLVMIsAGlobalVariable(array.LLVMValue) != null) {
                    const global_variable_array = try self.llvmNodeValue(array);
                    const local_insert_block = llvm_core.LLVMGetInsertBlock(builder);
                    if (local_insert_block != null) {
                        var values_ = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
                        const ptr = llvm_core.LLVMBuildGEP2(builder, llvm_core.LLVMGlobalGetValueType(global_variable_array), global_variable_array, &values_, 2, "");
                        return dereferencesLLVMPointer(ptr, .GEP);
                    }

                    const initializer = llvm_core.LLVMGetInitializer(global_variable_array);
                    const constants_index = index;

                    if (llvm_core.LLVMIsAConstantDataArray(initializer) != null) {
                        return llvm_core.LLVMGetElementAsConstant(initializer, @intCast(llvm_core.LLVMConstIntGetZExtValue(constants_index)));
                    }

                    if (llvm_core.LLVMIsAConstantArray(initializer) != null) {
                        return llvm_core.LLVMGetOperand(initializer, @intCast(llvm_core.LLVMConstIntGetZExtValue(constants_index)));
                    }

                    if (llvm_core.LLVMIsAConstant(initializer) != null) {
                        return llvm_core.LLVMGetElementAsConstant(initializer, @intCast(llvm_core.LLVMConstIntGetZExtValue(constants_index)));
                        // return llvm_core.LLVMGetAggregateElement(initializer, @intCast(llvm_core.LLVMConstIntGetZExtValue(constants_index)));
                    }
                }
                self.internalCompilerError("Index expression with literal must have alloca or global variable");
            },
            .index_expression => {
                const array = try self.llvmNodeValue(try node_value.accept(self.visitor));
                if (llvm_core.LLVMIsALoadInst(array) != null) {
                    var values_ = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
                    const ptr = llvm_core.LLVMBuildGEP2(builder, llvm_core.LLVMTypeOf(array), array, &values_, 2, "");
                    return dereferencesLLVMPointer(ptr, .Load);
                }

                if (llvm_core.LLVMIsAConstant(array) != null) {
                    return llvm_core.LLVMGetElementAsConstant(array, @intCast(llvm_core.LLVMConstIntGetZExtValue(index)));
                    // return llvm_core.LLVMGetAggregateElement(array, @intCast(llvm_core.LLVMConstIntGetZExtValue(index)));
                }
            },
            .array_expression => {
                const array = try self.llvmNodeValue(try node_value.accept(self.visitor));
                if (llvm_core.LLVMIsALoadInst(array) != null) {
                    var values_ = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
                    const ptr = llvm_core.LLVMBuildGEP2(builder, llvm_core.LLVMGetElementType(llvm_core.LLVMTypeOf(array)), array, &values_, 2, "");
                    return dereferencesLLVMPointer(ptr, .Load);
                }

                if (llvm_core.LLVMIsAConstant(array) != null) {
                    // return llvm_core.LLVMGetAggregateElement(array, @intCast(llvm_core.LLVMConstIntGetZExtValue(index)));
                    return llvm_core.LLVMGetElementAsConstant(array, @intCast(llvm_core.LLVMConstIntGetZExtValue(index)));
                }
            },
            .dot_expression => |*dot_expression| {
                const struct_field = try dot_expression.accept(self.visitor);
                if (llvm_core.LLVMIsALoadInst(struct_field.LLVMValue) != null) {
                    var values_ = [2]llvm_types.LLVMValueRef{ zero_int32_value, index };
                    const operand = llvm_core.LLVMGetOperand(struct_field.LLVMValue, 0);
                    const ptr = llvm_core.LLVMBuildGEP2(builder, llvm_core.LLVMTypeOf(struct_field.LLVMValue), operand, &values_, 2, "");
                    return dereferencesLLVMPointer(ptr, .Load);
                }
            },
            else => {},
        }
        self.internalCompilerError("Invalid array element access");
        unreachable;
    }

    fn resolveGenericFunction(self: *Self, node: *ast.FunctionDeclaration, generic_parameters: []const *types.Type) !llvm_types.LLVMValueRef {
        log("Resolving generic function", .{});
        self.is_on_global_scope = false;
        const prototype = node.prototype;
        const name = prototype.name.literal;
        const mangled_name = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ name, try types.mangleTypes(self.allocator, generic_parameters) });

        if (self.alloca_inst_table.isDefined(mangled_name)) {
            return self.alloca_inst_table.lookup(mangled_name).?.LLVMValue;
        }

        var generic_parameter_idx: usize = 0;
        for (prototype.generic_parameters.items) |parameter| {
            try self.generic_types.put(parameter, generic_parameters[generic_parameter_idx]);
            generic_parameter_idx += 1;
        }

        var return_type = prototype.return_type.?;
        if (prototype.return_type.?.typeKind() == .GenericParameter) {
            const generic_type = return_type.GenericParameter;
            return_type = self.generic_types.get(generic_type.name).?;
        }

        var arguments = std.ArrayList(llvm_types.LLVMTypeRef).init(self.allocator);
        for (prototype.parameters.items) |parameter| {
            if (parameter.parameter_type.typeKind() == .GenericParameter) {
                const generic_type = parameter.parameter_type.GenericParameter;
                try arguments.append(try self.llvmTypeFromLangType(self.generic_types.get(generic_type.name).?));
            } else {
                try arguments.append(try self.llvmTypeFromLangType(parameter.parameter_type));
            }
        }

        try self.functions_table.put(mangled_name, prototype);
        var linkage: llvm_types.LLVMLinkage = .LLVMInternalLinkage;
        if (std.mem.eql(u8, name, "main")) {
            linkage = .LLVMExternalLinkage;
        }
        const function_type = llvm_core.LLVMFunctionType(try self.llvmTypeFromLangType(return_type), @ptrCast(arguments.items), @intCast(arguments.items.len), 0);
        const previous_insert_block = llvm_core.LLVMGetInsertBlock(builder);
        const function = llvm_core.LLVMAddFunction(self.llvm_module, self.cStr(mangled_name), function_type);
        llvm_core.LLVMSetLinkage(function, linkage);
        try self.function_types_map.put(mangled_name, function_type);

        var index: usize = 0;
        const args = llvm_core.LLVMCountParams(function);

        for (0..args) |i| {
            const arg = llvm_core.LLVMGetParam(function, @intCast(i));
            if (index >= prototype.parameters.items.len) {
                break;
            }

            llvm_core.LLVMSetValueName(arg, self.cStr(prototype.parameters.items[index].name.literal));
            index += 1;
        }

        const entry_block = llvm_core.LLVMAppendBasicBlockInContext(llvm_context, function, self.cStr("entry"));
        llvm_core.LLVMPositionBuilderAtEnd(builder, entry_block);

        try self.defer_calls_stack.append(ds.ScopedList(*DeferCall).init(self.allocator));
        try self.pushAllocaInstScope();

        for (0..args) |i| {
            const arg = llvm_core.LLVMGetParam(function, @intCast(i));
            const arg_name = llvm_core.LLVMGetValueName(arg);
            const alloca_inst = try self.createEntryBlockAlloca(function, std.mem.span(arg_name), llvm_core.LLVMTypeOf(arg));
            _ = self.alloca_inst_table.define(std.mem.span(arg_name), try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = alloca_inst }));
            _ = llvm_core.LLVMBuildStore(builder, arg, alloca_inst);
        }

        const body = node.body;
        _ = try body.accept(self.visitor);

        self.popAllocaInstScope();
        _ = self.defer_calls_stack.pop();

        _ = self.alloca_inst_table.define(mangled_name, try self.allocReturn(ds.Any, ds.Any{ .LLVMValue = function }));

        if (body.getAstNodeType() == .Block) {
            const statements = body.block_statement.statements;
            if (statements.items.len == 0 or statements.getLast().getAstNodeType() != .Return) {
                _ = llvm_core.LLVMBuildUnreachable(builder);
            }
        }
        self.debugModule();
        _ = llvm_analysis.LLVMVerifyFunction(function, .LLVMAbortProcessAction);
        // _ = llvm_analysis.LLVMVerifyFunction(function, .LLVMPrintMessageAction);
        self.has_return_statement = false;
        self.is_on_global_scope = true;
        llvm_core.LLVMPositionBuilderAtEnd(builder, previous_insert_block);

        self.generic_types.clearRetainingCapacity();
        return function;
    }

    fn resolveConstantExpression(self: *Self, value: ?*ast.Expression) !llvm_types.LLVMValueRef {
        log("Resolving constant expression", .{});
        if (value == null) {
            const field_type = value.?.getTypeNode().?;
            return llvm_core.LLVMConstNull(try self.llvmTypeFromLangType(field_type));
        }

        if (value.?.getAstNodeType() == .Index) {
            const index_expression = value.?.index_expression;
            return try self.resolveConstantIndexExpression(&index_expression);
        }

        if (value.?.getAstNodeType() == .IfExpression) {
            const if_expression = value.?.if_expression;
            return try self.resolveConstantIfExpression(&if_expression);
        }

        const llvm_value = try self.llvmResolveValue(try value.?.accept(self.visitor));
        return llvm_value;
    }

    fn resolveConstantIndexExpression(self: *Self, expression: *const ast.IndexExpression) !llvm_types.LLVMValueRef {
        log("Resolving constant index expression", .{});
        const llvm_array = try self.llvmResolveValue(try expression.value.accept(self.visitor));
        const index_value = try expression.index.accept(self.visitor);
        const constants_index = try self.llvmNodeValue(index_value);

        if (llvm_core.LLVMIsAGlobalVariable(llvm_array) != null) {
            const initializer = llvm_core.LLVMGetInitializer(llvm_array);
            if (llvm_core.LLVMIsAConstantDataArray(initializer) != null) {
                return llvm_core.LLVMGetElementAsConstant(initializer, @intCast(llvm_core.LLVMConstIntGetZExtValue(constants_index)));
            }

            if (llvm_core.LLVMIsAConstantArray(initializer) != null) {
                return llvm_core.LLVMGetElementAsConstant(initializer, @intCast(llvm_core.LLVMConstIntGetZExtValue(constants_index)));
                // return llvm_core.LLVMGetAggregateElement(initializer, @intCast(llvm_core.LLVMConstIntGetZExtValue(constants_index)));
            }

            if (llvm_core.LLVMIsAConstant(initializer) != null) {
                return llvm_core.LLVMGetElementAsConstant(initializer, @intCast(llvm_core.LLVMConstIntGetZExtValue(constants_index)));
                // return llvm_core.LLVMGetAggregateElement(initializer, @intCast(llvm_core.LLVMConstIntGetZExtValue(constants_index)));
            }
        }

        if (llvm_core.LLVMIsAConstantDataArray(llvm_array) != null) {
            return llvm_core.LLVMGetElementAsConstant(llvm_array, @intCast(llvm_core.LLVMConstIntGetZExtValue(constants_index)));
        }

        if (llvm_core.LLVMIsAConstantArray(llvm_array) != null) {
            const idx = llvm_core.LLVMConstIntGetZExtValue(constants_index);
            return llvm_core.LLVMGetOperand(llvm_array, @intCast(idx));
        }

        if (llvm_core.LLVMIsAConstant(llvm_array) != null) {
            return llvm_core.LLVMGetElementAsConstant(llvm_array, @intCast(llvm_core.LLVMConstIntGetZExtValue(constants_index)));
            // return llvm_core.LLVMGetAggregateElement(llvm_array, @intCast(llvm_core.LLVMConstIntGetZExtValue(constants_index)));
        }

        self.internalCompilerError("Invalid index expression");
        unreachable;
    }

    fn resolveConstantIfExpression(self: *Self, expression: *const ast.IfExpression) !llvm_types.LLVMValueRef {
        log("Resolving constant if expression", .{});
        const count = expression.tokens.items.len;
        for (0..count) |i| {
            const condition = try self.llvmResolveValue(try expression.conditions.items[i].accept(self.visitor));
            // isOneValue
            if (llvm_core.LLVMIsAConstantInt(condition) != null and llvm_core.LLVMIsAConstant(condition) != null and llvm_core.LLVMConstIntGetSExtValue(condition) == 1) {
                return try self.llvmResolveValue(try expression.values.items[i].accept(self.visitor));
            }
        }
        return null;
    }

    fn resolveConstantSwitchExpression(self: *Self, expression: *ast.SwitchExpression) !llvm_types.LLVMValueRef {
        log("Resolving constant switch expression", .{});
        const op = expression.op;
        const constant_argument = try self.llvmResolveValue(try expression.argument.accept(self.visitor));
        const switch_cases = expression.switch_cases;
        const cases_size = switch_cases.items.len;

        for (0..cases_size) |i| {
            const switch_case = switch_cases.items[i];
            const constant_case = try self.llvmResolveValue(try switch_case.accept(self.visitor));
            if (op == .EqualEqual and llvm_core.LLVMConstIntGetSExtValue(constant_argument) == llvm_core.LLVMConstIntGetSExtValue(constant_case)) {
                return try self.llvmResolveValue(try expression.switch_case_values.items[i].accept(self.visitor));
            }

            if (op == .BangEqual and llvm_core.LLVMConstIntGetSExtValue(constant_argument) != llvm_core.LLVMConstIntGetSExtValue(constant_case)) {
                return try self.llvmResolveValue(try expression.switch_case_values.items[i].accept(self.visitor));
            }

            if (op == .Greater and llvm_core.LLVMConstIntGetSExtValue(constant_argument) > llvm_core.LLVMConstIntGetSExtValue(constant_case)) {
                return try self.llvmResolveValue(try expression.switch_case_values.items[i].accept(self.visitor));
            }

            if (op == .GreaterEqual and llvm_core.LLVMConstIntGetSExtValue(constant_argument) >= llvm_core.LLVMConstIntGetSExtValue(constant_case)) {
                return try self.llvmResolveValue(try expression.switch_case_values.items[i].accept(self.visitor));
            }

            if (op == .Smaller and llvm_core.LLVMConstIntGetSExtValue(constant_argument) < llvm_core.LLVMConstIntGetSExtValue(constant_case)) {
                return try self.llvmResolveValue(try expression.switch_case_values.items[i].accept(self.visitor));
            }

            if (op == .SmallerEqual and llvm_core.LLVMConstIntGetSExtValue(constant_argument) <= llvm_core.LLVMConstIntGetSExtValue(constant_case)) {
                return try self.llvmResolveValue(try expression.switch_case_values.items[i].accept(self.visitor));
            }
        }
        return try self.llvmResolveValue(try expression.default_value.?.accept(self.visitor));
    }

    fn resolveConstantStringExpression(self: *Self, literal: []const u8) !*ds.Any {
        log("Resolving constant string expression", .{});
        if (self.constants_string_pool.contains(literal)) {
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = self.constants_string_pool.get(literal).? });
        }

        if (literal.len == 0) {
            const str = llvm_core.LLVMBuildGlobalStringPtr(builder, self.cStr(""), self.cStr("empty_string"));
            try self.constants_string_pool.put(literal, str);
            return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = str });
        }

        const size = literal.len;
        const length = size + 1;
        var characters = std.ArrayList(llvm_types.LLVMValueRef).init(self.allocator);
        try characters.resize(length);

        for (0..size) |i| {
            characters.items[i] = llvm_core.LLVMConstInt(llvm_int8_type, literal[i], 0);
        }
        characters.items[size] = llvm_core.LLVMConstInt(llvm_int8_type, 0, 0);
        const array_type = llvm_core.LLVMArrayType(llvm_int8_type, @intCast(length));
        const init_ = llvm_core.LLVMConstArray(array_type, @ptrCast(characters.items), @intCast(length));
        const init_type = llvm_core.LLVMTypeOf(init_);
        const variable = llvm_core.LLVMAddGlobal(self.llvm_module, init_type, self.cStr(literal));
        llvm_core.LLVMSetInitializer(variable, init_);
        llvm_core.LLVMSetGlobalConstant(variable, 1);
        llvm_core.LLVMSetLinkage(variable, .LLVMExternalLinkage);

        const string = llvm_core.LLVMConstBitCast(variable, llvm_int8_ptr_type);
        try self.constants_string_pool.put(literal, string);
        return self.allocReturn(ds.Any, ds.Any{ .LLVMValue = string });
    }

    fn resolveGenericStruct(self: *Self, generic: *const types.GenericStructType) !llvm_types.LLVMTypeRef {
        log("Resolving generic struct", .{});
        const struct_type = generic.struct_type;
        const struct_name = struct_type.name;
        const mangled_name = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ struct_name, try types.mangleTypes(self.allocator, generic.parameters.items) });
        if (self.structures_types_map.contains(mangled_name)) {
            return self.structures_types_map.get(mangled_name).?;
        }

        const struct_llvm_type = llvm_core.LLVMStructCreateNamed(llvm_context, self.cStr(mangled_name));

        const fields = struct_type.field_types.items;
        var struct_fields = std.ArrayList(llvm_types.LLVMTypeRef).init(self.allocator);

        for (fields) |field| {
            if (field.typeKind() == .Pointer) {
                const pointer = field.Pointer;
                if (pointer.base_type.typeKind() == .Struct) {
                    const struct_ty = pointer.base_type.Struct;
                    if (std.mem.eql(u8, struct_ty.name, struct_name)) {
                        try struct_fields.append(llvm_core.LLVMPointerType(struct_llvm_type, 0));
                        continue;
                    }
                }
            }

            if (field.typeKind() == .StaticArray) {
                const array = field.StaticArray;
                if (array.element_type.?.typeKind() == .Pointer) {
                    const pointer = array.element_type.?.Pointer;
                    if (pointer.base_type.typeKind() == .Struct) {
                        const struct_ty = pointer.base_type.Struct;
                        if (std.mem.eql(u8, struct_ty.name, struct_name)) {
                            const struct_ptr_ty = llvm_core.LLVMPointerType(struct_llvm_type, 0);
                            const array_ty = llvm_core.LLVMArrayType(struct_ptr_ty, @intCast(array.size));
                            try struct_fields.append(array_ty);
                            continue;
                        }
                    }
                }
            }

            if (field.typeKind() == .GenericParameter) {
                const generic_type = field.GenericParameter;
                const position = ds.indexOf(struct_type.generic_parameters.items, generic_type.name).?;
                try struct_fields.append(try self.llvmTypeFromLangType(generic.parameters.items[position]));
                continue;
            }

            try struct_fields.append(try self.llvmTypeFromLangType(field));
        }

        llvm_core.LLVMStructSetBody(struct_llvm_type, @ptrCast(struct_fields.items), @intCast(struct_fields.items.len), @intFromBool(struct_type.is_packed));
        try self.structures_types_map.put(mangled_name, struct_llvm_type);
        return struct_llvm_type;
    }

    fn createEntryBlockAlloca(self: *Self, function: llvm_types.LLVMValueRef, var_name: []const u8, type_: llvm_types.LLVMTypeRef) !llvm_types.LLVMValueRef {
        log("Creating entry block alloca", .{});
        const builder_object = llvm_core.LLVMCreateBuilder();
        const entry_block = llvm_core.LLVMGetEntryBasicBlock(function);
        llvm_core.LLVMPositionBuilder(builder_object, entry_block, llvm_core.LLVMGetFirstInstruction(entry_block));

        const alloca_inst = llvm_core.LLVMBuildAlloca(builder_object, type_, self.cStr(var_name));
        llvm_core.LLVMDisposeBuilder(builder_object);
        return alloca_inst;
    }

    fn lookupFunction(self: *Self, name: []const u8) !?llvm_types.LLVMValueRef {
        log("Looking up function", .{});
        if (llvm_core.LLVMGetNamedFunction(self.llvm_module, self.cStr(name)) != null) {
            return llvm_core.LLVMGetNamedFunction(self.llvm_module, self.cStr(name));
        }

        for (self.functions_table.keys()) |key| {
            log("Table: {s}", .{key});
        }

        for (self.function_declarations.keys()) |key| {
            log("Decl: {s}", .{key});
        }

        if (self.functions_table.contains(name)) {
            const function_prototype = self.functions_table.get(name).?;
            return (try function_prototype.accept(self.visitor)).LLVMValue;
        }

        return self.llvm_functions.get(name);
    }

    fn isLambdaFunctionName(self: *Self, name: []const u8) !bool {
        _ = self;
        log("Checking if is lambda function name", .{});
        if (name.len < 7) {
            return false;
        }
        return std.mem.eql(u8, name[0..7], "_lambda");
    }

    fn isGlobalBlock(self: *Self) bool {
        log("Checking if is global block", .{});
        return self.is_on_global_scope;
    }

    fn executeDeferCall(self: *Self, defer_call: *DeferCall) void {
        log("Executing defer call", .{});
        _ = switch (defer_call.*) {
            .FunctionCall => |fun_call| {
                const fun_name = llvm_core.LLVMGetValueName(fun_call.function);
                const fun_type = self.function_types_map.get(std.mem.span(fun_name)).?;
                _ = llvm_core.LLVMBuildCall2(builder, fun_type, fun_call.function, @ptrCast(fun_call.arguments.items), @intCast(fun_call.arguments.items.len), "");
            },
            .FunctionPtrCall => |fun_ptr| llvm_core.LLVMBuildCall2(builder, fun_ptr.function_type, fun_ptr.callee, @ptrCast(fun_ptr.arguments.items), @intCast(fun_ptr.arguments.items.len), ""),
        };
    }

    fn executeScopeDeferCalls(self: *Self) void {
        log("Executing scope defer calls", .{});
        const defer_calls = self.defer_calls_stack.getLast().getScopeElements2();
        for (defer_calls) |defer_call| {
            self.executeDeferCall(defer_call);
        }
    }

    fn executeAllDeferCalls(self: *Self) void {
        log("Executing all defer calls", .{});
        const current_defer_stack = self.defer_calls_stack.getLast();
        const size = current_defer_stack.size();
        log("Defer stack size {d}", .{size});
        var i: i64 = @intCast(size - 1);
        while (i >= 0) : (i -= 1) {
            const defer_calls = current_defer_stack.getScopeElements(@intCast(i));
            for (defer_calls) |defer_call| {
                self.executeDeferCall(defer_call);
            }
        }
    }

    fn pushAllocaInstScope(self: *Self) !void {
        log("Pushing alloca inst scope", .{});
        try self.alloca_inst_table.pushNewScope();
    }

    fn popAllocaInstScope(self: *Self) void {
        log("Popping alloca inst scope", .{});
        self.alloca_inst_table.popCurrentScope();
    }

    fn internalCompilerError(self: *Self, message: []const u8) void {
        _ = self;
        std.log.err("Internal compiler error: {s}", .{message});
        std.process.exit(1);
    }

    fn cStr(self: *Self, slice: []const u8) [*:0]const u8 {
        return self.allocator.dupeZ(u8, slice) catch unreachable;
    }

    fn dereferencesLLVMPointer(pointer: llvm_types.LLVMValueRef, pointer_type: PointerType) llvm_types.LLVMValueRef {
        log("Dereferencing LLVM pointer", .{});
        _ = pointer_type;
        // const ptr_type = switch (pointer_type) {
        //     .Alloca => llvm_core.LLVMGetAllocatedType(pointer),
        //     .Load => llvm_core.LLVMTypeOf(pointer),
        //     .GEP => llvm_core.LLVMGetElementType(llvm_core.LLVMGetGEPSourceElementType(pointer)),
        // };
        const ptr_type = llvm_core.LLVMGetElementType(llvm_core.LLVMTypeOf(pointer));
        return llvm_core.LLVMBuildLoad2(builder, ptr_type, pointer, @ptrCast(""));
    }

    fn isFloatingPointTy(type_: llvm_types.LLVMTypeRef) bool {
        const type_kind = llvm_core.LLVMGetTypeKind(type_);
        return type_kind == .LLVMFloatTypeKind or type_kind == .LLVMDoubleTypeKind;
    }

    fn isArrayTy(type_: llvm_types.LLVMTypeRef) bool {
        return llvm_core.LLVMGetTypeKind(type_) == .LLVMArrayTypeKind;
    }

    fn isVectorTy(type_: llvm_types.LLVMTypeRef) bool {
        return llvm_core.LLVMGetTypeKind(type_) == .LLVMVectorTypeKind;
    }

    fn debugModule(self: *Self) void {
        log("Debugging module", .{});
        llvm_core.LLVMDumpModule(self.llvm_module);
    }
};

pub const DeferCall = union(enum) {
    FunctionCall: DeferFunctionCall,
    FunctionPtrCall: DeferFunctionPtrCall,
};

pub const DeferFunctionCall = struct {
    function: llvm_types.LLVMValueRef,
    arguments: std.ArrayList(llvm_types.LLVMValueRef),

    pub fn init(function: llvm_types.LLVMValueRef, arguments: std.ArrayList(llvm_types.LLVMValueRef)) DeferFunctionCall {
        return DeferFunctionCall{
            .function = function,
            .arguments = arguments,
        };
    }
};

pub const DeferFunctionPtrCall = struct {
    function_type: llvm_types.LLVMTypeRef,
    callee: llvm_types.LLVMValueRef,
    arguments: std.ArrayList(llvm_types.LLVMValueRef),

    pub fn init(function_type: llvm_types.LLVMTypeRef, callee: llvm_types.LLVMValueRef, arguments: std.ArrayList(llvm_types.LLVMValueRef)) DeferFunctionPtrCall {
        return DeferFunctionPtrCall{
            .function_type = function_type,
            .callee = callee,
            .arguments = arguments,
        };
    }
};

fn debugV(val: llvm_types.LLVMValueRef) void {
    const str = llvm_core.LLVMPrintValueToString(val);
    std.log.info("Value : {s}", .{str});
    llvm_core.LLVMDisposeMessage(str);
}

fn debugT(val: llvm_types.LLVMTypeRef) void {
    const str = llvm_core.LLVMPrintTypeToString(val);
    std.log.info("Type : {s}", .{str});
    llvm_core.LLVMDisposeMessage(str);
}
