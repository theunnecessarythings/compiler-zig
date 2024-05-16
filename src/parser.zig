const std = @import("std");
const types = @import("types.zig");
const Type = types.Type;
const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;
const Tokenizer = tokenizer.Tokenizer;
const TokenKind = tokenizer.TokenKind;
const TokenSpan = tokenizer.TokenSpan;
const ast = @import("ast.zig");
const diagnostics = @import("diagnostics.zig");
const DiagnosticEngine = diagnostics.DiagnosticEngine;
const DignosticLevel = diagnostics.DiagnosticLevel;
const SourceManager = diagnostics.SourceManager;
const ds = @import("data_structures.zig");
const AliasTable = ds.AliasTable;
const ScopedMap = ds.ScopedMap;
const Error = diagnostics.Error;
const log = diagnostics.log;

pub const AstNodeScope = enum {
    Global,
    Function,
    Condition,
};

pub const FunctionKind = enum {
    Normal,
    Prefix,
    Infix,
    Postfix,
};

pub const LIBRARIES_PREFIX = "lib/";
pub const LANGUAGE_EXTENSION = ".la";

pub const CompilerOptions = struct {
    allocator: std.mem.Allocator,
    output_file_name: []const u8 = "output",
    should_report_warns: bool = false,
    convert_warns_to_errors: bool = false,
    use_cpu_features: bool = true,
    linker_extra_flags: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) CompilerOptions {
        return CompilerOptions{
            .allocator = allocator,
            .linker_extra_flags = std.ArrayList([]const u8).init(allocator),
        };
    }
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    options: CompilerOptions,
    diagnostics: DiagnosticEngine,
    source_manager: *SourceManager,
    type_alias_table: AliasTable,
    functions: std.StringArrayHashMap(FunctionKind),
    structures: std.StringArrayHashMap(*types.StructType),
    enumerations: std.StringArrayHashMap(*types.EnumType),
    constants_table_map: ScopedMap(*ast.Expression),

    pub fn init(allocator: std.mem.Allocator, source_manager: *SourceManager) !Context {
        var constants_table_map = ScopedMap(*ast.Expression).init(allocator);
        _ = try constants_table_map.pushNewScope();
        return Context{
            .allocator = allocator,
            .options = CompilerOptions.init(allocator),
            .diagnostics = try DiagnosticEngine.init(allocator, source_manager),
            .source_manager = source_manager,
            .type_alias_table = try AliasTable.init(allocator),
            .functions = std.StringArrayHashMap(FunctionKind).init(allocator),
            .structures = std.StringArrayHashMap(*types.StructType).init(allocator),
            .enumerations = std.StringArrayHashMap(*types.EnumType).init(allocator),
            .constants_table_map = constants_table_map,
        };
    }
};

fn primitiveTypes(type_: []const u8) ?*Type {
    if (std.mem.eql(u8, "int1", type_)) {
        return @constCast(&Type.I1_TYPE);
    } else if (std.mem.eql(u8, "bool", type_)) {
        return @constCast(&Type.I1_TYPE);
    } else if (std.mem.eql(u8, "chr", type_)) {
        return @constCast(&Type.I8_TYPE);
    } else if (std.mem.eql(u8, "uchr", type_)) {
        return @constCast(&Type.U8_TYPE);
    } else if (std.mem.eql(u8, "int8", type_)) {
        return @constCast(&Type.I8_TYPE);
    } else if (std.mem.eql(u8, "int16", type_)) {
        return @constCast(&Type.I16_TYPE);
    } else if (std.mem.eql(u8, "int32", type_)) {
        return @constCast(&Type.I32_TYPE);
    } else if (std.mem.eql(u8, "int64", type_)) {
        return @constCast(&Type.I64_TYPE);
    } else if (std.mem.eql(u8, "uint8", type_)) {
        return @constCast(&Type.U8_TYPE);
    } else if (std.mem.eql(u8, "uint16", type_)) {
        return @constCast(&Type.U16_TYPE);
    } else if (std.mem.eql(u8, "uint32", type_)) {
        return @constCast(&Type.U32_TYPE);
    } else if (std.mem.eql(u8, "uint64", type_)) {
        return @constCast(&Type.U64_TYPE);
    } else if (std.mem.eql(u8, "float32", type_)) {
        return @constCast(&Type.F32_TYPE);
    } else if (std.mem.eql(u8, "float64", type_)) {
        return @constCast(&Type.F64_TYPE);
    } else if (std.mem.eql(u8, "void", type_)) {
        return @constCast(&Type.VOID_TYPE);
    } else {
        return null;
    }
}

pub const Parser = struct {
    allocator: std.mem.Allocator,
    file_parent_path: []const u8,
    context: *Context,
    tokenizer: *Tokenizer,
    previous_token: ?Token,
    current_token: ?Token,
    next_token: ?Token,
    generic_parameter_names: std.StringArrayHashMap(void),
    current_ast_scope: AstNodeScope = .Global,
    loop_levels_stack: std.ArrayList(i32),
    current_struct_name: []const u8,
    current_struct_unknown_fields: u32 = 0,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, context: *Context, tokenizer_: *Tokenizer) !Parser {
        const current_source_file_id = tokenizer_.getSourceFileId();
        const file_path = context.source_manager.resolveSourcePath(current_source_file_id).?;
        var file_parent_path = std.fs.path.dirname(file_path).?;

        const file_separator = std.fs.path.sep_str;
        if (file_parent_path[file_parent_path.len - 1] != file_separator[0]) {
            file_parent_path = try std.mem.concat(allocator, u8, &[_][]const u8{ file_parent_path, file_separator });
        }

        log("File parent path: {s}", .{file_parent_path}, .{ .module = .Parser });

        var loop_levels_stack = std.ArrayList(i32).init(allocator);
        _ = try loop_levels_stack.append(0);
        return Parser{
            .allocator = allocator,
            .file_parent_path = file_parent_path,
            .context = context,
            .tokenizer = tokenizer_,
            .previous_token = null,
            .current_token = null,
            .next_token = null,
            .generic_parameter_names = std.StringArrayHashMap(void).init(allocator),
            .current_ast_scope = AstNodeScope.Global,
            .loop_levels_stack = loop_levels_stack,
            .current_struct_name = "",
        };
    }

    pub fn parseCompilationUnit(self: *Self) Error!*ast.CompilationUnit {
        log("Parsing compilation unit", .{}, .{ .module = .Parser });
        var tree_nodes = std.ArrayList(*ast.Statement).init(self.allocator);
        _ = try self.advancedToken();
        _ = try self.advancedToken();

        while (self.isSourceAvailable()) {
            if (self.isCurrentKind(.Import)) {
                const module_tree_node = try self.parseImportDeclaration();
                _ = try tree_nodes.appendSlice(module_tree_node.items);
                continue;
            }

            if (self.isCurrentKind(.Load)) {
                const module_tree_node = try self.parseLoadDeclaration();
                _ = try tree_nodes.appendSlice(module_tree_node.items);
                continue;
            }

            if (self.isCurrentKind(.Type)) {
                try self.parseTypeAliasDeclaration();
                continue;
            }

            _ = try tree_nodes.append(try self.parseDeclarationStatement());
        }
        return self.allocReturn(ast.CompilationUnit, ast.CompilationUnit.init(tree_nodes));
    }

    fn allocReturn(self: *Self, comptime T: type, value: T) Error!*T {
        const ptr = try self.allocator.create(T);
        ptr.* = value;
        return ptr;
    }

    fn parseImportDeclaration(self: *Self) !std.ArrayList(*ast.Statement) {
        log("Parsing import declaration", .{}, .{ .module = .Parser });
        _ = try self.advancedToken();
        if (self.isCurrentKind(.OpenBrace)) {
            _ = try self.advancedToken();
            var tree_nodes = std.ArrayList(*ast.Statement).init(self.allocator);
            while (self.isSourceAvailable() and !self.isCurrentKind(.CloseBrace)) {
                const library_name = (try self.consumeKind(.String, "Expect string as library name after import statement")).?;
                const library_path = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ LIBRARIES_PREFIX, library_name.literal, LANGUAGE_EXTENSION });

                if (self.context.source_manager.isPathRegistered(library_path)) {
                    continue;
                }
                std.fs.cwd().access(library_path, .{}) catch {
                    try self.context.diagnostics.reportError(
                        library_name.position,
                        try std.fmt.allocPrint(self.allocator, "No standard library with name: '{s}'", .{library_name.literal}),
                    );
                    return Error.ParsingError;
                };

                const nodes = try self.parseSingleSourceFile(library_path);
                _ = try tree_nodes.appendSlice(nodes.items);
            }
            try self.assertKind(.CloseBrace, "Expect '}' after import statement");
            try self.checkUnnecessarySemicolonWarning();
            return tree_nodes;
        }

        const library_name = (try self.consumeKind(.String, "Expect string as library name after import statement")).?;
        try self.checkUnnecessarySemicolonWarning();

        const library_path = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ LIBRARIES_PREFIX, library_name.literal, LANGUAGE_EXTENSION });
        if (self.context.source_manager.isPathRegistered(library_path)) {
            return std.ArrayList(*ast.Statement).init(self.allocator);
        }

        log("Library path: {s}", .{library_path}, .{ .module = .Parser });
        std.fs.cwd().access(library_path, .{}) catch {
            try self.context.diagnostics.reportError(
                library_name.position,
                try std.fmt.allocPrint(self.allocator, "No standrad library with name: '{s}'", .{library_name.literal}),
            );
            return Error.ParsingError;
        };

        return self.parseSingleSourceFile(library_path);
    }

    fn parseLoadDeclaration(self: *Self) !std.ArrayList(*ast.Statement) {
        log("Parsing load declaration", .{}, .{ .module = .Parser });
        _ = try self.advancedToken();
        if (self.isCurrentKind(.OpenBrace)) {
            _ = try self.advancedToken();
            var tree_nodes = std.ArrayList(*ast.Statement).init(self.allocator);
            while (self.isSourceAvailable() and !self.isCurrentKind(.CloseBrace)) {
                const library_name = (try self.consumeKind(.String, "Expect string as library name after load statement")).?;

                const library_path = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ self.file_parent_path, library_name.literal, LANGUAGE_EXTENSION });

                if (self.context.source_manager.isPathRegistered(library_path)) {
                    continue;
                }

                std.fs.accessAbsolute(library_path, .{}) catch {
                    try self.context.diagnostics.reportError(
                        library_name.position,
                        try std.fmt.allocPrint(self.allocator, "Library not found: '{s}'", .{library_name.literal}),
                    );
                    return Error.ParsingError;
                };

                const nodes = try self.parseSingleSourceFile(library_path);
                try tree_nodes.appendSlice(nodes.items);
            }
            try self.assertKind(.CloseBrace, "Expect '}' after load statement");
            try self.checkUnnecessarySemicolonWarning();
            return tree_nodes;
        }

        const library_name = (try self.consumeKind(.String, "Expect string as library name after load statement")).?;
        try self.checkUnnecessarySemicolonWarning();

        const library_path = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ self.file_parent_path, library_name.literal, LANGUAGE_EXTENSION });

        if (self.context.source_manager.isPathRegistered(library_path)) {
            return std.ArrayList(*ast.Statement).init(self.allocator);
        }

        std.fs.accessAbsolute(library_path, .{}) catch {
            try self.context.diagnostics.reportError(
                library_name.position,
                try std.fmt.allocPrint(self.allocator, "Library not found: '{s}'", .{library_name.literal}),
            );
            return Error.ParsingError;
        };

        return self.parseSingleSourceFile(library_path);
    }

    fn parseCompiletimeConstantsDeclaration(self: *Self) Error!*ast.Statement {
        log("Parsing compiletime constants declaration", .{}, .{ .module = .Parser });
        _ = try self.advancedToken();
        const name = (try self.consumeKind(.Identifier, "Expect const declaraion name")).?;
        try self.assertKind(.Equal, "Expect = after const variable name");
        const expression = try self.parseExpression();
        try self.checkCompiletimeconstantsExpression(expression, name.position);
        try self.assertKind(.Semicolon, "Expect ; after const declaraion");
        _ = self.context.constants_table_map.define(name.literal, expression);
        return self.allocReturn(ast.Statement, ast.Statement{ .const_declaration = ast.ConstDeclaration.init(name, expression) });
    }

    fn parseTypeAliasDeclaration(self: *Self) !void {
        log("Parsing type alias declaration", .{}, .{ .module = .Parser });
        const type_token = (try self.consumeKind(.Type, "Expect type keyword")).?;
        _ = type_token;

        const alias_token = (try self.consumeKind(.Identifier, "Expect identifier for type alias")).?;

        if (self.context.type_alias_table.contains(alias_token.literal)) {
            try self.context.diagnostics.reportError(alias_token.position, try std.fmt.allocPrint(self.allocator, "There already a type with name '{s}'", .{alias_token.literal}));
            return Error.ParsingError;
        }

        try self.assertKind(.Equal, "Expect = after alias name");
        const actual_type = try self.parseType();

        if (types.isEnumType(actual_type)) {
            try self.context.diagnostics.reportError(alias_token.position, "You can't use type alias for enum name");
            return Error.ParsingError;
        }

        if (types.isEnumElementType(actual_type)) {
            try self.context.diagnostics.reportError(alias_token.position, "You can't use type alias for enum element");
            return Error.ParsingError;
        }

        try self.assertKind(.Semicolon, "Expect ; after actual type");
        try self.context.type_alias_table.defineAlias(alias_token.literal, actual_type);
    }

    fn parseSingleSourceFile(self: *Self, path: []const u8) Error!std.ArrayList(*ast.Statement) {
        log("Parsing single source file", .{}, .{ .module = .Parser });
        const file_name = path;
        const file = std.fs.cwd().openFile(path, .{}) catch return Error.ParsingError;
        defer file.close();
        const source_content = try file.readToEndAlloc(self.allocator, comptime std.math.maxInt(usize));

        const file_id = try self.context.source_manager.registerSourcePath(file_name);
        var tokenizer_ = Tokenizer.init(self.allocator, source_content, file_id);
        var parser = try Parser.init(self.allocator, self.context, &tokenizer_);
        const compilation_unit = try parser.parseCompilationUnit();
        if (self.context.diagnostics.levelCount(.Error) > 0) {
            return Error.ParsingError;
        }
        return compilation_unit.tree_nodes;
    }

    fn parseDeclarationStatement(self: *Self) Error!*ast.Statement {
        log("Parsing declaration statement", .{}, .{ .module = .Parser });
        return switch (self.peekCurrent().kind) {
            .Fun => {
                return try self.parseFunctionDeclaration(FunctionKind.Normal);
            },
            .Operator => {
                return try self.parseOperatorFunctionDeclaration(FunctionKind.Normal);
            },
            .Var => {
                if (self.isNextKind(.OpenParen)) {
                    return try self.parseDestructuringFieldDeclaration(true);
                }
                return try self.parseFieldDeclaration(true);
            },
            .Const => {
                return try self.parseCompiletimeConstantsDeclaration();
            },
            .Struct => {
                return try self.parseStructureDeclaration(false, false);
            },
            .Enum => {
                return try self.parseEnumDeclaration();
            },
            .At => {
                return try self.parseDeclarationsDirective();
            },
            else => {
                try self.context.diagnostics.reportError(self.peekCurrent().position, "Invalid top level declaration statement");
                return Error.ParsingError;
            },
        };
    }

    fn parseStatement(self: *Self) Error!*ast.Statement {
        log("Parsing statement", .{}, .{ .module = .Parser });
        return switch (self.current_token.?.kind) {
            .Var => {
                if (self.isNextKind(.OpenParen)) {
                    return self.parseDestructuringFieldDeclaration(false);
                }
                return self.parseFieldDeclaration(false);
            },
            .Const => {
                return self.parseCompiletimeConstantsDeclaration();
            },
            .If => {
                return self.parseIfStatement();
            },
            .For => {
                return self.parseForStatement();
            },
            .While => {
                return self.parseWhileStatement();
            },
            .Switch => {
                return self.parseSwitchastatement();
            },
            .Return => {
                return self.parseReturnStatement();
            },
            .Defer => {
                return self.parseDeferStatement();
            },
            .Break => {
                return self.parseBreakStatement();
            },
            .Continue => {
                return self.parseContinueStatement();
            },
            .OpenBrace => {
                return self.parseBlockStatement();
            },
            .At => {
                return self.parseStatementsDirective();
            },
            else => {
                return self.parseExpressionStatement();
            },
        };
    }

    fn parseFieldDeclaration(self: *Self, is_global: bool) Error!*ast.Statement {
        log("Parsing field declaration", .{}, .{ .module = .Parser });
        _ = try self.advancedToken();
        const name = (try self.consumeKind(.Identifier, "Expect identifier as variable name")).?;

        if (self.isCurrentKind(.Colon)) {
            _ = try self.advancedToken();
            const type_ = try self.parseType();
            var initializer: ?*ast.Expression = null;
            if (self.isCurrentKind(.Equal)) {
                _ = try self.advancedToken();
                if (self.isCurrentKind(.Undefined)) {
                    const keyword = try self.peekAndAdvanceToken();
                    initializer = try self.allocReturn(ast.Expression, ast.Expression{ .undefined_expression = ast.UndefinedExpression.init(keyword) });
                } else {
                    initializer = try self.parseExpression();
                }
            }
            try self.assertKind(.Semicolon, "Expect semicolon after field declaration");
            return self.allocReturn(ast.Statement, ast.Statement{ .field_declaration = ast.FieldDeclaration.init(name, type_, initializer, is_global) });
        }

        try self.assertKind(.Equal, "Expect = or : after field declaraion name");
        const init_value = try self.parseExpression();
        try self.assertKind(.Semicolon, "Expect semicolon after field declaration");
        return self.allocReturn(ast.Statement, ast.Statement{ .field_declaration = ast.FieldDeclaration.init(name, @constCast(&Type.NONE_TYPE), init_value, is_global) });
    }

    fn parseDestructuringFieldDeclaration(self: *Self, is_global: bool) Error!*ast.Statement {
        log("Parsing destructuring field declaration", .{}, .{ .module = .Parser });
        try self.assertKind(.Var, "Expected var keyword");
        try self.assertKind(.OpenParen, "Expect ( after var keyword");

        var names = std.ArrayList(Token).init(self.allocator);
        var field_types = std.ArrayList(*Type).init(self.allocator);

        while (!self.isCurrentKind(.CloseParen)) {
            const name = (try self.consumeKind(.Identifier, "Expect identifier as variable name")).?;
            try names.append(name);

            if (self.isCurrentKind(.Colon)) {
                _ = try self.advancedToken();
                try field_types.append(try self.parseType());
            } else {
                try field_types.append(@constCast(&Type.NONE_TYPE));
            }

            if (self.isCurrentKind(.Comma)) {
                _ = try self.advancedToken();
            } else {
                break;
            }
        }

        try self.assertKind(.CloseParen, "Expect ) after var keyword");
        const equal_token = (try self.consumeKind(.Equal, "Expect = after var keyword")).?;
        const value = try self.parseExpression();
        try self.assertKind(.Semicolon, "Expect semicolon `;` after field declaration");
        return self.allocReturn(ast.Statement, ast.Statement{ .destructuring_declaration = ast.DestructuringDeclaration.init(names, field_types, value, equal_token, is_global) });
    }

    fn parseIntrinsicPrototype(self: *Self) Error!*ast.Statement {
        log("Parsing intrinsic prototype", .{}, .{ .module = .Parser });
        const intrinsic_keyword = (try self.consumeKind(.Identifier, "Expect intrinsic keyword")).?;
        _ = intrinsic_keyword;

        var intrinsic_name: ?[]const u8 = null;
        if (self.isCurrentKind(.OpenParen)) {
            _ = try self.advancedToken();
            const intrinsic_token = (try self.consumeKind(.String, "Expect intrinsic ntive name")).?;
            intrinsic_name = intrinsic_token.literal;
            if (!self.isValidIntrinsicName(intrinsic_token)) {
                try self.context.diagnostics.reportError(intrinsic_token.position, "Intrinsic name can't have space or be empty");
                return Error.ParsingError;
            }
            try self.assertKind(.CloseParen, "Expect ) after native intrinsic name");
        }

        try self.assertKind(.Fun, "Expect function keyword");
        const name = (try self.consumeKind(.Identifier, "Expect identifier as function name")).?;

        const is_generic_function = self.isCurrentKind(.Smaller);
        if (is_generic_function) {
            try self.context.diagnostics.reportError(name.position, "intrinsic function can't has generic parameter");
            return Error.ParsingError;
        }

        if (intrinsic_name == null) {
            intrinsic_name = name.literal;
        }

        var has_varargs = false;

        var varargs_type: ?*Type = null;
        var parameters = std.ArrayList(*ast.Parameter).init(self.allocator);
        if (self.isCurrentKind(.OpenParen)) {
            _ = try self.advancedToken();
            while (self.isSourceAvailable() and !self.isCurrentKind(.CloseParen)) {
                if (has_varargs) {
                    try self.context.diagnostics.reportError(self.previous_token.?.position, "Varargs must be the last parameter in the function");
                    return Error.ParsingError;
                }

                if (self.isCurrentKind(.Varargs)) {
                    _ = try self.advancedToken();
                    if (self.isCurrentKind(.Identifier) and std.mem.eql(u8, self.current_token.?.literal, "Any")) {
                        _ = try self.advancedToken();
                    } else {
                        varargs_type = try self.parseType();
                    }
                    has_varargs = true;
                    continue;
                }

                try parameters.append(try self.parseParameter());
                if (self.isCurrentKind(.Comma)) {
                    _ = try self.advancedToken();
                }
            }
            try self.assertKind(.CloseParen, "Expect ) after function parameters");
        }

        try self.context.functions.put(name.literal, .Normal);
        var return_type: *Type = undefined;
        if (self.isCurrentKind(.Semicolon) or self.isCurrentKind(.OpenBrace)) {
            return_type = @constCast(&Type.NONE_TYPE);
        } else {
            return_type = try self.parseType();
        }

        if (return_type.typeKind() == .StaticArray) {
            try self.context.diagnostics.reportError(name.position, try std.fmt.allocPrint(self.allocator, "Function cannot return array type '{any}'", .{return_type}));
            return Error.ParsingError;
        }

        try self.assertKind(.Semicolon, "Expect ; after external function declaration");

        return self.allocReturn(ast.Statement, ast.Statement{ .intrinsic_prototype = ast.IntrinsicPrototype.init(name, intrinsic_name.?, parameters, return_type, has_varargs, varargs_type) });
    }

    fn parseFunctionPrototype(self: *Self, kind: FunctionKind, is_external: bool) Error!*ast.Statement {
        log("Parsing function prototype", .{}, .{ .module = .Parser });
        if (is_external) {
            try self.assertKind(.Identifier, "Expect external keyword");
        }

        try self.assertKind(.Fun, "Expect function keyword");
        const name = (try self.consumeKind(.Identifier, "Expect identifier as function name")).?;

        var generics_parameters = std.ArrayList([]const u8).init(self.allocator);
        const is_generic_function = self.isCurrentKind(.Smaller);
        if (is_external and is_generic_function) {
            try self.context.diagnostics.reportError(name.position, "external function can't has generic parameter");
            return Error.ParsingError;
        }

        if (is_generic_function) {
            _ = try self.advancedToken();
            while (self.isSourceAvailable() and !self.isCurrentKind(.Greater)) {
                const parameter = (try self.consumeKind(.Identifier, "Expect parameter name")).?;
                try self.checkGenericParameterName(parameter);
                try generics_parameters.append(parameter.literal);
                if (self.isCurrentKind(.Comma)) {
                    _ = try self.advancedToken();
                } else {
                    break;
                }
            }

            try self.assertKind(.Greater, "Expect > after struct type parameters");
        }

        var has_varargs = false;
        var varargs_type: ?*Type = null;
        var parameters = std.ArrayList(*ast.Parameter).init(self.allocator);
        if (self.isCurrentKind(.OpenParen)) {
            _ = try self.advancedToken();
            while (self.isSourceAvailable() and !self.isCurrentKind(.CloseParen)) {
                if (has_varargs) {
                    try self.context.diagnostics.reportError(self.previous_token.?.position, "Varargs must be the last parameter in the function");
                    return Error.ParsingError;
                }

                if (self.isCurrentKind(.Varargs)) {
                    _ = try self.advancedToken();
                    if (self.isCurrentKind(.Identifier) and std.mem.eql(u8, self.current_token.?.literal, "Any")) {
                        _ = try self.advancedToken();
                    } else {
                        varargs_type = try self.parseType();
                    }
                    has_varargs = true;
                    continue;
                }

                try parameters.append(try self.parseParameter());
                if (self.isCurrentKind(.Comma)) {
                    _ = try self.advancedToken();
                } else {
                    break;
                }
            }
            try self.assertKind(.CloseParen, "Expect ) after function parameters");
        }

        const parameters_size: u32 = @intCast(parameters.items.len);
        try self.checkFunctionKindParametersCount(kind, parameters_size, name.position);

        try self.context.functions.put(try self.allocator.dupe(u8, name.literal), kind);

        var return_type: *Type = undefined;

        if (self.isCurrentKind(.Semicolon) or self.isCurrentKind(.OpenBrace)) {
            return_type = @constCast(&Type.VOID_TYPE);
        } else {
            return_type = try self.parseType();
        }

        if (is_external) {
            try self.assertKind(.Semicolon, "Expect ; after external function declaration");
        }
        if (std.mem.eql(u8, name.literal, "main")) {
            if (kind != .Normal) {
                try self.context.diagnostics.reportError(name.position, "main can't be prefix, infix or postfix function");
                return Error.ParsingError;
            }

            if (is_external) {
                try self.context.diagnostics.reportError(name.position, "main can't be external function");
                return Error.ParsingError;
            }

            if (!(types.isVoidType(return_type) or types.isInteger32Type(return_type) or types.isInteger64Type(return_type))) {
                try self.context.diagnostics.reportError(name.position, "main has invalid return type expect void, int32 or int64");
                return Error.ParsingError;
            }
        }

        return self.allocReturn(ast.Statement, ast.Statement{ .function_prototype = ast.FunctionPrototype.init(name, return_type, parameters, is_external, has_varargs, varargs_type, is_generic_function, generics_parameters) });
    }

    fn parseFunctionDeclaration(self: *Self, kind: FunctionKind) Error!*ast.Statement {
        log("Parsing function declaration", .{}, .{ .module = .Parser });
        const parent_node_scope = self.current_ast_scope;
        self.current_ast_scope = .Function;
        try self.context.constants_table_map.pushNewScope();

        const prototype = (try self.parseFunctionPrototype(kind, false)).function_prototype;
        const prototype_ = try self.allocReturn(ast.FunctionPrototype, prototype);

        if (self.isCurrentKind(.Equal)) {
            const equal_token = try self.peekAndAdvanceToken();
            const value = try self.parseExpression();
            const return_statement = try self.allocReturn(ast.Statement, ast.Statement{ .return_statement = ast.ReturnStatement.init(equal_token, value, true) });
            try self.assertKind(.Semicolon, "Expect ; after function value");
            self.current_ast_scope = parent_node_scope;
            self.context.constants_table_map.popCurrentScope();
            self.generic_parameter_names.clearRetainingCapacity();
            return self.allocReturn(ast.Statement, ast.Statement{ .function_declaration = ast.FunctionDeclaration.init(prototype_, return_statement) });
        }

        if (self.isCurrentKind(.OpenBrace)) {
            try self.loop_levels_stack.append(0);
            const block = try self.parseBlockStatement();
            var block_statement = block.block_statement;

            try self.checkUnnecessarySemicolonWarning();

            _ = self.loop_levels_stack.pop();
            const close_brace = self.peekPrevious();

            if (types.isVoidType(prototype.return_type.?) and (block_statement.statements.items.len == 0 or block_statement.statements.items[block_statement.statements.items.len - 1].getAstNodeType() != .Return)) {
                const void_return = try self.allocReturn(ast.Statement, ast.Statement{ .return_statement = ast.ReturnStatement.init(close_brace, null, false) });
                try block.block_statement.statements.append(void_return);
            }
            self.current_ast_scope = parent_node_scope;
            self.context.constants_table_map.popCurrentScope();
            self.generic_parameter_names.clearRetainingCapacity();
            return self.allocReturn(ast.Statement, ast.Statement{ .function_declaration = ast.FunctionDeclaration.init(prototype_, block) });
        }

        const posiiton = self.peekPrevious().position;
        try self.context.diagnostics.reportError(posiiton, "function declaration without a body: `{ <body> }` or `= <value>;`");
        return Error.ParsingError;
    }

    fn parseOperatorFunctionDeclaration(self: *Self, kind: FunctionKind) Error!*ast.Statement {
        log("Parsing operator function declaration", .{}, .{ .module = .Parser });
        const parent_node_scope = self.current_ast_scope;
        self.current_ast_scope = .Function;
        try self.context.constants_table_map.pushNewScope();

        const operator_keyword = try self.peekAndAdvanceToken();
        const position = operator_keyword.position;
        const operator_token = try self.parseOperatorFunctionOperator(kind);

        var parameters = std.ArrayList(*ast.Parameter).init(self.allocator);
        var parameters_types = std.ArrayList(*Type).init(self.allocator);
        if (self.isCurrentKind(.OpenParen)) {
            _ = try self.advancedToken();
            while (self.isSourceAvailable() and !self.isCurrentKind(.CloseParen)) {
                const parameter = try self.parseParameter();
                try parameters.append(parameter);
                try parameters_types.append(parameter.parameter_type);
                if (self.isCurrentKind(.Comma)) {
                    _ = try self.advancedToken();
                } else {
                    break;
                }
            }
            try self.assertKind(.CloseParen, "Expect ) after function parameters");
        }

        try self.checkFunctionKindParametersCount(.Normal, @intCast(parameters.items.len), position);

        const prefix = if (kind == .Prefix)
            "_prefix"
        else if (kind == .Postfix)
            "_postfix"
        else
            "";

        const mangled_name = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prefix, try types.mangleOperatorFunction(self.allocator, operator_token.kind, parameters_types.items) });
        const name = Token{ .kind = TokenKind.Identifier, .position = operator_token.position, .literal = mangled_name };

        var return_type: *Type = undefined;
        if (self.isCurrentKind(.Semicolon) or self.isCurrentKind(.OpenBrace)) {
            return_type = @constCast(&Type.NONE_TYPE);
        } else {
            return_type = try self.parseType();
        }

        const prototype = try self.allocReturn(ast.FunctionPrototype, ast.FunctionPrototype.init(name, return_type, parameters, false, false, null, false, std.ArrayList([]const u8).init(self.allocator)));

        if (self.isCurrentKind(.Equal)) {
            const equal_token = try self.peekAndAdvanceToken();
            const value = try self.parseExpression();
            const return_statement = try self.allocReturn(ast.Statement, ast.Statement{ .return_statement = ast.ReturnStatement.init(equal_token, value, true) });
            try self.assertKind(.Semicolon, "Expect ; after function value");
            self.current_ast_scope = parent_node_scope;
            self.context.constants_table_map.popCurrentScope();
            const declaration = try self.allocReturn(ast.FunctionDeclaration, ast.FunctionDeclaration.init(prototype, return_statement));
            return self.allocReturn(ast.Statement, ast.Statement{ .operator_function_declaration = ast.OperatorFunctionDeclaration.init(operator_token, declaration) });
        }

        if (self.isCurrentKind(.OpenBrace)) {
            try self.loop_levels_stack.append(0);
            const block = try self.parseBlockStatement();
            var block_statements = block.block_statement.statements;

            try self.checkUnnecessarySemicolonWarning();
            _ = self.loop_levels_stack.pop();
            const close_brace = self.peekPrevious();

            if (types.isVoidType(prototype.return_type.?) and (block_statements.items.len == 0 or block_statements.items[block_statements.items.len - 1].getAstNodeType() != .Return)) {
                const void_return = try self.allocReturn(ast.Statement, ast.Statement{ .return_statement = ast.ReturnStatement.init(close_brace, null, false) });
                try block_statements.append(void_return);
            }

            self.current_ast_scope = parent_node_scope;
            self.context.constants_table_map.popCurrentScope();
            self.generic_parameter_names.clearRetainingCapacity();
            const declaration = try self.allocReturn(ast.FunctionDeclaration, ast.FunctionDeclaration.init(prototype, block));
            return self.allocReturn(ast.Statement, ast.Statement{ .operator_function_declaration = ast.OperatorFunctionDeclaration.init(operator_token, declaration) });
        }

        const posiiton = self.peekPrevious().position;
        try self.context.diagnostics.reportError(posiiton, "operator function declaration without a body: `{ <body> }` or `= <value>;`");

        return Error.ParsingError;
    }

    fn parseOperatorFunctionOperator(self: *Self, kind: FunctionKind) !Token {
        log("Parsing Operator Function Operator", .{}, .{ .module = .Parser });
        var op = try self.peekAndAdvanceToken();
        if (self.isRightShiftOperator(self.peekPrevious(), self.peekCurrent())) {
            _ = try self.advancedToken();
            op.kind = .RightShift;
        }

        _ = tokenizer.overloadingOperatorLiteral(op.kind) catch {
            try self.context.diagnostics.reportError(op.position, "Unsupported Operator for operator overloading function");
            return Error.ParsingError;
        };

        const op_kind = op.kind;

        if (kind == .Prefix and !tokenizer.overloadingPrefixOperators(op_kind)) {
            try self.context.diagnostics.reportError(op.position, "this operator can't be used as prefix operator");
            return Error.ParsingError;
        }

        if (kind == .Infix and !tokenizer.overloadingInfixOperators(op_kind)) {
            try self.context.diagnostics.reportError(op.position, "this operator can't be used as infix operator");
            return Error.ParsingError;
        }

        if (kind == .Postfix and !tokenizer.overloadingPostfixOperators(op_kind)) {
            try self.context.diagnostics.reportError(op.position, "this operator can't be used as postfix operator");
            return Error.ParsingError;
        }

        return op;
    }

    fn parseStructureDeclaration(
        self: *Self,
        is_packed: bool,
        is_extern: bool,
    ) Error!*ast.Statement {
        log("Parsing Structure Declaration", .{}, .{ .module = .Parser });
        const struct_token = (try self.consumeKind(.Struct, "Expect struct keyword")).?;
        _ = struct_token;
        const struct_name = (try self.consumeKind(.Identifier, "Expect Symbol as struct name")).?;
        const struct_name_str = struct_name.literal;

        if (self.context.structures.contains(struct_name_str)) {
            try self.context.diagnostics.reportError(struct_name.position, try std.fmt.allocPrint(self.allocator, "There is already struct with name '{s}'", .{struct_name_str}));
            return Error.ParsingError;
        }

        if (self.context.type_alias_table.contains(struct_name_str)) {
            try self.context.diagnostics.reportError(
                struct_name.position,
                try std.fmt.allocPrint(self.allocator, "There is already a type with name '{s}'", .{struct_name_str}),
            );
            return Error.ParsingError;
        }

        self.current_struct_name = struct_name.literal;

        var fields_names = std.ArrayList([]const u8).init(self.allocator);
        var fields_types = std.ArrayList(*Type).init(self.allocator);

        if (is_extern) {
            try self.assertKind(.Semicolon, "Expect `;` at the end of external struct");
            var structure_type = try self.allocReturn(Type, Type{ .Struct = types.StructType.init(
                struct_name_str,
                fields_names,
                fields_types,
                std.ArrayList([]const u8).init(self.allocator),
                std.ArrayList(*Type).init(self.allocator),
                true,
                false,
                true,
            ) });
            try self.context.structures.put(struct_name_str, &structure_type.Struct);
            try self.context.type_alias_table.defineAlias(struct_name_str, structure_type);
            self.current_struct_name = "";
            self.generic_parameter_names.clearRetainingCapacity();
            return self.allocReturn(ast.Statement, ast.Statement{ .struct_declaration = ast.StructDeclaration.init(structure_type) });
        }

        var generics_parameters: std.ArrayList([]const u8) = std.ArrayList([]const u8).init(self.allocator);

        const is_generic_struct: bool = self.isCurrentKind(TokenKind.Smaller);
        if (is_generic_struct) {
            _ = try self.advancedToken();
            while (self.isSourceAvailable() and !self.isCurrentKind(.Greater)) {
                const parameter = (try self.consumeKind(.Identifier, "Expect parameter name")).?;
                try self.checkGenericParameterName(parameter);
                try generics_parameters.append(parameter.literal);
                if (self.isCurrentKind(.Comma)) {
                    _ = try self.advancedToken();
                } else {
                    break;
                }
            }
            try self.assertKind(.Greater, "Expect > after struct type parameters");
        }

        try self.assertKind(.OpenBrace, "Expect { after struct name");
        while (self.isSourceAvailable() and !self.isCurrentKind(.CloseBrace)) {
            const field_name = (try self.consumeKind(.Identifier, "Expect Symbol as struct name")).?;
            if (ds.contains([]const u8, fields_names.items, field_name.literal)) {
                try self.context.diagnostics.reportError(field_name.position, try std.fmt.allocPrint(self.allocator, "There is already struct member with name '{s}'", .{field_name.literal}));
                return Error.ParsingError;
            }

            try fields_names.append(field_name.literal);
            var field_type = try self.parseType();

            if (field_type.typeKind() == .None) {
                try self.context.diagnostics.reportError(field_name.position, try std.fmt.allocPrint(self.allocator, "Field type isn't fully defined yet, you can't use it until it defined but you can use *{s}", .{struct_name_str}));

                return Error.ParsingError;
            }

            try fields_types.append(field_type);
            try self.assertKind(.Semicolon, "Expect ; at the end of struct field declaration");
        }

        try self.assertKind(.CloseBrace, "Expect } in the end of struct declaration");

        try self.checkUnnecessarySemicolonWarning();

        var structure_type = try self.allocReturn(Type, Type{ .Struct = types.StructType.init(
            struct_name_str,
            fields_names,
            fields_types,
            generics_parameters,
            std.ArrayList(*Type).init(self.allocator),
            is_packed,
            is_generic_struct,
            false,
        ) });

        if (self.current_struct_unknown_fields > 0) {
            const struct_pointer_ty = try self.allocReturn(types.PointerType, types.PointerType{ .base_type = structure_type });

            const fields_size = fields_types.items.len;
            for (0..fields_size) |i| {
                const field_type = try self.resolveFieldSelfReference(fields_types.items[i], struct_pointer_ty);
                structure_type.Struct.field_types.items[i] = field_type;
            }
        }

        std.debug.assert(self.current_struct_unknown_fields == 0);

        try self.context.structures.put(struct_name_str, &structure_type.Struct);
        try self.context.type_alias_table.defineAlias(struct_name_str, structure_type);
        self.current_struct_name = "";
        self.generic_parameter_names.clearRetainingCapacity();

        return self.allocReturn(ast.Statement, ast.Statement{ .struct_declaration = ast.StructDeclaration.init(structure_type) });
    }

    fn parseEnumDeclaration(self: *Self) Error!*ast.Statement {
        log("Parsing Enum Declaration", .{}, .{ .module = .Parser });
        const enum_token = (try self.consumeKind(.Enum, "Expect enum keyword")).?;
        _ = enum_token;
        const enum_name = (try self.consumeKind(.Identifier, "Expect Symbol as enum name")).?;

        var element_type: ?*Type = null;

        if (self.isCurrentKind(.Colon)) {
            _ = try self.advancedToken();
            element_type = try self.parseType();
        } else {
            element_type = @constCast(&Type.I32_TYPE);
        }

        try self.assertKind(.OpenBrace, "Expect { after enum name");
        var enum_values = std.ArrayList(Token).init(self.allocator);
        var enum_values_indexes = std.StringArrayHashMap(u32).init(self.allocator);
        var explicit_values = std.AutoHashMap(u32, void).init(self.allocator);
        var index: usize = 0;
        var has_explicit_values = false;

        while (self.isSourceAvailable() and !self.isCurrentKind(.CloseBrace)) {
            const enum_value = (try self.consumeKind(.Identifier, "Expect Symbol as enum value")).?;
            try enum_values.append(enum_value);
            const enum_field_literal = enum_value.literal;

            if (enum_values_indexes.contains(enum_field_literal)) {
                try self.context.diagnostics.reportError(enum_value.position, "Can't declare 2 elements with the same name");
                return Error.ParsingError;
            }

            if (self.isCurrentKind(.Equal)) {
                _ = try self.advancedToken();
                const field_value = try self.parseExpression();
                if (field_value.getAstNodeType() != ast.AstNodeType.Number) {
                    try self.context.diagnostics.reportError(enum_value.position, "Enum field explicit value must be integer expression");
                    return Error.ParsingError;
                }

                const number_expr = field_value.number_expression;
                const number_value_token = number_expr.value;
                if (tokenizer.isFloatNumberToken(number_value_token.kind)) {
                    try self.context.diagnostics.reportError(enum_value.position, "Enum field explicit value must be integer value not float");
                    return Error.ParsingError;
                }

                const explicit_value = try std.fmt.parseInt(u32, number_value_token.literal, 10);
                if (explicit_values.contains(explicit_value)) {
                    try self.context.diagnostics.reportError(enum_value.position, try std.fmt.allocPrint(self.allocator, "There is also one enum field with explicit value '{d}'", .{explicit_value}));
                    return Error.ParsingError;
                }

                try explicit_values.put(explicit_value, {});
                try enum_values_indexes.put(enum_field_literal, explicit_value);
                has_explicit_values = true;
            } else {
                if (has_explicit_values) {
                    try self.context.diagnostics.reportError(enum_value.position, "You must add explicit value to all enum fields or to no one");
                    return Error.ParsingError;
                }
                try enum_values_indexes.put(enum_field_literal, @intCast(index));
                index += 1;
            }

            if (self.isCurrentKind(.Comma)) {
                _ = try self.advancedToken();
            }
        }

        try self.assertKind(.CloseBrace, "Expect } in the end of enum declaration");

        try self.checkUnnecessarySemicolonWarning();

        const enum_type = try self.allocReturn(types.EnumType, types.EnumType.init(enum_name.literal, enum_values_indexes, element_type));

        try self.context.enumerations.put(enum_name.literal, enum_type);
        const type_ = try self.allocReturn(Type, Type{ .Enum = enum_type.* });
        return self.allocReturn(ast.Statement, ast.Statement{ .enum_declaration = ast.EnumDeclaration.init(enum_name, type_) });
    }

    fn parseParameter(self: *Self) Error!*ast.Parameter {
        log("Parsing Parameter", .{}, .{ .module = .Parser });
        const name = (try self.consumeKind(.Identifier, "Expect identifier as parameter name")).?;
        const type_ = try self.parseType();
        return self.allocReturn(ast.Parameter, ast.Parameter.init(name, type_));
    }

    fn parseBlockStatement(self: *Self) Error!*ast.Statement {
        log("Parsing Block Statement", .{}, .{ .module = .Parser });
        try self.assertKind(.OpenBrace, "Expect { on the start of block");
        var statements = std.ArrayList(*ast.Statement).init(self.allocator);
        while (self.isSourceAvailable() and !self.isCurrentKind(.CloseBrace)) {
            try statements.append(try self.parseStatement());
        }
        try self.assertKind(.CloseBrace, "Expect } on the end of block");
        return self.allocReturn(ast.Statement, ast.Statement{ .block_statement = ast.BlockStatement.init(statements) });
    }

    fn parseReturnStatement(self: *Self) Error!*ast.Statement {
        log("Parsing Return Statement", .{}, .{ .module = .Parser });
        const keyword = (try self.consumeKind(.Return, "Expect return keyword")).?;
        if (self.isCurrentKind(.Semicolon)) {
            try self.assertKind(.Semicolon, "Expect semicolon `;` after return keyword");
            return self.allocReturn(ast.Statement, ast.Statement{ .return_statement = ast.ReturnStatement.init(keyword, null, false) });
        }
        const value = try self.parseExpression();
        try self.assertKind(.Semicolon, "Expect semicolon `;` after return statement");
        return self.allocReturn(ast.Statement, ast.Statement{ .return_statement = ast.ReturnStatement.init(keyword, value, true) });
    }

    fn parseDeferStatement(self: *Self) Error!*ast.Statement {
        log("Parsing Defer Statement", .{}, .{ .module = .Parser });
        const defer_token = (try self.consumeKind(.Defer, "Expect Defer keyword")).?;
        const expression = try self.parseExpression();
        if (expression.getAstNodeType() == .Call) {
            try self.assertKind(.Semicolon, "Expect semicolon `;` after defer call statement");
            return self.allocReturn(ast.Statement, ast.Statement{ .defer_statement = ast.DeferStatement.init(expression) });
        }
        try self.context.diagnostics.reportError(defer_token.position, "defer keyword expect call expression");
        return Error.ParsingError;
    }

    fn parseBreakStatement(self: *Self) Error!*ast.Statement {
        log("Parsing Break Statement", .{}, .{ .module = .Parser });
        const break_token = (try self.consumeKind(.Break, "Expect break keyword")).?;
        if (self.current_ast_scope != .Condition or self.loop_levels_stack.items[self.loop_levels_stack.items.len - 1] == 0) {
            try self.context.diagnostics.reportError(break_token.position, "break keyword can only be used inside at last one while loop");
            return Error.ParsingError;
        }

        if (self.isCurrentKind(.Semicolon)) {
            try self.assertKind(.Semicolon, "Expect semicolon `;` after break call statement");
            return self.allocReturn(ast.Statement, ast.Statement{ .break_statement = ast.BreakStatement.init(break_token, false, 1) });
        }

        const break_times = try self.parseExpression();
        if (break_times.getAstNodeType() == .Number) {
            const number_expr = break_times.number_expression;
            const number_value = number_expr.value;
            if (number_value.kind == .Float or number_value.kind == .Float32 or number_value.kind == .Float64) {
                try self.context.diagnostics.reportError(break_token.position, "expect break keyword times to be integer but found floating pointer value");
                return Error.ParsingError;
            }

            const times_int = try std.fmt.parseInt(u32, number_value.literal, 10);
            if (times_int < 1) {
                try self.context.diagnostics.reportError(break_token.position, "expect break times must be positive value and at last 1");
                return Error.ParsingError;
            }

            if (times_int > self.loop_levels_stack.items[self.loop_levels_stack.items.len - 1]) {
                try self.context.diagnostics.reportError(
                    break_token.position,
                    try std.fmt.allocPrint(self.allocator, "break times can't be bigger than the number of loops you have, expect less than or equals {d}", .{self.loop_levels_stack.items[self.loop_levels_stack.items.len - 1]}),
                );
                return Error.ParsingError;
            }

            try self.assertKind(.Semicolon, "Expect semicolon `;` after brea statement");
            return self.allocReturn(ast.Statement, ast.Statement{ .break_statement = ast.BreakStatement.init(break_token, true, times_int) });
        }

        try self.context.diagnostics.reportError(break_token.position, "break keyword times must be a number");
        return Error.ParsingError;
    }

    fn parseContinueStatement(self: *Self) Error!*ast.Statement {
        log("Parsing Continue Statement", .{}, .{ .module = .Parser });
        const continue_token = (try self.consumeKind(.Continue, "Expect continue keyword")).?;
        if (self.current_ast_scope != .Condition or self.loop_levels_stack.items[self.loop_levels_stack.items.len - 1] == 0) {
            try self.context.diagnostics.reportError(continue_token.position, "continue keyword can only be used inside at last one while loop");
            return Error.ParsingError;
        }

        if (self.isCurrentKind(.Semicolon)) {
            try self.assertKind(.Semicolon, "Expect semicolon `;` after defer call statement");
            return self.allocReturn(ast.Statement, ast.Statement{ .continue_statement = ast.ContinueStatement.init(continue_token, false, 1) });
        }

        const continue_times = try self.parseExpression();
        if (continue_times.getAstNodeType() == ast.AstNodeType.Number) {
            const number_expr = continue_times.number_expression;
            const number_value = number_expr.value;
            const number_kind = number_value.kind;
            if (number_kind == .Float or number_kind == .Float32 or number_kind == .Float64) {
                try self.context.diagnostics.reportError(continue_token.position, "expect continue times to be integer but found floating pointer value");
                return Error.ParsingError;
            }

            const times_int = try std.fmt.parseInt(u32, number_value.literal, 10);
            if (times_int < 1) {
                try self.context.diagnostics.reportError(continue_token.position, "expect continue times must be positive value and at last 1");
                return Error.ParsingError;
            }

            if (times_int > self.loop_levels_stack.items[self.loop_levels_stack.items.len - 1]) {
                try self.context.diagnostics.reportError(
                    continue_token.position,
                    try std.fmt.allocPrint(self.allocator, "continue times can't be bigger than the number of loops you have, expect less than or equals {d}", .{self.loop_levels_stack.items[self.loop_levels_stack.items.len - 1]}),
                );
                return Error.ParsingError;
            }

            try self.assertKind(.Semicolon, "Expect semicolon `;` after break statement");
            return self.allocReturn(ast.Statement, ast.Statement{ .continue_statement = ast.ContinueStatement.init(continue_token, true, times_int) });
        }

        try self.context.diagnostics.reportError(continue_token.position, "continue keyword times must be a number");
        return Error.ParsingError;
    }

    fn parseIfStatement(self: *Self) Error!*ast.Statement {
        log("Parsing If Statement", .{}, .{ .module = .Parser });
        const parent_node_scope = self.current_ast_scope;
        self.current_ast_scope = .Condition;

        const if_token = (try self.consumeKind(.If, "Expect If keyword")).?;
        try self.assertKind(.OpenParen, "Expect ( before if condition");
        const condition = try self.parseExpression();
        try self.assertKind(.CloseParen, "Expect ) after if condition");
        const then_block = try self.parseStatement();
        var conditional_blocks = std.ArrayList(*ast.ConditionalBlock).init(self.allocator);
        const conditional_block = try self.allocReturn(ast.ConditionalBlock, ast.ConditionalBlock.init(if_token, condition, then_block));
        try conditional_blocks.append(conditional_block);

        var has_else_branch = false;
        while (self.isSourceAvailable() and self.isCurrentKind(.Else)) {
            const else_token = (try self.consumeKind(.Else, "Expect else keyword")).?;
            if (self.isCurrentKind(.If)) {
                _ = try self.advancedToken();
                const elif_condition = try self.parseExpression();
                const elif_block = try self.parseStatement();
                const elif_condition_block = try self.allocReturn(ast.ConditionalBlock, ast.ConditionalBlock.init(else_token, elif_condition, elif_block));
                try conditional_blocks.append(elif_condition_block);
                continue;
            }

            if (has_else_branch) {
                try self.context.diagnostics.reportError(else_token.position, "You already declared else branch");
                return Error.ParsingError;
            }

            var true_value_token = else_token;
            true_value_token.kind = .True;
            const true_expression = try self.allocReturn(ast.Expression, ast.Expression{ .bool_expression = ast.BoolExpression.init(true_value_token) });
            const else_block = try self.parseStatement();
            const else_condition_block = try self.allocReturn(ast.ConditionalBlock, ast.ConditionalBlock.init(else_token, true_expression, else_block));
            try conditional_blocks.append(else_condition_block);
            has_else_branch = true;
        }

        self.current_ast_scope = parent_node_scope;
        return self.allocReturn(ast.Statement, ast.Statement{ .if_statement = ast.IfStatement.init(conditional_blocks, has_else_branch) });
    }

    fn parseForStatement(self: *Self) Error!*ast.Statement {
        log("Parsing For Statement", .{}, .{ .module = .Parser });
        const parent_node_scope = self.current_ast_scope;
        self.current_ast_scope = .Condition;

        const for_token = (try self.consumeKind(.For, "Expect For keyword")).?;
        if (self.isCurrentKind(.OpenBrace)) {
            self.loop_levels_stack.items[self.loop_levels_stack.items.len - 1] += 1;
            const body = try self.parseStatement();
            self.loop_levels_stack.items[self.loop_levels_stack.items.len - 1] -= 1;

            self.current_ast_scope = parent_node_scope;
            return self.allocReturn(ast.Statement, ast.Statement{ .for_ever_statement = ast.ForEverStatement.init(for_token, body) });
        }

        try self.assertKind(.OpenParen, "Expect ( before for names and collection");

        var element_name: []const u8 = "it";
        var index_name: []const u8 = "it_index";
        var has_custom_index_name = false;

        var expr = try self.parseExpression();
        if (self.isCurrentKind(.Colon) or self.isCurrentKind(.Comma)) {
            if (expr.getAstNodeType() != .Literal) {
                try self.context.diagnostics.reportError(for_token.position, "Optional named variable must be identifier");
                return Error.ParsingError;
            }

            if (self.isCurrentKind(.Comma)) {
                index_name = self.previous_token.?.literal;
                has_custom_index_name = true;
                _ = try self.advancedToken();
                element_name = (try self.consumeKind(.Identifier, "Expect element name")).?.literal;
            } else {
                element_name = self.previous_token.?.literal;
            }

            try self.assertKind(.Colon, "Expect `:` after element name in foreach");
            expr = try self.parseExpression();
        }

        if (self.isCurrentKind(.DotDot)) {
            if (has_custom_index_name) {
                try self.context.diagnostics.reportError(for_token.position, "for range has no index name to override");
                return Error.ParsingError;
            }

            _ = try self.advancedToken();
            const range_end = try self.parseExpression();
            var step: ?*ast.Expression = null;
            if (self.isCurrentKind(.Colon)) {
                _ = try self.advancedToken();
                step = try self.parseExpression();
            }

            try self.assertKind(.CloseParen, "Expect ) after for names and collection");
            self.loop_levels_stack.items[self.loop_levels_stack.items.len - 1] += 1;
            const body = try self.parseStatement();
            self.loop_levels_stack.items[self.loop_levels_stack.items.len - 1] -= 1;

            self.current_ast_scope = parent_node_scope;

            return self.allocReturn(ast.Statement, ast.Statement{ .for_range_statement = ast.ForRangeStatement.init(for_token, element_name, expr, range_end, step, body) });
        }

        try self.assertKind(.CloseParen, "Expect ) after for names and collection");

        self.loop_levels_stack.items[self.loop_levels_stack.items.len - 1] += 1;
        const body = try self.parseStatement();
        self.loop_levels_stack.items[self.loop_levels_stack.items.len - 1] -= 1;

        self.current_ast_scope = parent_node_scope;

        return self.allocReturn(ast.Statement, ast.Statement{ .for_each_statement = ast.ForEachStatement.init(for_token, element_name, index_name, expr, body) });
    }

    fn parseWhileStatement(self: *Self) Error!*ast.Statement {
        log("Parsing While Statement", .{}, .{ .module = .Parser });
        const parent_node_scope = self.current_ast_scope;
        self.current_ast_scope = .Condition;

        const while_token = (try self.consumeKind(.While, "Expect While keyword")).?;
        try self.assertKind(.OpenParen, "Expect ( before while condition");
        const condition = try self.parseExpression();
        try self.assertKind(.CloseParen, "Expect ) after while condition");
        self.loop_levels_stack.items[self.loop_levels_stack.items.len - 1] += 1;
        const body = try self.parseStatement();
        self.loop_levels_stack.items[self.loop_levels_stack.items.len - 1] -= 1;
        self.current_ast_scope = parent_node_scope;
        return self.allocReturn(ast.Statement, ast.Statement{ .while_statement = ast.WhileStatement.init(while_token, condition, body) });
    }

    fn parseSwitchastatement(self: *Self) Error!*ast.Statement {
        log("Parsing Switch Statement", .{}, .{ .module = .Parser });
        const switch_token = (try self.consumeKind(.Switch, "Expect Switch keyword")).?;
        try self.assertKind(.OpenParen, "Expect ( before switch argument");
        const argument = try self.parseExpression();
        const op = try self.parseSwitchOperator();
        try self.assertKind(.CloseParen, "Expect ) after switch argument");
        try self.assertKind(.OpenBrace, "Expect { after switch value");

        var switch_cases = std.ArrayList(*ast.SwitchCase).init(self.allocator);
        var default_branch: ?*ast.SwitchCase = null;
        var has_default_case = false;

        while (self.isSourceAvailable() and !self.isCurrentKind(.CloseBrace)) {
            var values = std.ArrayList(*ast.Expression).init(self.allocator);
            if (self.isCurrentKind(.Else)) {
                if (has_default_case) {
                    try self.context.diagnostics.reportError(switch_token.position, "Switch statementscan't has more than one default branch");
                    return Error.ParsingError;
                }

                const else_keyword = (try self.consumeKind(.Else, "Expect else keyword in switch defult branch")).?;
                _ = try self.consumeKind(.RightArrow, "Expect after else keyword in switch default branch");
                const default_body = try self.parseStatement();
                try values.append(argument);
                default_branch = try self.allocReturn(ast.SwitchCase, ast.SwitchCase.init(else_keyword, values, default_body));
                has_default_case = true;
                continue;
            }

            // parse all values for this case V1, V2, ..., Vn ->
            while (self.isSourceAvailable() and !self.isCurrentKind(.RightArrow)) {
                const value = try self.parseExpression();
                try values.append(value);
                if (self.isCurrentKind(.Comma)) {
                    _ = try self.advancedToken();
                }
            }

            const right_arrow = (try self.consumeKind(.RightArrow, "Expect after branch value")).?;
            const branch = try self.parseStatement();
            const switch_case = try self.allocReturn(ast.SwitchCase, ast.SwitchCase.init(right_arrow, values, branch));
            try switch_cases.append(switch_case);
        }

        try self.assertKind(.CloseBrace, "Expect } after switch Statement last branch");

        if (has_default_case) {
            try switch_cases.append(default_branch.?);
        }

        return self.allocReturn(ast.Statement, ast.Statement{ .switch_statement = ast.SwitchStatement.init(switch_token, argument, switch_cases, op, has_default_case, false) });
    }

    fn parseExpressionStatement(self: *Self) Error!*ast.Statement {
        log("Parsing Expression Statement", .{}, .{ .module = .Parser });
        const expression = try self.parseExpression();
        try self.assertKind(.Semicolon, "Expect semicolon `;` after field declaration");
        return self.allocReturn(ast.Statement, ast.Statement{ .expression_statement = ast.ExpressionStatement.init(expression) });
    }

    fn parseExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Expression", .{}, .{ .module = .Parser });
        return try self.parseAssignmentExpression();
    }

    fn parseAssignmentExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Assignament Expression", .{}, .{ .module = .Parser });
        const expression = try self.parseLogicalOrExpression();
        if (tokenizer.assignmentOperators(self.peekCurrent().kind)) {
            var assignments_token = try self.peekAndAdvanceToken();
            const assignments_token_kind = assignments_token.kind;
            const rhs = try self.parseAssignmentExpression();

            if (tokenizer.assignmentBinaryOperators(assignments_token_kind) != error.NotFound) {
                const op_kind = try tokenizer.assignmentBinaryOperators(assignments_token_kind);
                assignments_token.kind = op_kind;
                const binary = try self.allocReturn(ast.Expression, ast.Expression{ .binary_expression = ast.BinaryExpression.init(assignments_token, expression, rhs) });
                return self.allocReturn(ast.Expression, ast.Expression{ .assign_expression = ast.AssignExpression.init(assignments_token, expression, binary) });
            }

            if (tokenizer.assignmentBitwiseOperators(assignments_token_kind) != error.NotFound) {
                const op_kind = try tokenizer.assignmentBitwiseOperators(assignments_token_kind);
                assignments_token.kind = op_kind;
                const bitwise = try self.allocReturn(ast.Expression, ast.Expression{ .bitwise_expression = ast.BitwiseExpression.init(assignments_token, expression, rhs) });
                return self.allocReturn(ast.Expression, ast.Expression{ .assign_expression = ast.AssignExpression.init(assignments_token, expression, bitwise) });
            }

            return self.allocReturn(ast.Expression, ast.Expression{ .assign_expression = ast.AssignExpression.init(assignments_token, expression, rhs) });
        }

        return expression;
    }

    fn parseLogicalOrExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Logical Or Expression", .{}, .{ .module = .Parser });
        var expression = try self.parseLogicalAndExpression();
        while (self.isCurrentKind(.OrOr)) {
            const or_token = try self.peekAndAdvanceToken();
            const right = try self.parseLogicalAndExpression();
            expression = try self.allocReturn(ast.Expression, ast.Expression{ .logical_expression = ast.LogicalExpression.init(or_token, expression, right) });
        }
        return expression;
    }

    fn parseLogicalAndExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Logical And Expression", .{}, .{ .module = .Parser });
        var expression = try self.parseBitwiseAndExpression();
        while (self.isCurrentKind(.AndAnd)) {
            const and_token = try self.peekAndAdvanceToken();
            const right = try self.parseBitwiseAndExpression();
            expression = try self.allocReturn(ast.Expression, ast.Expression{ .logical_expression = ast.LogicalExpression.init(and_token, expression, right) });
        }
        return expression;
    }

    fn parseBitwiseAndExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Bitwise And Expression", .{}, .{ .module = .Parser });
        var expression = try self.parseBitwiseXorExpression();
        while (self.isCurrentKind(.And)) {
            const and_token = try self.peekAndAdvanceToken();
            const right = try self.parseBitwiseXorExpression();
            expression = try self.allocReturn(ast.Expression, ast.Expression{ .bitwise_expression = ast.BitwiseExpression.init(and_token, expression, right) });
        }
        return expression;
    }

    fn parseBitwiseXorExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Bitwise Xor Expression", .{}, .{ .module = .Parser });
        var expression = try self.parseBitwiseOrExpression();
        while (self.isCurrentKind(.Xor)) {
            const and_token = try self.peekAndAdvanceToken();
            const right = try self.parseBitwiseOrExpression();
            expression = try self.allocReturn(ast.Expression, ast.Expression{ .bitwise_expression = ast.BitwiseExpression.init(and_token, expression, right) });
        }
        return expression;
    }

    fn parseBitwiseOrExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Bitwise Or Expression", .{}, .{ .module = .Parser });
        var expression = try self.parseEqualityExpression();
        while (self.isCurrentKind(.Or)) {
            const and_token = try self.peekAndAdvanceToken();
            const right = try self.parseEqualityExpression();
            expression = try self.allocReturn(ast.Expression, ast.Expression{ .bitwise_expression = ast.BitwiseExpression.init(and_token, expression, right) });
        }
        return expression;
    }

    fn parseEqualityExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Equality Expression", .{}, .{ .module = .Parser });
        var expression = try self.parseComparisonExpression();
        while (self.isCurrentKind(.EqualEqual) or self.isCurrentKind(.BangEqual)) {
            const op = try self.peekAndAdvanceToken();
            const right = try self.parseComparisonExpression();
            expression = try self.allocReturn(ast.Expression, ast.Expression{ .comparison_expression = ast.ComparisonExpression.init(op, expression, right) });
        }
        return expression;
    }

    fn parseComparisonExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Comparison Expression", .{}, .{ .module = .Parser });
        var expression = try self.parseBitwiseShiftExpression();
        while (self.isCurrentKind(.Greater) or self.isCurrentKind(.GreaterEqual) or self.isCurrentKind(.Smaller) or self.isCurrentKind(.SmallerEqual)) {
            const op = try self.peekAndAdvanceToken();
            const right = try self.parseBitwiseShiftExpression();
            if (expression.getAstNodeType() == .Comparison) {
                const left_comparison = expression.comparison_expression;
                const new_left = left_comparison.right;
                const comparison = try self.allocReturn(ast.Expression, ast.Expression{ .comparison_expression = ast.ComparisonExpression.init(op, new_left, right) });
                const logical_op = Token{ .kind = .AndAnd, .literal = "&&", .position = op.position };
                expression = try self.allocReturn(ast.Expression, ast.Expression{ .logical_expression = ast.LogicalExpression.init(logical_op, expression, comparison) });
                continue;
            }

            expression = try self.allocReturn(ast.Expression, ast.Expression{ .comparison_expression = ast.ComparisonExpression.init(op, expression, right) });
        }
        return expression;
    }

    fn parseBitwiseShiftExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Bitwise Shift Expression", .{}, .{ .module = .Parser });
        var expression = try self.parseTermExpression();
        while (self.isCurrentKind(.LeftShift) or self.isRightShiftOperator(self.peekCurrent(), self.peekNext())) {
            if (self.isCurrentKind(.LeftShift)) {
                const op = try self.peekAndAdvanceToken();
                const right = try self.parseTermExpression();
                expression = try self.allocReturn(ast.Expression, ast.Expression{ .bitwise_expression = ast.BitwiseExpression.init(op, expression, right) });
                continue;
            }

            _ = try self.advancedToken();
            var op = try self.peekAndAdvanceToken();
            op.kind = .RightShift;
            const right = try self.parseTermExpression();
            expression = try self.allocReturn(ast.Expression, ast.Expression{ .bitwise_expression = ast.BitwiseExpression.init(op, expression, right) });
        }
        return expression;
    }

    fn parseTermExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Term Expression", .{}, .{ .module = .Parser });
        var expression = try self.parseFactorExpression();
        while (self.isCurrentKind(.Plus) or self.isCurrentKind(.Minus)) {
            const op = try self.peekAndAdvanceToken();
            const right = try self.parseFactorExpression();
            expression = try self.allocReturn(ast.Expression, ast.Expression{ .binary_expression = ast.BinaryExpression.init(op, expression, right) });
        }
        return expression;
    }

    fn parseFactorExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Factor Expression", .{}, .{ .module = .Parser });
        var expression = try self.parseEnumAccessExpression();
        while (self.isCurrentKind(.Star) or self.isCurrentKind(.Slash) or self.isCurrentKind(.Percent)) {
            const op = try self.peekAndAdvanceToken();
            const right = try self.parseEnumAccessExpression();
            expression = try self.allocReturn(ast.Expression, ast.Expression{ .binary_expression = ast.BinaryExpression.init(op, expression, right) });
        }
        return expression;
    }

    fn parseEnumAccessExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Enum Access Expression", .{}, .{ .module = .Parser });
        var expression = try self.parseInfixCallExpression();
        if (self.isCurrentKind(.ColonColon)) {
            const colons_token = try self.peekAndAdvanceToken();
            if (expression.getAstNodeType() == ast.AstNodeType.Literal) {
                const enum_name = expression.literal_expression.name;
                if (self.context.enumerations.contains(enum_name.literal)) {
                    const enum_type = self.context.enumerations.get(enum_name.literal).?;
                    const element = (try self.consumeKind(.Identifier, "Expect identifier s enum field name")).?;
                    const enum_values = enum_type.values;
                    if (!enum_values.contains(element.literal)) {
                        try self.context.diagnostics.reportError(element.position, try std.fmt.allocPrint(self.allocator, "Can't find element with name '{s}' in enum '{s}'", .{ element.literal, enum_name.literal }));
                        return Error.ParsingError;
                    }

                    const index = enum_values.get(element.literal).?;
                    const enum_element_type = try self.allocReturn(Type, types.Type{ .EnumElement = types.EnumElementType.init(enum_name.literal, enum_type.element_type.?) });
                    return self.allocReturn(ast.Expression, ast.Expression{ .enum_access_expression = ast.EnumAccessExpression.init(element, enum_name, index, enum_element_type) });
                } else {
                    try self.context.diagnostics.reportError(colons_token.position, try std.fmt.allocPrint(self.allocator, "Can't find enum declaration with name '{s}'", .{enum_name.literal}));
                    return Error.ParsingError;
                }
            } else {
                try self.context.diagnostics.reportError(colons_token.position, "Expect identifier as Enum name");
                return Error.ParsingError;
            }
        }

        return expression;
    }

    fn parseInfixCallExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Infix Call Expression", .{}, .{ .module = .Parser });
        const expression = try self.parsePrefixExpression();
        const current_token_literal = self.peekCurrent().literal;

        if (self.isCurrentKind(.Identifier) and self.isFunctionDeclarationKind(current_token_literal, .Infix)) {
            const name_token = self.peekCurrent();
            const function_name = try self.parseLiteralExpression();
            const generic_arguments = try self.parseGenericArgumentsIfExists();
            var arguments = std.ArrayList(*ast.Expression).init(self.allocator);
            _ = try arguments.append(expression);
            _ = try arguments.append(try self.parseInfixCallExpression());
            return self.allocReturn(ast.Expression, ast.Expression{ .call_expression = ast.CallExpression.init(name_token, function_name, arguments, generic_arguments) });
        }

        return expression;
    }

    fn parsePrefixExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Prefix Expression", .{}, .{ .module = .Parser });
        if (tokenizer.unaryOperators(self.peekCurrent().kind)) {
            const token = try self.peekAndAdvanceToken();
            const right = try self.parsePrefixExpression();
            return self.allocReturn(ast.Expression, ast.Expression{ .prefix_unary_expression = ast.PrefixUnaryExpression.init(token, right) });
        }

        if (self.isCurrentKind(.PlusPlus) or self.isCurrentKind(.MinusMinus)) {
            const token = try self.peekAndAdvanceToken();
            const right = try self.parsePrefixExpression();
            return self.allocReturn(ast.Expression, ast.Expression{ .prefix_unary_expression = ast.PrefixUnaryExpression.init(token, right) });
        }

        return self.parsePrefixCallExpression();
    }

    fn parsePrefixCallExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Prefix Call Expression", .{}, .{ .module = .Parser });
        const current_token_literal = self.peekCurrent().literal;
        if (self.isCurrentKind(.Identifier) and self.isFunctionDeclarationKind(current_token_literal, .Prefix)) {
            const token = self.peekCurrent();
            const name = try self.parseLiteralExpression();
            const generic_arguments = try self.parseGenericArgumentsIfExists();
            var arguments = std.ArrayList(*ast.Expression).init(self.allocator);
            _ = try arguments.append(try self.parsePrefixExpression());
            return self.allocReturn(ast.Expression, ast.Expression{ .call_expression = ast.CallExpression.init(token, name, arguments, generic_arguments) });
        }

        return self.parsePostfixIncrementOrDecrement();
    }

    fn parsePostfixIncrementOrDecrement(self: *Self) Error!*ast.Expression {
        log("Parsing Postfix Increment Or Decrement", .{}, .{ .module = .Parser });
        const expression = try self.parseCallOrAccessExpression();
        if (self.isCurrentKind(.PlusPlus) or self.isCurrentKind(.MinusMinus)) {
            const token = try self.peekAndAdvanceToken();
            return self.allocReturn(ast.Expression, ast.Expression{ .postfix_unary_expression = ast.PostfixUnaryExpression.init(token, expression) });
        }

        return expression;
    }

    fn parseCallOrAccessExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Call Or Access Expression", .{}, .{ .module = .Parser });
        var expression = try self.parseEnumerationAttributeExpression();
        while (self.isCurrentKind(.Dot) or self.isCurrentKind(.OpenParen) or self.isCurrentKind(.OpenBracket) or (self.isCurrentKind(.Smaller) and expression.getAstNodeType() == .Literal)) {
            if (self.isCurrentKind(.Dot)) {
                const dot_token = try self.peekAndAdvanceToken();
                if (self.isCurrentKind(.Identifier)) {
                    const field_name = (try self.consumeKind(.Identifier, "Expect literal as field name")).?;
                    expression = try self.allocReturn(ast.Expression, ast.Expression{ .dot_expression = ast.DotExpression.init(dot_token, field_name, expression) });
                    continue;
                }

                if (self.isCurrentKind(.Int)) {
                    const field_name = (try self.consumeKind(.Int, "Expect literal as field name")).?;
                    var access = try self.allocReturn(ast.Expression, ast.Expression{ .dot_expression = ast.DotExpression.init(dot_token, field_name, expression) });
                    access.dot_expression.field_index = try std.fmt.parseInt(u32, field_name.literal, 10);
                    expression = access;
                    continue;
                }

                try self.context.diagnostics.reportError(dot_token.position, "DotExpression `.` must followed by symnol or integer for struct or tuple access");
                return Error.ParsingError;
            }

            if (self.isCurrentKind(.Smaller)) {
                const literal = expression.literal_expression;
                if (!self.context.functions.contains(literal.name.literal)) {
                    return expression;
                }

                const position = self.peekCurrent();
                const generic_arguments = try self.parseGenericArgumentsIfExists();
                try self.assertKind(.OpenParen, "Expect ( after in the end of function call");
                var arguments = std.ArrayList(*ast.Expression).init(self.allocator);
                while (!self.isCurrentKind(.CloseParen)) {
                    try arguments.append(try self.parseExpression());
                    if (self.isCurrentKind(.Comma)) {
                        _ = try self.advancedToken();
                    }
                }

                try self.assertKind(.CloseParen, "Expect ) after in the end of function call");

                if (self.isCurrentKind(.OpenBrace)) {
                    try arguments.append(try self.parseLambdaExpression());
                }

                expression = try self.allocReturn(ast.Expression, ast.Expression{ .call_expression = ast.CallExpression.init(position, expression, arguments, generic_arguments) });
                continue;
            }

            if (self.isCurrentKind(.OpenParen)) {
                const position = try self.peekAndAdvanceToken();
                var arguments = std.ArrayList(*ast.Expression).init(self.allocator);
                while (!self.isCurrentKind(.CloseParen)) {
                    try arguments.append(try self.parseExpression());
                    if (self.isCurrentKind(.Comma)) {
                        _ = try self.advancedToken();
                    }
                }

                try self.assertKind(.CloseParen, "Expect ) after in the end of function call");

                if (self.isCurrentKind(.OpenBrace)) {
                    try arguments.append(try self.parseLambdaExpression());
                }

                expression = try self.allocReturn(ast.Expression, ast.Expression{ .call_expression = ast.CallExpression.init(position, expression, arguments, std.ArrayList(*Type).init(self.allocator)) });
                continue;
            }

            if (self.isCurrentKind(.OpenBracket)) {
                const position = try self.peekAndAdvanceToken();
                const index = try self.parseExpression();
                try self.assertKind(.CloseBracket, "Expect ] after index value");
                expression = try self.allocReturn(ast.Expression, ast.Expression{ .index_expression = ast.IndexExpression.init(position, index, expression) });
                continue;
            }
        }

        return expression;
    }

    fn parseEnumerationAttributeExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Enumeration Attribute Expression", .{}, .{ .module = .Parser });
        var expression = try self.parsePostfixCallExpression();
        if (self.isCurrentKind(.Dot) and expression.getAstNodeType() == .Literal) {
            const literal = expression.literal_expression;
            const literal_str = literal.name.literal;
            if (self.context.enumerations.contains(literal_str)) {
                const dot_token = try self.peekAndAdvanceToken();
                _ = dot_token;
                const attribute = (try self.consumeKind(.Identifier, "Expect attribute name for enum")).?;
                const attribute_str = attribute.literal;
                if (std.mem.eql(u8, attribute_str, "count")) {
                    const count = self.context.enumerations.get(literal_str).?.values.count();
                    const number_token = Token{ .kind = TokenKind.Int, .position = attribute.position, .literal = try std.fmt.allocPrint(self.allocator, "{d}", .{count}) };
                    const number_type = @constCast(&Type.I64_TYPE);
                    return self.allocReturn(ast.Expression, ast.Expression{ .number_expression = ast.NumberExpression.init(number_token, number_type) });
                }

                try self.context.diagnostics.reportError(attribute.position, "Unsupported attribute for enumeration type");
                return Error.ParsingError;
            }
        }

        return expression;
    }

    fn parsePostfixCallExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Postfix Call Expression", .{}, .{ .module = .Parser });
        const expression = try self.parseInitializerExpression();
        const current_token_literal = self.peekCurrent().literal;
        if (self.isCurrentKind(.Identifier) and self.isFunctionDeclarationKind(current_token_literal, .Postfix)) {
            const token = self.peekCurrent();
            const name = try self.parseLiteralExpression();
            const generic_arguments = try self.parseGenericArgumentsIfExists();
            var arguments = std.ArrayList(*ast.Expression).init(self.allocator);
            _ = try arguments.append(expression);
            return self.allocReturn(ast.Expression, ast.Expression{ .call_expression = ast.CallExpression.init(token, name, arguments, generic_arguments) });
        }

        return expression;
    }

    fn parseInitializerExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Initializer Expression", .{}, .{ .module = .Parser });
        if (self.isCurrentKind(.Identifier) and self.context.type_alias_table.contains(self.peekCurrent().literal)) {
            const resolved_type = self.context.type_alias_table.resolveAlias(self.peekCurrent().literal);
            if (types.isStructType(resolved_type) or types.isGenericStructType(resolved_type)) {
                if (self.isNextKind(.OpenParen) or self.isNextKind(.OpenBrace) or self.isNextKind(.Smaller)) {
                    const type_ = try self.parseType();
                    const token = self.peekCurrent();
                    var arguments = std.ArrayList(*ast.Expression).init(self.allocator);

                    // Check if this constructor has arguments
                    if (self.isCurrentKind(.OpenParen)) {
                        _ = try self.advancedToken();
                        while (!self.isCurrentKind(.CloseParen)) {
                            try arguments.append(try self.parseExpression());
                            if (self.isCurrentKind(.Comma)) {
                                _ = try self.advancedToken();
                            } else {
                                break;
                            }
                        }

                        try self.assertKind(.CloseParen, "Expect ) at the end of initializer");
                    }

                    // Check if this constructor has outside lambda argument
                    if (self.isCurrentKind(.OpenBrace)) {
                        const lambda_argument = try self.parseLambdaExpression();
                        try arguments.append(lambda_argument);
                    }

                    return self.allocReturn(ast.Expression, ast.Expression{ .init_expression = ast.InitExpression.init(token, type_, arguments) });
                }
            }
        }

        return self.parseFunctionCallWithLambdaArgument();
    }

    fn parseFunctionCallWithLambdaArgument(self: *Self) Error!*ast.Expression {
        log("Parsing Function Call With Lambda Argument", .{}, .{ .module = .Parser });
        if (self.isCurrentKind(.Identifier) and self.isNextKind(.OpenBrace) and self.isFunctionDeclarationKind(self.peekCurrent().literal, .Normal)) {
            const symbol_token = self.peekCurrent();
            const literal = try self.parseLiteralExpression();
            var arguments = std.ArrayList(*ast.Expression).init(self.allocator);
            try arguments.append(try self.parseLambdaExpression());
            return self.allocReturn(ast.Expression, ast.Expression{ .call_expression = ast.CallExpression.init(symbol_token, literal, arguments, std.ArrayList(*Type).init(self.allocator)) });
        }

        return self.parsePrimaryExpression();
    }

    fn parsePrimaryExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Primary Expression", .{}, .{ .module = .Parser });
        const current_token_kind = self.peekCurrent().kind;
        switch (current_token_kind) {
            .Int, .Int1, .Int8, .Int16, .Int32, .Int64, .Uint8, .Uint16, .Uint32, .Uint64, .Float, .Float32, .Float64 => {
                return try self.parseNumberExpression();
            },

            .Character => {
                _ = try self.advancedToken();
                return self.allocReturn(ast.Expression, ast.Expression{ .character_expression = ast.CharacterExpression.init(self.peekPrevious()) });
            },

            .String => {
                _ = try self.advancedToken();
                return self.allocReturn(ast.Expression, ast.Expression{ .string_expression = ast.StringExpression.init(self.peekPrevious()) });
            },

            .True, .False => {
                _ = try self.advancedToken();
                return self.allocReturn(ast.Expression, ast.Expression{ .bool_expression = ast.BoolExpression.init(self.peekPrevious()) });
            },

            .Null => {
                _ = try self.advancedToken();
                return self.allocReturn(ast.Expression, ast.Expression{ .null_expression = ast.NullExpression.init(self.peekPrevious()) });
            },

            .Identifier => {
                // Resolve const or non const variable
                const name = self.peekCurrent();
                if (self.context.constants_table_map.isDefined(name.literal)) {
                    _ = try self.advancedToken();
                    return self.context.constants_table_map.lookup(name.literal).?;
                }

                return self.parseLiteralExpression();
            },

            .OpenParen => {
                return try self.parseGroupOrTupleExpression();
            },

            .OpenBracket => {
                return try self.parseArrayExpression();
            },

            .OpenBrace => {
                return try self.parseLambdaExpression();
            },

            .If => {
                return try self.parseIfExpression();
            },

            .Switch => {
                return try self.parseSwitchExpression();
            },

            .Cast => {
                return try self.parseCastExpression();
            },

            .TypeSize => {
                return try self.parseTypeSizeExpression();
            },

            .TypeAlign => {
                return try self.parseTypeAlignExpression();
            },

            .ValueSize => {
                return try self.parseValueSizeExpression();
            },

            .At => {
                return try self.parseExpressionsDirective();
            },

            else => {
                return try self.unexpectedTokenError();
            },
        }
    }

    fn parseLambdaExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Lambda Expression", .{}, .{ .module = .Parser });
        const open_brace = (try self.consumeKind(.OpenBrace, "Expect { at the start of lambda expression")).?;
        var parameters = std.ArrayList(*ast.Parameter).init(self.allocator);
        var return_type: ?*Type = null;

        if (self.isCurrentKind(.OpenParen)) {
            _ = try self.advancedToken();
            while (!self.isCurrentKind(.CloseParen)) {
                const parameter = try self.parseParameter();
                try parameters.append(parameter);
                if (self.isCurrentKind(.Comma)) {
                    _ = try self.advancedToken();
                } else {
                    break;
                }
            }

            try self.assertKind(.CloseParen, "Expect ) after lambda parameters");
            if (self.isCurrentKind(.RightArrow)) {
                _ = try self.advancedToken();
                return_type = @constCast(&Type.VOID_TYPE);
            } else {
                return_type = try self.parseType();
                try self.assertKind(.RightArrow, "Expect -> after lambda return type");
            }
        } else {
            return_type = @constCast(&Type.VOID_TYPE);
        }

        try self.loop_levels_stack.append(0);
        var body = std.ArrayList(*ast.Statement).init(self.allocator);
        while (self.isSourceAvailable() and !self.isCurrentKind(.CloseBrace)) {
            try body.append(try self.parseStatement());
        }
        _ = self.loop_levels_stack.pop();
        const lambda_body = try self.allocReturn(ast.BlockStatement, ast.BlockStatement{ .statements = body });
        const close_brace = (try self.consumeKind(.CloseBrace, "Expect } at the end of lambda expression")).?;

        if (types.isVoidType(return_type.?) and
            (body.items.len == 0 or body.items[body.items.len - 1].getAstNodeType() != .Return))
        {
            const void_return = try self.allocReturn(ast.Statement, ast.Statement{ .return_statement = ast.ReturnStatement.init(close_brace, null, false) });
            try lambda_body.statements.append(void_return);
        }

        return self.allocReturn(ast.Expression, ast.Expression{ .lambda_expression = ast.LambdaExpression.init(
            self.allocator,
            open_brace,
            parameters,
            std.ArrayList([]const u8).init(self.allocator),
            std.ArrayList(*Type).init(self.allocator),
            return_type.?,
            lambda_body,
        ) });
    }

    fn parseNumberExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Number Expression", .{}, .{ .module = .Parser });
        const token = try self.peekAndAdvanceToken();
        const number_kind = try self.getNumberKind(token.kind);
        const number_type = try self.allocReturn(Type, types.Type{ .Number = types.NumberType.init(number_kind) });
        return self.allocReturn(ast.Expression, ast.Expression{ .number_expression = ast.NumberExpression.init(token, number_type) });
    }

    fn parseLiteralExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Literal Expression", .{}, .{ .module = .Parser });
        const token = try self.peekAndAdvanceToken();
        return self.allocReturn(ast.Expression, ast.Expression{ .literal_expression = ast.LiteralExpression.init(token) });
    }

    fn parseIfExpression(self: *Self) Error!*ast.Expression {
        log("Parsing If Expression", .{}, .{ .module = .Parser });

        var tokens = std.ArrayList(Token).init(self.allocator);
        var conditions = std.ArrayList(*ast.Expression).init(self.allocator);
        var values = std.ArrayList(*ast.Expression).init(self.allocator);
        var has_else_branch = false;

        try tokens.append(try self.peekAndAdvanceToken());
        try self.assertKind(.OpenParen, "Expect ( before if condition");
        try conditions.append(try self.parseExpression());
        try self.assertKind(.CloseParen, "Expect ) after if condition");
        try self.assertKind(.OpenBrace, "Expect { at the start of if expression value");
        try values.append(try self.parseExpression());
        try self.assertKind(.CloseBrace, "Expect } at the end of if expression value");

        while (self.isCurrentKind(.Else)) {
            // Consume else token
            try tokens.append(try self.peekAndAdvanceToken());

            // parse `else if` node
            if (self.isCurrentKind(.If)) {
                // Consume if token
                _ = try self.advancedToken();
                try self.assertKind(.OpenParen, "Expect ( before if condition");
                try conditions.append(try self.parseExpression());
                try self.assertKind(.CloseParen, "Expect ) after if condition");
                try self.assertKind(.OpenBrace, "Expect { at the start of `else if` expression value");
                try values.append(try self.parseExpression());
                try self.assertKind(.CloseBrace, "Expect } at the end of `else if` expression value");
                continue;
            }

            // Prevent declring else branch more than once
            if (has_else_branch) {
                try self.context.diagnostics.reportError(self.peekCurrent().position, "else branch is declared twice in the same if expression");
                return Error.ParsingError;
            }

            // parse `else` node
            const true_token = Token{ .kind = TokenKind.True, .position = self.peekCurrent().position, .literal = "" };
            try conditions.append(try self.allocReturn(ast.Expression, ast.Expression{ .bool_expression = ast.BoolExpression.init(true_token) }));
            try self.assertKind(.OpenBrace, "Expect { at the start of `else` expression value");
            try values.append(try self.parseExpression());
            try self.assertKind(.CloseBrace, "Expect } at the end of `else` expression value");
            has_else_branch = true;
        }

        return self.allocReturn(ast.Expression, ast.Expression{ .if_expression = ast.IfExpression.init(tokens, conditions, values) });
    }

    fn parseSwitchExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Switch Expression", .{}, .{ .module = .Parser });
        const switch_token = (try self.consumeKind(.Switch, "Expect Switch keyword")).?;
        try self.assertKind(.OpenParen, "Expect ( before switch argument");
        const argument = try self.parseExpression();
        const op = try self.parseSwitchOperator();
        try self.assertKind(.CloseParen, "Expect ) after switch argument");
        try self.assertKind(.OpenBrace, "Expect { after switch value");

        var cases = std.ArrayList(*ast.Expression).init(self.allocator);
        var values = std.ArrayList(*ast.Expression).init(self.allocator);
        var default_value: ?*ast.Expression = null;
        var has_default_branch = false;

        while (self.isSourceAvailable() and !self.isCurrentKind(.CloseBrace)) {
            if (self.isCurrentKind(.Else)) {
                if (has_default_branch) {
                    has_default_branch = true;
                    try self.context.diagnostics.reportError(switch_token.position, "Switch expression can't has more than one default branch");
                    return Error.ParsingError;
                }

                try self.assertKind(.Else, "Expect else keyword in switch defult branch");
                try self.assertKind(.RightArrow, "Expect after else keyword in switch default branch");
                default_value = try self.parseExpression();
                try self.checkUnnecessarySemicolonWarning();
                continue;
            }

            while (true) : (if (!self.isCurrentKind(.Comma)) break) {
                if (self.isCurrentKind(.Comma)) {
                    if (cases.items.len > values.items.len) {
                        try self.advancedToken();
                    } else {
                        try self.context.diagnostics.reportError(self.peekCurrent().position, "In Switch Expression can't use `,` with no value before it");
                        return Error.ParsingError;
                    }
                }

                var case_expression = try self.parseExpression();
                const case_node_type = case_expression.getAstNodeType();
                if (case_node_type == .Number or case_node_type == .EnumElement) {
                    try cases.append(case_expression);
                    continue;
                }

                try self.context.diagnostics.reportError(switch_token.position, "Switch case must be a number or enum element");
                return Error.ParsingError;
            }
            const cases_values_count = cases.items.len - values.items.len;
            try self.assertKind(.RightArrow, "Expect after branch value");
            const right_value_expression = try self.parseExpression();
            for (0..cases_values_count) |_| {
                try values.append(right_value_expression);
            }
            try self.checkUnnecessarySemicolonWarning();
        }

        if (cases.items.len == 0) {
            try self.context.diagnostics.reportError(switch_token.position, "Switch expression must has at last one case and default case");
            return Error.ParsingError;
        }

        try self.assertKind(.CloseBrace, "Expect } after switch Statement last branch");
        return self.allocReturn(ast.Expression, ast.Expression{ .switch_expression = ast.SwitchExpression.init(switch_token, argument, cases, values, default_value, op) });
    }

    fn parseGroupOrTupleExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Group Or Tuple Expression", .{}, .{ .module = .Parser });
        try self.assertKind(.OpenParen, "Expect ( at the start of group or tuple expression");
        const expression = try self.parseExpression();

        // parse Tuple values expression
        if (self.isCurrentKind(.Comma)) {
            const token = try self.peekAndAdvanceToken();
            var values = std.ArrayList(*ast.Expression).init(self.allocator);
            try values.append(expression);

            while (!self.isCurrentKind(.CloseParen)) {
                try values.append(try self.parseExpression());
                if (self.isCurrentKind(.Comma)) {
                    _ = try self.advancedToken();
                }
            }

            try self.assertKind(.CloseParen, "Expect ) at the end of tuple values expression");
            return self.allocReturn(ast.Expression, ast.Expression{ .tuple_expression = ast.TupleExpression.init(token, values) });
        }

        try self.assertKind(.CloseParen, "Expect ) at the end of group expression");
        return expression;
    }

    fn parseArrayExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Array Expression", .{}, .{ .module = .Parser });
        const token = try self.peekAndAdvanceToken();
        var values = std.ArrayList(*ast.Expression).init(self.allocator);

        while (self.isSourceAvailable() and !self.isCurrentKind(.CloseBracket)) {
            try values.append(try self.parseExpression());
            if (self.isCurrentKind(.Comma)) {
                _ = try self.advancedToken();
            }
        }

        try self.assertKind(.CloseBracket, "Expect ] at the end of array values");
        return self.allocReturn(ast.Expression, ast.Expression{ .array_expression = ast.ArrayExpression.init(self.allocator, token, values) });
    }

    fn parseCastExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Cast Expression", .{}, .{ .module = .Parser });
        const cast_keyword = (try self.consumeKind(.Cast, "Expect cast keyword")).?;
        try self.assertKind(.OpenParen, "Expect ( after cast keyword");
        const target_type = try self.parseType();

        // Support syntx cast(T, value)
        if (self.isCurrentKind(.Comma)) {
            _ = try self.advancedToken();
            const expression = try self.parseExpression();
            try self.assertKind(.CloseParen, "Expect ) after cast type");
            return self.allocReturn(ast.Expression, ast.Expression{ .cast_expression = ast.CastExpression.init(cast_keyword, expression, target_type) });
        }

        try self.assertKind(.CloseParen, "Expect ) after cast type");
        const expression = try self.parseExpression();
        return self.allocReturn(ast.Expression, ast.Expression{ .cast_expression = ast.CastExpression.init(cast_keyword, expression, target_type) });
    }

    fn parseTypeSizeExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Type Size Expression", .{}, .{ .module = .Parser });
        const type_size_keyword = (try self.consumeKind(.TypeSize, "Expect type_size keyword")).?;
        _ = type_size_keyword;
        try self.assertKind(.OpenParen, "Expect ( after type_size keyword");
        const type_ = try self.parseType();
        try self.assertKind(.CloseParen, "Expect ) after type_size type");
        return self.allocReturn(ast.Expression, ast.Expression{ .type_size_expression = ast.TypeSizeExpression.init(type_) });
    }

    fn parseTypeAlignExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Type Align Expression", .{}, .{ .module = .Parser });
        const type_align_keyword = (try self.consumeKind(.TypeAlign, "Expect type_align keyword")).?;
        _ = type_align_keyword;
        try self.assertKind(.OpenParen, "Expect ( after type_align keyword");
        const type_ = try self.parseType();
        try self.assertKind(.CloseParen, "Expect ) after type_align type");
        return self.allocReturn(ast.Expression, ast.Expression{ .type_align_expression = ast.TypeAlignExpression.init(type_) });
    }

    fn parseValueSizeExpression(self: *Self) Error!*ast.Expression {
        log("Parsing Value Size Expression", .{}, .{ .module = .Parser });
        const value_size_keyword = (try self.consumeKind(.ValueSize, "Expect value_size keyword")).?;
        _ = value_size_keyword;
        try self.assertKind(.OpenParen, "Expect ( after value_size keyword");
        const value = try self.parseExpression();
        try self.assertKind(.CloseParen, "Expect ) after value_size type");
        return self.allocReturn(ast.Expression, ast.Expression{ .value_size_expression = ast.ValueSizeExpression.init(value) });
    }

    fn parseGenericArgumentsIfExists(self: *Self) !std.ArrayList(*Type) {
        log("Parsing Generic Arguments If Exists", .{}, .{ .module = .Parser });
        var generic_arguments = std.ArrayList(*Type).init(self.allocator);
        if (self.isCurrentKind(.Smaller)) {
            _ = try self.advancedToken();
            while (!self.isCurrentKind(.Greater)) {
                try generic_arguments.append(try self.parseType());
                if (self.isCurrentKind(.Comma)) {
                    _ = try self.advancedToken();
                } else {
                    break;
                }
            }

            try self.assertKind(.Greater, "Expect > after generic arguments types");
        }

        return generic_arguments;
    }

    fn parseSwitchOperator(self: *Self) !TokenKind {
        log("Parsing Switch Operator", .{}, .{ .module = .Parser });
        if (self.isCurrentKind(.Comma)) {
            _ = try self.advancedToken();
            const op_token = try self.peekAndAdvanceToken();
            const op_kind = op_token.kind;
            if (!tokenizer.comparisonsOperators(op_kind)) {
                try self.context.diagnostics.reportError(op_token.position, "Switch operator must be a comparions operators only");
                return Error.ParsingError;
            }

            return op_kind;
        }

        return .EqualEqual;
    }

    fn checkGenericParameterName(self: *Self, name: Token) !void {
        log("Checking Generic parameter Name", .{}, .{ .module = .Parser });
        const literal = name.literal;
        const position = name.position;

        // Check tht parameter name is not a built in primitive type
        if (primitiveTypes(literal) != null) {
            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "primitives type can't be used as generic parameter name '{s}'", .{literal}));
            return Error.ParsingError;
        }

        // Mke sure this name is not a struct name
        if (self.context.structures.contains(literal)) {
            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Struct name can't be used as generic parameter name '{s}'", .{literal}));
            return Error.ParsingError;
        }

        // Mke sure this name is not an enum name
        if (self.context.enumerations.contains(literal)) {
            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "Enum name can't be used as generic parameter name '{s}'", .{literal}));
            return Error.ParsingError;
        }

        // Mke sure this name is unique and no alias use it
        if (self.context.type_alias_table.contains(literal)) {
            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "You can't use alias as generic parameter name '{s}'", .{literal}));
            return Error.ParsingError;
        }

        // Mke sure this generic parameter type is unique in this node
        self.generic_parameter_names.put(literal, {}) catch {
            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "You already declared generic parameter with name '{s}'", .{literal}));
            return Error.ParsingError;
        };
    }

    fn checkFunctionKindParametersCount(self: *Self, kind: FunctionKind, count: u32, span: TokenSpan) !void {
        log("Checking Function Kind parameters Count", .{}, .{ .module = .Parser });
        if (kind == .Prefix and count != 1) {
            try self.context.diagnostics.reportError(span, "Prefix function must have exactly one parameter");
            return Error.ParsingError;
        }

        if (kind == .Infix and count != 2) {
            try self.context.diagnostics.reportError(span, "Infix function must have exactly Two parameter");
            return Error.ParsingError;
        }

        if (kind == .Postfix and count != 1) {
            try self.context.diagnostics.reportError(span, "Postfix function must have exactly one parameter");
            return Error.ParsingError;
        }
    }

    fn checkCompiletimeconstantsExpression(self: *Self, expression: *ast.Expression, position: TokenSpan) !void {
        log("Checking Compiletime constants Expression", .{}, .{ .module = .Parser });
        const ast_node_type = expression.getAstNodeType();

        // Now we just check tht the value is primitive but later must allow more types
        if (ast_node_type == ast.AstNodeType.Character or ast_node_type == ast.AstNodeType.String or ast_node_type == ast.AstNodeType.Number or ast_node_type == ast.AstNodeType.Bool) {
            return;
        }

        // llow negative number and later should allow prefix unary with constants right
        if (ast_node_type == ast.AstNodeType.PrefixUnary) {
            const prefix_unary = expression.prefix_unary_expression;
            if (prefix_unary.right.getAstNodeType() == ast.AstNodeType.Number and prefix_unary.operator_token.kind == TokenKind.Minus) {
                return;
            }
        }

        try self.context.diagnostics.reportError(position, "Value must be a compile time constants");
        return Error.ParsingError;
    }

    fn unexpectedTokenError(self: *Self) !*ast.Expression {
        log("Unexpected Token Error", .{}, .{ .module = .Parser });
        const current_token = self.peekCurrent();
        const position = current_token.position;
        const token_literal = tokenizer.tokenKindLiteral(current_token.kind);

        // Specil error message for using undefined value in wrong place
        if (self.isCurrentKind(.Undefined)) {
            try self.context.diagnostics.reportError(position, "`---` used only in variable declaraion to represent an undefined value");
            return Error.ParsingError;
        }

        // Check if its  two tokens operators with space in the middle
        for (tokenizer.TwoTokensOperators) |two_tokens_op| {
            if (self.isPreviousKind(two_tokens_op.first) and self.isCurrentKind(two_tokens_op.second)) {
                const unexpected = tokenizer.tokenKindLiteral(two_tokens_op.second);
                const correct = tokenizer.tokenKindLiteral(two_tokens_op.both);
                const message = try std.fmt.allocPrint(self.allocator, "unexpected '{s}', do you means '{s}'", .{ unexpected, correct });
                try self.context.diagnostics.reportError(position, message);
                return Error.ParsingError;
            }
        }

        try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "expected expression, found '{s}'", .{token_literal}));
        return Error.ParsingError;
    }

    fn checkUnnecessarySemicolonWarning(self: *Self) !void {
        log("Checking Unnecessry Semicolon Warning", .{}, .{ .module = .Parser });
        if (self.isCurrentKind(.Semicolon)) {
            const semicolon = try self.peekAndAdvanceToken();
            if (self.context.options.should_report_warns) {
                try self.context.diagnostics.reportWarning(semicolon.position, "remove unnecessary semicolon");
            }
        }
    }

    fn getNumberKind(self: *Self, token: TokenKind) !types.NumberKind {
        log("Getting Number Kind", .{}, .{ .module = .Parser });
        switch (token) {
            .Int => return .Integer64,
            .Int1 => return .Integer1,
            .Int8 => return .Integer8,
            .Int16 => return .Integer16,
            .Int32 => return .Integer32,
            .Int64 => return .Integer64,
            .Uint8 => return .UInteger8,
            .Uint16 => return .UInteger16,
            .Uint32 => return .UInteger32,
            .Uint64 => return .UInteger64,
            .Float => return .Float64,
            .Float32 => return .Float32,
            .Float64 => return .Float64,
            else => {
                try self.context.diagnostics.reportError(self.peekCurrent().position, "Token kind is not a number");
                return Error.ParsingError;
            },
        }
    }

    fn isFunctionDeclarationKind(self: *Self, literal: []const u8, kind: FunctionKind) bool {
        log("Is Function Declration Kind", .{}, .{ .module = .Parser });
        if (self.context.functions.contains(literal)) {
            return self.context.functions.get(literal) == kind;
        }

        return false;
    }

    fn isValidIntrinsicName(self: *Self, name: Token) bool {
        _ = self;
        log("Is Valid Intrinsic Name", .{}, .{ .module = .Parser });
        if (name.literal.len == 0) {
            return false;
        }
        if (ds.contains(u8, name.literal, ' ')) {
            return false;
        }

        return true;
    }

    fn resolveFieldSelfReference(self: *Self, field_type: *Type, current_struct_ptr_type: *types.PointerType) !*Type {
        log("Resolving Field Self Reference", .{}, .{ .module = .Parser });
        if (field_type.typeKind() == .Pointer) {
            var pointer_type = field_type.Pointer;
            if (pointer_type.base_type.typeKind() == .None) {
                self.current_struct_unknown_fields -= 1;
                return self.allocReturn(Type, Type{ .Pointer = current_struct_ptr_type.* });
            }

            pointer_type.base_type = try self.resolveFieldSelfReference(pointer_type.base_type, current_struct_ptr_type);
            return self.allocReturn(Type, Type{ .Pointer = pointer_type });
        }

        if (field_type.typeKind() == .StaticArray) {
            var array_type = field_type.StaticArray;
            array_type.element_type = try self.resolveFieldSelfReference(array_type.element_type.?, current_struct_ptr_type);
            return self.allocReturn(Type, Type{ .StaticArray = array_type });
        }

        if (field_type.typeKind() == .Function) {
            var function_type = field_type.Function;
            function_type.return_type = try self.resolveFieldSelfReference(function_type.return_type, current_struct_ptr_type);
            const size = function_type.parameters.items.len;
            for (0..size) |i| {
                function_type.parameters.items[i] = try self.resolveFieldSelfReference(function_type.parameters.items[i], current_struct_ptr_type);
            }

            return self.allocReturn(Type, Type{ .Function = function_type });
        }

        if (field_type.typeKind() == .Tuple) {
            const tuple_type = field_type.Tuple;
            for (tuple_type.field_types.items) |*field| {
                field.* = try self.resolveFieldSelfReference(field.*, current_struct_ptr_type);
            }

            return self.allocReturn(Type, Type{ .Tuple = tuple_type });
        }

        return field_type;
    }

    fn advancedToken(self: *Self) !void {
        const scanned_token = try self.tokenizer.scanNextToken();

        if (scanned_token.kind == .Invalid) {
            try self.context.diagnostics.reportError(scanned_token.position, scanned_token.literal);
            return Error.ParsingError;
        }

        self.previous_token = self.current_token;
        self.current_token = self.next_token;
        self.next_token = scanned_token;
    }

    fn peekAndAdvanceToken(self: *Self) !Token {
        const current = self.peekCurrent();
        _ = try self.advancedToken();
        return current;
    }

    fn peekCurrent(self: *Self) Token {
        return self.current_token.?;
    }

    fn peekNext(self: *Self) Token {
        return self.next_token.?;
    }

    fn peekPrevious(self: *Self) Token {
        return self.previous_token.?;
    }

    fn isCurrentKind(self: *Self, kind: TokenKind) bool {
        return self.peekCurrent().kind == kind;
    }

    fn isNextKind(self: *Self, kind: TokenKind) bool {
        return self.peekNext().kind == kind;
    }

    fn isPreviousKind(self: *Self, kind: TokenKind) bool {
        return self.peekPrevious().kind == kind;
    }

    fn consumeKind(self: *Self, kind: TokenKind, message: []const u8) !?Token {
        if (self.isCurrentKind(kind)) {
            _ = try self.advancedToken();
            return self.previous_token;
        }

        try self.context.diagnostics.reportError(self.peekCurrent().position, message);
        return Error.ParsingError;
    }

    fn assertKind(self: *Self, kind: TokenKind, message: []const u8) !void {
        log("Asserting Kind: {any}, {s}", .{ kind, message }, .{ .module = .Parser });
        if (self.isCurrentKind(kind)) {
            _ = try self.advancedToken();
            return;
        }
        var location = self.peekCurrent().position;
        if (kind == .Semicolon) {
            location = self.peekPrevious().position;
        }
        try self.context.diagnostics.reportError(location, message);
        return Error.ParsingError;
    }

    fn isRightShiftOperator(self: *Self, first: Token, second: Token) bool {
        _ = self;
        if (first.kind == TokenKind.Greater and second.kind == TokenKind.Greater) {
            const first_position = first.position;
            const second_position = second.position;
            return (first_position.line_number == second_position.line_number) and (first_position.column_end + 1 == second_position.column_start);
        }

        return false;
    }

    fn isSourceAvailable(self: *Self) bool {
        return self.peekCurrent().kind != .EndOfFile;
    }

    fn parseType(self: *Self) Error!*types.Type {
        log("Parsing Type", .{}, .{ .module = .Parser });
        if (self.isCurrentKind(.At)) {
            return try self.parseTypesDirective();
        }

        return self.parseTypeWithPrefix();
    }

    fn parseTypeWithPrefix(self: *Self) Error!*types.Type {
        log("Parsing Type With Prefix", .{}, .{ .module = .Parser });
        if (self.isCurrentKind(.Fun)) {
            return try self.parseFunctionPtrType();
        }

        if (self.isCurrentKind(.Star)) {
            return try self.parsePointerToType();
        }

        if (self.isCurrentKind(.OpenParen)) {
            return try self.parseTupleType();
        }

        if (self.isCurrentKind(.OpenBracket)) {
            return try self.parseFixedSizeArrayType();
        }

        return self.parseTypeWithPostfix();
    }

    fn parsePointerToType(self: *Self) Error!*Type {
        log("Parsing Pointer To Type", .{}, .{ .module = .Parser });
        try self.assertKind(.Star, "Pointer type must be started with *");
        return self.allocReturn(types.Type, Type{ .Pointer = types.PointerType.init(try self.parseTypeWithPrefix()) });
    }

    fn parseFunctionPtrType(self: *Self) Error!*Type {
        log("Parsing function pointer type", .{}, .{ .module = .Parser });
        try self.assertKind(.Fun, "Expect fun keyword at the start of function ptr");
        const paren = self.peekCurrent();
        const parameters_types = try self.parseListOfTypes();
        const return_type = try self.parseType();
        const function_type = try self.allocReturn(types.Type, Type{ .Function = types.FunctionType.init(
            paren,
            parameters_types,
            return_type,
            false,
            null,
            false,
            false,
            std.ArrayList([]const u8).init(self.allocator),
        ) });
        return self.allocReturn(types.Type, Type{ .Pointer = types.PointerType.init(function_type) });
    }

    fn parseTupleType(self: *Self) Error!*Type {
        log("Parsing tuple type", .{}, .{ .module = .Parser });
        const paren = self.peekCurrent();
        const field_types = try self.parseListOfTypes();

        if (field_types.items.len < 2) {
            try self.context.diagnostics.reportError(paren.position, "Tuple type must has at least 2 types");
            return Error.ParsingError;
        }

        var tuple_type = try self.allocReturn(types.Type, Type{ .Tuple = types.TupleType.init(paren.literal, field_types) });
        tuple_type.Tuple.name = try types.mangleTupleType(self.allocator, &tuple_type.Tuple);

        return tuple_type;
    }

    fn parseListOfTypes(self: *Self) !std.ArrayList(*Type) {
        log("Parsing List of Types", .{}, .{ .module = .Parser });
        try self.assertKind(.OpenParen, "Expect ( before types");
        var types_list = std.ArrayList(*Type).init(self.allocator);

        while (!self.isCurrentKind(.CloseParen)) {
            try types_list.append(try self.parseType());
            if (self.isCurrentKind(.Comma)) {
                _ = try self.advancedToken();
            } else {
                break;
            }
        }

        try self.assertKind(.CloseParen, "Expect ) after types");
        return types_list;
    }

    fn parseFixedSizeArrayType(self: *Self) Error!*Type {
        log("Parsing Fixed Size Array Type", .{}, .{ .module = .Parser });
        try self.assertKind(.OpenBracket, "Expect [ for fixed size array type");

        if (self.isCurrentKind(.CloseBracket)) {
            try self.context.diagnostics.reportError(self.peekCurrent().position, "Fixed array type must have implicit size [n]");
            return Error.ParsingError;
        }

        const size_expression = try self.parseExpression();
        if (size_expression.getAstNodeType() != ast.AstNodeType.Number) {
            try self.context.diagnostics.reportError(self.peekCurrent().position, "Array size must be an integer constants");
            return Error.ParsingError;
        }

        const size = size_expression; //.number_expression;
        if (!types.isIntegerType(size.getTypeNode().?)) {
            try self.context.diagnostics.reportError(self.peekCurrent().position, "Array size must be an integer constants");
            return Error.ParsingError;
        }

        try self.assertKind(.CloseBracket, "Expect ] after array size");
        const element_type = try self.parseType();

        // Check if rray element type is not void
        if (element_type.typeKind() == .Void) {
            try self.context.diagnostics.reportError(self.peekCurrent().position, "Can't declare array with incomplete type 'void'");
            return Error.ParsingError;
        }
        const number_value = try std.fmt.parseInt(u32, size.number_expression.value.literal, 10);
        return self.allocReturn(types.Type, Type{ .StaticArray = types.StaticArrayType.init(element_type, number_value, null) });
    }

    fn parseTypeWithPostfix(self: *Self) Error!*Type {
        log("Parsing type with postfix", .{}, .{ .module = .Parser });
        const type_ = try self.parseGenericStructType();

        // Report useful message when user create pointer type with prefix `*` like in C
        if (self.isCurrentKind(.String)) {
            try self.context.diagnostics.reportError(self.peekPrevious().position, try std.fmt.allocPrint(self.allocator, "In pointer type `*` must be before the type like *{s}", .{try types.getTypeLiteral(self.allocator, type_)}));
            return Error.ParsingError;
        }

        return type_;
    }

    fn parseGenericStructType(self: *Self) Error!*Type {
        log("Parsing Generic Struct Type", .{}, .{ .module = .Parser });
        var type_ = try self.parsePrimaryType();

        // parse generic struct type with types parameters
        if (self.isCurrentKind(.Smaller)) {
            if (type_.typeKind() == .Struct) {
                const smaller_token = self.peekCurrent();
                const struct_type = type_.Struct;

                // Prevent use non generic struct type with ny type parameters
                if (!struct_type.is_generic) {
                    try self.context.diagnostics.reportError(smaller_token.position, "Non generic struct type don't accept any types parameters");
                    return Error.ParsingError;
                }

                const generic_parameters = try self.parseGenericArgumentsIfExists();

                // Mke sure generic struct types is used with correct number of parameters
                if (struct_type.generic_parameters.items.len != generic_parameters.items.len) {
                    try self.context.diagnostics.reportError(smaller_token.position, try std.fmt.allocPrint(self.allocator, "Invalid number of generic parameters expect {d} but got {d}", .{ struct_type.generic_parameters.items.len, generic_parameters.items.len }));
                    return Error.ParsingError;
                }

                return self.allocReturn(Type, Type{ .GenericStruct = types.GenericStructType{ .struct_type = try self.allocReturn(types.StructType, struct_type), .parameters = generic_parameters } });
            }

            try self.context.diagnostics.reportError(self.peekPrevious().position, "Only structures can accept generic parameters");
            return Error.ParsingError;
        }

        // ssert that generic structs types must be created with parameters types
        if (type_.typeKind() == .Struct) {
            const struct_type = type_.Struct;
            if (struct_type.is_generic) {
                const struct_name = self.peekPrevious();
                try self.context.diagnostics.reportError(struct_name.position, try std.fmt.allocPrint(self.allocator, "Generic struct type must be used with parameters types '{s}<..>'", .{struct_name.literal}));
                return Error.ParsingError;
            }
        }

        return type_;
    }

    fn parsePrimaryType(self: *Self) Error!*Type {
        log("Parsing Primary Type", .{}, .{ .module = .Parser });
        if (self.isCurrentKind(.Identifier)) {
            return self.parseIdentifierType();
        }

        // Show helpful dignostic error message for varargs case
        if (self.isCurrentKind(.Varargs)) {
            try self.context.diagnostics.reportError(self.peekCurrent().position, "Varargs not supported as function pointer parameter");
            return Error.ParsingError;
        }

        try self.context.diagnostics.reportError(self.peekCurrent().position, "Expected type name");
        return Error.ParsingError;
    }

    fn parseIdentifierType(self: *Self) Error!*Type {
        log("Parsing Identifier Type", .{}, .{ .module = .Parser });
        const symbol_token = (try self.consumeKind(.Identifier, "Expect identifier s type")).?;
        const type_literal = symbol_token.literal;

        // Check if this time is primitive
        if (primitiveTypes(type_literal)) |primitive_type| {
            return primitive_type;
        }

        // Check if this type is structure type
        if (self.context.structures.get(type_literal)) |struct_type| {
            return self.allocReturn(types.Type, types.Type{ .Struct = struct_type.* });
        }

        // Check if this type is enumertion type
        if (self.context.enumerations.get(type_literal)) |enum_type| {
            return self.allocReturn(types.Type, types.Type{ .EnumElement = types.EnumElementType.init(symbol_token.literal, enum_type.element_type.?) });
        }

        // Struct with field tht has his type for example LinkedList Node struct
        // Current mrk it un solved then solve it after building the struct type itself
        if (std.mem.eql(u8, type_literal, self.current_struct_name)) {
            self.current_struct_unknown_fields += 1;
            return self.allocReturn(types.Type, Type{ .None = types.NoneType{} });
        }

        // Check if this is  it generic type parameter
        if (self.generic_parameter_names.contains(type_literal)) {
            return self.allocReturn(types.Type, Type{ .GenericParameter = types.GenericParameterType.init(type_literal) });
        }

        // Check if this identifier is  type alias key
        if (self.context.type_alias_table.contains(type_literal)) {
            return self.context.type_alias_table.resolveAlias(type_literal);
        }

        // This type is not permitive, structure or enumerations
        try self.context.diagnostics.reportError(symbol_token.position, try std.fmt.allocPrint(self.allocator, "Cannot find type '{s}'", .{type_literal}));
        return Error.ParsingError;
    }

    fn parseDeclarationsDirective(self: *Self) Error!*ast.Statement {
        log("Parsing Declarations Directive", .{}, .{ .module = .Parser });
        const hash_token = (try self.consumeKind(.At, "Expect @ before directive name")).?;
        const position = hash_token.position;

        if (self.isCurrentKind(.Identifier)) {
            const directive = self.peekCurrent();
            const directive_name = directive.literal;

            if (std.mem.eql(u8, directive_name, "intrinsic")) {
                return try self.parseIntrinsicPrototype();
            }

            if (std.mem.eql(u8, directive_name, "extern")) {
                // parse opaque struct
                if (self.isNextKind(.Struct)) {
                    _ = try self.advancedToken();
                    return try self.parseStructureDeclaration(false, true);
                }

                return try self.parseFunctionPrototype(.Normal, true);
            }

            if (std.mem.eql(u8, directive_name, "prefix")) {
                const token = try self.peekAndAdvanceToken();
                const call_kind = FunctionKind.Prefix;
                if (self.isCurrentKind(.Fun)) {
                    return try self.parseFunctionDeclaration(call_kind);
                }

                if (self.isCurrentKind(.Operator)) {
                    return try self.parseOperatorFunctionDeclaration(call_kind);
                }

                try self.context.diagnostics.reportError(token.position, "prefix keyword used only for function and operators");
                return Error.ParsingError;
            }

            if (std.mem.eql(u8, directive_name, "infix")) {
                const token = try self.peekAndAdvanceToken();
                const call_kind = FunctionKind.Infix;
                if (self.isCurrentKind(.Fun)) {
                    return try self.parseFunctionDeclaration(call_kind);
                }

                // Operator functions are infix by default but also it not a syntax error
                if (self.isCurrentKind(.Operator)) {
                    return try self.parseOperatorFunctionDeclaration(call_kind);
                }

                try self.context.diagnostics.reportError(token.position, "infix keyword used only for function and operators");
                return Error.ParsingError;
            }

            if (std.mem.eql(u8, directive_name, "postfix")) {
                const token = try self.peekAndAdvanceToken();
                const call_kind = FunctionKind.Postfix;
                if (self.isCurrentKind(.Fun)) {
                    return try self.parseFunctionDeclaration(call_kind);
                }

                if (self.isCurrentKind(.Operator)) {
                    return try self.parseOperatorFunctionDeclaration(call_kind);
                }

                try self.context.diagnostics.reportError(token.position, "postfix keyword used only for function and operators");
                return Error.ParsingError;
            }

            if (std.mem.eql(u8, directive_name, "packed")) {
                _ = try self.advancedToken();
                return try self.parseStructureDeclaration(true, false);
            }

            try self.context.diagnostics.reportError(position, try std.fmt.allocPrint(self.allocator, "No declarations directive with name '{s}'", .{directive_name}));
            return Error.ParsingError;
        }
        try self.context.diagnostics.reportError(position, "Expected identifier as directive name");
        return Error.ParsingError;
    }

    fn parseStatementsDirective(self: *Self) Error!*ast.Statement {
        log("Parsing Statements Directive", .{}, .{ .module = .Parser });
        try self.assertKind(.At, "Expect @ before directive name");
        const directive = (try self.consumeKind(.Identifier, "Expect symbol s directive name")).?;
        const directive_name = directive.literal;

        if (std.mem.eql(u8, directive_name, "complete")) {
            const statement = try self.parseStatement();
            if (statement.getAstNodeType() != .SwitchStatement) {
                try self.context.diagnostics.reportError(directive.position, "@complete expect switch statement");
                return Error.ParsingError;
            }

            var switch_node = statement.switch_statement;
            switch_node.should_perform_complete_check = true;
            return self.allocReturn(ast.Statement, ast.Statement{ .switch_statement = switch_node });
        }

        try self.context.diagnostics.reportError(directive.position, try std.fmt.allocPrint(self.allocator, "No statement directive with name '{s}'", .{directive_name}));
        return Error.ParsingError;
    }

    fn parseExpressionsDirective(self: *Self) Error!*ast.Expression {
        log("Parsing Expressions Directive", .{}, .{ .module = .Parser });
        try self.assertKind(.At, "Expect @ before directive name");
        const directive = (try self.consumeKind(.Identifier, "Expect symbol s directive name")).?;
        const directive_name = directive.literal;

        if (std.mem.eql(u8, directive_name, "line")) {
            const current_line = self.peekPrevious().position.line_number;
            const directive_token = Token{
                .kind = .Int64,
                .literal = try std.fmt.allocPrint(self.allocator, "{d}", .{current_line}),
                .position = directive.position,
            };
            return self.allocReturn(ast.Expression, ast.Expression{ .number_expression = ast.NumberExpression.init(directive_token, @constCast(&Type.I64_TYPE)) });
        }

        if (std.mem.eql(u8, directive_name, "column")) {
            const current_column = self.peekPrevious().position.column_start;
            const directive_token = Token{
                .kind = .Int64,
                .literal = try std.fmt.allocPrint(self.allocator, "{d}", .{current_column}),
                .position = directive.position,
            };
            return self.allocReturn(ast.Expression, ast.Expression{ .number_expression = ast.NumberExpression.init(directive_token, @constCast(&Type.I64_TYPE)) });
        }

        if (std.mem.eql(u8, directive_name, "filepath")) {
            const current_filepath = self.context.source_manager.resolveSourcePath(self.peekPrevious().position.file_id).?;
            const directive_token = Token{
                .kind = .String,
                .literal = current_filepath,
                .position = directive.position,
            };
            return self.allocReturn(ast.Expression, ast.Expression{ .string_expression = ast.StringExpression.init(directive_token) });
        }

        if (std.mem.eql(u8, directive_name, "vec")) {
            const expression = try self.parseExpression();
            if (expression.getAstNodeType() != .Array) {
                try self.context.diagnostics.reportError(self.peekPrevious().position, "Expect Array expression after @vec");
                return Error.ParsingError;
            }

            const array = try self.allocReturn(ast.ArrayExpression, expression.array_expression);
            return self.allocReturn(ast.Expression, ast.Expression{ .vector_expression = ast.VectorExpression.init(self.allocator, array) });
        }

        if (std.mem.eql(u8, directive_name, "max_value")) {
            try self.assertKind(.OpenParen, "Expect ( after @max_value");
            const type_ = try self.parseType();
            try self.assertKind(.CloseParen, "Expect ) after @max_value type");

            if (type_.typeKind() != .Number) {
                try self.context.diagnostics.reportError(self.peekPrevious().position, "@max_value expect only number types");
                return Error.ParsingError;
            }

            const number_type = type_.Number;
            var max_value = Token{
                .kind = types.numberKindTokenKind(number_type.number_kind),
                .literal = "0",
                .position = self.peekPrevious().position,
            };
            if (types.isIntegerType(type_)) {
                max_value.literal = try std.fmt.allocPrint(self.allocator, "{d}", .{types.integersKindMaxValue(number_type.number_kind)});
            } else {
                if (number_type.number_kind == types.NumberKind.Float32) {
                    max_value.literal = try std.fmt.allocPrint(self.allocator, "{any}", .{std.math.floatMax(f32)});
                } else {
                    max_value.literal = try std.fmt.allocPrint(self.allocator, "{any}", .{std.math.floatMax(f64)});
                }
            }

            return self.allocReturn(ast.Expression, ast.Expression{ .number_expression = ast.NumberExpression.init(max_value, type_) });
        }

        if (std.mem.eql(u8, directive_name, "min_value")) {
            try self.assertKind(.OpenParen, "Expect ( after @min_value");
            const type_ = try self.parseType();
            try self.assertKind(.CloseParen, "Expect ) after @min_value type");

            if (type_.typeKind() != .Number) {
                try self.context.diagnostics.reportError(self.peekPrevious().position, "@min_value expect only number types");
                return Error.ParsingError;
            }

            const number_type = type_.Number;

            const kind = types.numberKindTokenKind(number_type.number_kind);
            var min_value = Token{
                .kind = kind,
                .literal = "0",
                .position = self.peekPrevious().position,
            };

            if (types.isIntegerType(type_)) {
                min_value.literal = try std.fmt.allocPrint(self.allocator, "{d}", .{types.integersKindMinValue(number_type.number_kind)});
            } else {
                if (number_type.number_kind == .Float32) {
                    min_value.literal = try std.fmt.allocPrint(self.allocator, "-{any}", .{std.math.floatMin(f32)});
                } else {
                    min_value.literal = try std.fmt.allocPrint(self.allocator, "-{any}", .{std.math.floatMin(f64)});
                }
            }

            return self.allocReturn(ast.Expression, ast.Expression{ .number_expression = ast.NumberExpression.init(min_value, type_) });
        }

        if (std.mem.eql(u8, directive_name, "infinity32")) {
            return self.allocReturn(ast.Expression, ast.Expression{ .infinity_expression = ast.InfinityExpression.init(@constCast(&Type.F32_TYPE)) });
        }

        if (std.mem.eql(u8, directive_name, "infinity") or std.mem.eql(u8, directive_name, "infinity64")) {
            return self.allocReturn(ast.Expression, ast.Expression{ .infinity_expression = ast.InfinityExpression.init(@constCast(&Type.F64_TYPE)) });
        }

        try self.context.diagnostics.reportError(directive.position, try std.fmt.allocPrint(self.allocator, "No expression directive with name '{s}'", .{directive_name}));

        return Error.ParsingError;
    }

    fn parseTypesDirective(self: *Self) Error!*types.Type {
        log("Parsing Types Directive", .{}, .{ .module = .Parser });
        try self.assertKind(.At, "Expect @ before directive name");
        const directive = (try self.consumeKind(.Identifier, "Expect symbol s directive name")).?;
        const directive_name = directive.literal;

        if (std.mem.eql(u8, directive_name, "vec")) {
            const type_ = try self.parseType();
            if (type_.typeKind() != .StaticArray) {
                try self.context.diagnostics.reportError(self.peekPrevious().position, "Expect array type after @vec");
                return Error.ParsingError;
            }

            // var array_type = type_.StaticArray;
            const array_type = try self.allocReturn(types.StaticArrayType, type_.StaticArray);
            return self.allocReturn(types.Type, types.Type{ .StaticVector = types.StaticVectorType.init(array_type) });
        }

        try self.context.diagnostics.reportError(directive.position, try std.fmt.allocPrint(self.allocator, "No types directive with name '{s}'", .{directive_name}));
        return Error.ParsingError;
    }
};
