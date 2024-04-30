const std = @import("std");
const ast = @import("ast.zig");
const print = std.debug.print;
const tokenizer = @import("tokenizer.zig");
const types = @import("types.zig");
const log = @import("diagnostics.zig").log;

fn generateType(type_a: ?*const types.Type) void {
    if (type_a) |type_| {
        switch (type_.*) {
            .Number => print("{s}", .{types.getNumberKindLiteral(type_.Number.number_kind)}),
            .Pointer => {
                print("*", .{});
                generateType(type_.Pointer.base_type);
            },
            .Void => print("void", .{}),
            .Function => |*x| generateFunctionType(x),
            .StaticArray => {
                print("[{d}]", .{type_.StaticArray.size});
                generateType(type_.StaticArray.element_type);
            },
            .StaticVector => |*x| {
                print("@vec", .{});
                generateType(&types.Type{ .StaticArray = x.array.* });
            },
            .GenericParameter => |*x| {
                print("{s}", .{x.name});
            },
            else => {
                std.log.err("Unknown type: {any}", .{@TypeOf(type_)});
            },
        }
    } else {
        print("Any", .{});
    }
}

fn generateFunctionType(type_: *const types.FunctionType) void {
    print("fun (", .{});
    for (type_.parameters.items) |parameter| {
        generateType(parameter);
        if (parameter != type_.parameters.items[type_.parameters.items.len - 1] or type_.has_varargs) {
            print(", ", .{});
        }
    }
    if (type_.has_varargs) {
        print("varargs ", .{});
        generateType(type_.varargs_type);
    }
    print(") ", .{});
    generateType(type_.return_type);
}

fn indent(space: u32) void {
    for (0..space) |_| {
        print("  ", .{});
    }
}

fn generateStatement(statement: *const ast.Statement, space: u32) void {
    switch (statement.*) {
        .block_statement => {},
        else => {
            indent(space);
        },
    }
    switch (statement.*) {
        .function_prototype => |*x| generateFunctionPrototype(x),
        .function_declaration => |*x| {
            generateFunctionDeclaration(x);
            return;
        },
        .expression_statement => |*x| generateExpressionStatement(x),
        .enum_declaration => |*x| generateEnumDeclaration(x),
        .field_declaration => |*x| generateFieldDeclaration(x),
        .block_statement => |*x| {
            print("{{\n", .{});
            for (x.statements.items) |stmt| {
                generateStatement(stmt, space + 1);
            }
            indent(space - 1);
            print("}}", .{});
        },
        .return_statement => |*x| generateReturnStatement(x),
        .if_statement => |*x| {
            generateIfStatement(x, space + 1);
            return;
        },
        .while_statement => |*x| {
            print("while (", .{});
            generateExpression(x.condition);
            print(") ", .{});
            generateStatement(x.body, space + 1);
            return;
        },
        .continue_statement => {
            print("continue", .{});
        },
        .break_statement => {
            print("break", .{});
        },
        .const_declaration => |*x| {
            print("const {s} = ", .{x.name.literal});
            generateExpression(x.value);
        },
        .defer_statement => |*x| {
            print("defer ", .{});
            generateExpression(x.call_expression);
        },
        .for_range_statement => |*x| generateForRangeStatement(x, space),
        .for_each_statement => |*x| {
            print("for (", .{});
            generateExpression(x.collection);
            print(") ", .{});
            generateStatement(x.body, space + 1);
        },
        .for_ever_statement => |*x| {
            print("for ", .{});
            generateStatement(x.body, space + 1);
        },

        else => {
            std.log.err("Unknown statement type: {any}", .{@TypeOf(statement)});
        },
    }
    print(";\n", .{});
}

fn generateForRangeStatement(statement: *const ast.ForRangeStatement, space: u32) void {
    print("for (", .{});
    generateExpression(statement.range_start);
    print(" .. ", .{});
    generateExpression(statement.range_end);
    if (statement.step) |step| {
        print(" : ", .{});
        generateExpression(step);
    }
    print(") ", .{});
    generateStatement(statement.body, space + 1);
}

fn generateIfStatement(statement: *const ast.IfStatement, space: u32) void {
    var i: u32 = 0;
    for (statement.conditional_blocks.items) |block| {
        if (i == 0) {
            print(" if (", .{});
        } else {
            indent(space);
            print("else if (", .{});
        }
        generateExpression(block.condition);
        print(") ", .{});
        generateStatement(block.body, space + 1);
        i += 1;
    }
}

fn generateFieldDeclaration(declaration: *const ast.FieldDeclaration) void {
    print("var {s} ", .{declaration.name.literal});
    if (declaration.has_explicit_type) {
        print(": ", .{});
        generateType(declaration.field_type);
    }
    if (declaration.value) |value| {
        print(" = ", .{});
        generateExpression(value);
    }
}

fn generateEnumDeclaration(declaration: *const ast.EnumDeclaration) void {
    print("enum {s} {{\n", .{declaration.name.literal});
    for (declaration.enum_type.Enum.values.keys()) |member| {
        print("    {s},\n", .{member});
    }
    print("}}", .{});
}

fn generateReturnStatement(statement: *const ast.ReturnStatement) void {
    print("return ", .{});
    if (statement.has_value) {
        generateExpression(statement.value.?);
    }
}

fn generateExpressionStatement(statement: *const ast.ExpressionStatement) void {
    generateExpression(statement.expression);
}

fn generateExpression(expression: *const ast.Expression) void {
    switch (expression.*) {
        .call_expression => |*x| generateCallExpression(x),
        .literal_expression => |*x| generateLiteralExpression(x),
        .string_expression => |*x| {
            const value = std.mem.replaceOwned(u8, std.heap.page_allocator, x.value.literal, "\n", "\\n") catch unreachable;
            print("\"{s}\"", .{value});
        },
        .number_expression => |*x| print("{s}", .{x.value.literal}),
        .binary_expression => |*x| generateBinaryExpression(x),
        .bool_expression => |*x| print("{s}", .{x.value.literal}),
        .if_expression => |*x| {
            generateIfExpression(x);
        },
        .assign_expression => |*x| {
            generateExpression(x.left);
            print(" = ", .{});
            generateExpression(x.right);
        },
        .comparison_expression => |*x| {
            generateExpression(x.left);
            print(" {s} ", .{tokenizer.tokenKindLiteral(x.operator_token.kind)});
            generateExpression(x.right);
        },
        .logical_expression => |*x| {
            generateExpression(x.left);
            print(" {s} ", .{tokenizer.tokenKindLiteral(x.operator_token.kind)});
            generateExpression(x.right);
        },
        .index_expression => |*x| {
            generateExpression(x.index);
            print("[", .{});
            generateExpression(x.value);
            print("]", .{});
        },
        .switch_expression => |*x| {
            print("switch (", .{});
            generateExpression(x.argument);
            print(") {{\n", .{});
            for (0..x.switch_cases.items.len) |i| {
                generateExpression(x.switch_cases.items[i]);
                print("->", .{});
                generateExpression(x.switch_case_values.items[i]);
                print(";\n", .{});
            }
            if (x.default_value) |def| {
                print("else ->", .{});
                generateExpression(def);
                print(";\n", .{});
            }
            print("}}", .{});
        },
        .prefix_unary_expression => |*x| {
            print("{s}", .{tokenizer.tokenKindLiteral(x.operator_token.kind)});
            generateExpression(x.right);
        },
        .postfix_unary_expression => |*x| {
            generateExpression(x.right);
            print("{s}", .{tokenizer.tokenKindLiteral(x.operator_token.kind)});
        },
        .array_expression => |*x| generateArrayExpression(x),
        .character_expression => |*x| print("'{s}'", .{x.value.literal}),
        .vector_expression => |*x| {
            print("@vec", .{});
            generateArrayExpression(x.array);
        },
        .lambda_expression => |*x| {
            print("{{ (", .{});
            for (x.explicit_parameters.items) |parameter| {
                print("{s} ", .{parameter.name.literal});
                generateType(parameter.parameter_type);
                if (parameter != x.explicit_parameters.items[x.explicit_parameters.items.len - 1]) {
                    print(", ", .{});
                }
            }
            print(") ", .{});
            generateType(x.return_type);
            print(" -> \n ", .{});
            for (x.body.statements.items) |stmt| {
                generateStatement(stmt, 1);
            }
            print("}}", .{});
        },
        else => {
            std.log.err("Unknown expression type: {any}", .{@TypeOf(expression)});
        },
    }
}

fn generateArrayExpression(expression: *const ast.ArrayExpression) void {
    print("[", .{});
    for (expression.values.items) |element| {
        generateExpression(element);
        if (element != expression.values.items[expression.values.items.len - 1]) {
            print(", ", .{});
        }
    }
    print("]", .{});
}

fn generateIfExpression(expression: *const ast.IfExpression) void {
    for (0..expression.conditions.items.len) |i| {
        if (i == 0) {
            print("if (", .{});
        } else if (i == expression.conditions.items.len - 1) {
            print("else {{ ", .{});
        } else {
            print("else if (", .{});
        }
        generateExpression(expression.conditions.items[i]);
        if (i != expression.conditions.items.len - 1) {
            print(") {{ ", .{});
        }
        generateExpression(expression.values.items[i]);
        print(" }} ", .{});
    }
}

fn generateBinaryExpression(expression: *const ast.BinaryExpression) void {
    print("(", .{});
    generateExpression(expression.left);
    print(" {s} ", .{tokenizer.tokenKindLiteral(expression.operator_token.kind)});
    generateExpression(expression.right);
    print(")", .{});
}

fn generateLiteralExpression(expression: *const ast.LiteralExpression) void {
    print("{s}", .{expression.name.literal});
}

fn generateCallExpression(expression: *const ast.CallExpression) void {
    generateExpression(expression.callee);
    print("(", .{});
    for (expression.arguments.items) |argument| {
        generateExpression(argument);
        if (argument != expression.arguments.items[expression.arguments.items.len - 1]) {
            print(", ", .{});
        }
    }
    print(")", .{});
}

fn generateFunctionDeclaration(declaration: *const ast.FunctionDeclaration) void {
    generateFunctionPrototype(declaration.prototype);
    generateStatement(declaration.body, 1);
}

fn generateFunctionPrototype(prototype: *const ast.FunctionPrototype) void {
    if (prototype.is_external) {
        print("@extern ", .{});
    }
    print("fun ", .{});

    print("{s}", .{prototype.name.literal});
    if (prototype.is_generic) {
        print("<", .{});
        for (prototype.generic_parameters.items) |parameter| {
            print("{s} ", .{parameter});
            print(", ", .{});
        }
        print("> ", .{});
    }
    print("(", .{});
    for (prototype.parameters.items) |parameter| {
        print("{s} ", .{parameter.name.literal});
        generateType(parameter.parameter_type);
        if (parameter != prototype.parameters.items[prototype.parameters.items.len - 1] or prototype.has_varargs) {
            print(", ", .{});
        }
    }
    if (prototype.has_varargs) {
        print("varargs ", .{});
        generateType(prototype.varargs_type);
    }
    print(") ", .{});
    generateType(prototype.return_type);
}

pub fn generateCodeFromAst(allocator: std.mem.Allocator, compilation_unit: *ast.CompilationUnit) void {
    log("Generating code from AST", .{}, .{ .module = .General });
    print("\n", .{});
    _ = allocator;
    for (compilation_unit.tree_nodes.items) |node| {
        generateStatement(node, 0);
    }
}
