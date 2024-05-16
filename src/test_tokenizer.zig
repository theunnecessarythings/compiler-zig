const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const TokenKind = @import("tokenizer.zig").TokenKind;

fn scanAllTokens(source: []const u8) ![]Token {
    const allocator = std.heap.page_allocator;
    var tokenizer = Tokenizer.init(allocator, source, 0);
    return try tokenizer.scanAllTokens();
}

fn expectTokensAndIdentifiers(tokens: []const Token, expected_token_kinds: []const TokenKind, expected_identifiers: []const []const u8) !void {
    try std.testing.expect(tokens.len == expected_token_kinds.len);
    try std.testing.expect(tokens.len == expected_identifiers.len);

    for (tokens, 0..) |token, i| {
        try std.testing.expectEqual(expected_token_kinds[i], token.kind);
        try std.testing.expectEqualSlices(u8, expected_identifiers[i], token.literal);
    }
}

test "basic_character" {
    const source = "( ) [ ] { } , ; ~ @";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .OpenParen, .CloseParen, .OpenBracket, .CloseBracket, .OpenBrace, .CloseBrace, .Comma, .Semicolon, .Not, .At, .EndOfFile };
    const expected_identifiers = [_][]const u8{""} ** expected_token_kinds.len;
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "operators" {
    const source = ". ; :: ; = ; == ; ! ; != ; * ; *= ; / ; /= ; % ; %= ; ^ ; ^= !";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .Dot, .Semicolon, .ColonColon, .Semicolon, .Equal, .Semicolon, .EqualEqual, .Semicolon, .Bang, .Semicolon, .BangEqual, .Semicolon, .Star, .Semicolon, .StarEqual, .Semicolon, .Slash, .Semicolon, .SlashEqual, .Semicolon, .Percent, .Semicolon, .PercentEqual, .Semicolon, .Xor, .Semicolon, .XorEqual, .Bang, .EndOfFile };

    const expected_identifiers = [_][]const u8{""} ** expected_token_kinds.len;
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "increment_decrement_arrow" {
    const source = "++ ; -- ; -> ;";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .PlusPlus, .Semicolon, .MinusMinus, .Semicolon, .RightArrow, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{""} ** expected_token_kinds.len;
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "shift_operators" {
    const source = "> >> >>= < << <<=";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .Greater, .Greater, .Greater, .RightShiftEqual, .Smaller, .LeftShift, .LeftShiftEqual, .EndOfFile };
    const expected_identifiers = [_][]const u8{""} ** expected_token_kinds.len;
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "logical_operators" {
    const source = "& && &= | || |=";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .And, .AndAnd, .AndEqual, .Or, .OrOr, .OrEqual, .EndOfFile };
    const expected_identifiers = [_][]const u8{""} ** expected_token_kinds.len;
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_boolean" {
    const tokens = try scanAllTokens("var bit : bool = 1i1;");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Int1, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "bit", "", "bool", "", "1", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "identifier_keywords" {
    const source = "if for var struct int32_t _customIdentifier";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .If, .For, .Var, .Struct, .Identifier, .Identifier, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "if", "for", "var", "struct", "int32_t", "_customIdentifier", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "whitespace_comments" {
    const source = "   // This is a single line comment\n /* This is a \n multiline \n comment */\n var x = 10;";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Equal, .Int, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "x", "", "10", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_byte" {
    const tokens = try scanAllTokens("var byte : int8 = 1i8;");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Int8, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "byte", "", "int8", "", "1", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_short" {
    const tokens = try scanAllTokens("var short : int16 = 1i16;");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Int16, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "short", "", "int16", "", "1", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_int" {
    const tokens = try scanAllTokens("var int : int32 = 1i32;");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Int32, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "int", "", "int32", "", "1", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_long" {
    const tokens = try scanAllTokens("var long : int64 = 1i64;");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Int64, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "long", "", "int64", "", "1", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_float" {
    const tokens = try scanAllTokens("var float : f32 = 1.0f32;");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Float32, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "float", "", "f32", "", "1.0", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_double" {
    const tokens = try scanAllTokens("var double : f64 = 1.0f64;");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Float64, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "double", "", "f64", "", "1.0", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_u8" {
    const tokens = try scanAllTokens("var u8 : uint8 = 1u8;");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Uint8, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "u8", "", "uint8", "", "1", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_u16" {
    const tokens = try scanAllTokens("var u16 : uint16 = 1u16;");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Uint16, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "u16", "", "uint16", "", "1", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_u32" {
    const tokens = try scanAllTokens("var u32 : uint32 = 1u32;");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Uint32, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "u32", "", "uint32", "", "1", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_u64" {
    const tokens = try scanAllTokens("var u64 : uint64 = 1_000u64;");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Uint64, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "u64", "", "uint64", "", "1000", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_octal" {
    const tokens = try scanAllTokens("var octal : int32 = 0o10;");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Int, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "octal", "", "int32", "", "8", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_hexadecimal" {
    const tokens = try scanAllTokens("var hexadecimal : int32 = 0xff;");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Int, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "hexadecimal", "", "int32", "", "255", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_binary" {
    const tokens = try scanAllTokens("var binary : int32 = 0b101;");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Int, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "binary", "", "int32", "", "5", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_string" {
    const tokens = try scanAllTokens("var string : *char = \"Hello, World!\";");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Star, .Identifier, .Equal, .String, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "string", "", "", "char", "", "Hello, World!", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "consume_characters" {
    const tokens = try scanAllTokens("var character : char = 'a';");

    const expected_token_kinds = [_]TokenKind{ .Var, .Identifier, .Colon, .Identifier, .Equal, .Character, .Semicolon, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "var", "character", "", "char", "", "a", "", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "empty_string" {
    const source = "\"\" \'\'";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .String, .Invalid, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "", "Empty character literal", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "unterminated_string" {
    const source = "\"hello";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .Invalid, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "Unterminated double quote string", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "operator_assign" {
    const source = "+= -= *= /= %= ^= &= |= <<= >>=";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .PlusEqual, .MinusEqual, .StarEqual, .SlashEqual, .PercentEqual, .XorEqual, .AndEqual, .OrEqual, .LeftShiftEqual, .RightShiftEqual, .EndOfFile };
    const expected_identifiers = [_][]const u8{""} ** expected_token_kinds.len;
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "unterminated_character" {
    const source = "\'a";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .Invalid, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "Unterminated single quote character", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "invalid_hexadecimal" {
    const source = "0x";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .Invalid, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "Missing digits after the integer base prefix", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "invalid_binary" {
    const source = "0b";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .Invalid, .EndOfFile };
    const expected_identifiers = [_][]const u8{ "Missing digits after the integer base prefix", "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "keywords" {
    const source = "if else for while break continue return var struct enum value_size type_size type_align";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .If, .Else, .For, .While, .Break, .Continue, .Return, .Var, .Struct, .Enum, .ValueSize, .TypeSize, .TypeAlign, .EndOfFile };

    const expected_identifiers = [_][]const u8{ "if", "else", "for", "while", "break", "continue", "return", "var", "struct", "enum", "value_size", "type_size", "type_align", "" };

    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "escape_sequence" {
    const source = "\"\\n\\t\\r\\b\\f\\'\\\"\\\\\"";
    const tokens = try scanAllTokens(source);

    const expected_token_kinds = [_]TokenKind{ .String, .EndOfFile };
    const expected_identifiers = [_][]const u8{ &[_]u8{ '\n', '\t', '\r', '\x08', '\x0C', '\'', '\"', '\\' }, "" };
    try expectTokensAndIdentifiers(tokens, &expected_token_kinds, &expected_identifiers);
}

test "hello_program" {
    const allocator = std.heap.page_allocator;
    const source =
        \\@extern fun printf(format *char, varargs Any) int64;
        \\fun main() int64 {
        \\    printf("Hello, World!\n");
        \\    return 0;
        \\}
    ;
    var tokenizer = Tokenizer.init(allocator, source, 0);
    const tokens = try tokenizer.scanAllTokens();
    try std.testing.expect(tokens.len == 30);

    const expected = [_]Token{
        .{ .kind = .At, .position = .{
            .file_id = 0,
            .line_number = 1,
            .column_start = 1,
            .column_end = 1,
        }, .literal = "" },
        .{ .kind = .Identifier, .position = .{
            .file_id = 0,
            .line_number = 1,
            .column_start = 2,
            .column_end = 7,
        }, .literal = "extern" },
        .{ .kind = .Fun, .position = .{
            .file_id = 0,
            .line_number = 1,
            .column_start = 9,
            .column_end = 11,
        }, .literal = "fun" },
        .{ .kind = .Identifier, .position = .{
            .file_id = 0,
            .line_number = 1,
            .column_start = 13,
            .column_end = 18,
        }, .literal = "printf" },
        .{ .kind = .OpenParen, .position = .{
            .file_id = 0,
            .line_number = 1,
            .column_start = 19,
            .column_end = 19,
        }, .literal = "" },
        .{ .kind = .Identifier, .position = .{
            .file_id = 0,
            .line_number = 1,
            .column_start = 20,
            .column_end = 25,
        }, .literal = "format" },
        .{ .kind = .Star, .position = .{
            .file_id = 0,
            .line_number = 1,
            .column_start = 27,
            .column_end = 27,
        }, .literal = "" },
        .{ .kind = .Identifier, .position = .{
            .file_id = 0,
            .line_number = 1,
            .column_start = 28,
            .column_end = 31,
        }, .literal = "char" },
        .{ .kind = .Comma, .position = .{
            .file_id = 0,
            .line_number = 1,
            .column_start = 32,
            .column_end = 32,
        }, .literal = "" },
        .{ .kind = .Varargs, .position = .{
            .file_id = 0,
            .line_number = 1,
            .column_start = 34,
            .column_end = 40,
        }, .literal = "varargs" },
        .{ .kind = .Identifier, .position = .{
            .file_id = 0,
            .line_number = 1,
            .column_start = 42,
            .column_end = 44,
        }, .literal = "Any" },
        .{ .kind = .CloseParen, .position = .{
            .file_id = 0,
            .line_number = 1,
            .column_start = 45,
            .column_end = 45,
        }, .literal = "" },
        .{ .kind = .Identifier, .position = .{
            .file_id = 0,
            .line_number = 1,
            .column_start = 47,
            .column_end = 51,
        }, .literal = "int64" },
        .{ .kind = .Semicolon, .position = .{
            .file_id = 0,
            .line_number = 1,
            .column_start = 52,
            .column_end = 52,
        }, .literal = "" },
        .{ .kind = .Fun, .position = .{
            .file_id = 0,
            .line_number = 2,
            .column_start = 1,
            .column_end = 3,
        }, .literal = "fun" },
        .{ .kind = .Identifier, .position = .{
            .file_id = 0,
            .line_number = 2,
            .column_start = 5,
            .column_end = 8,
        }, .literal = "main" },
        .{ .kind = .OpenParen, .position = .{
            .file_id = 0,
            .line_number = 2,
            .column_start = 9,
            .column_end = 9,
        }, .literal = "" },
        .{ .kind = .CloseParen, .position = .{
            .file_id = 0,
            .line_number = 2,
            .column_start = 10,
            .column_end = 10,
        }, .literal = "" },
        .{ .kind = .Identifier, .position = .{
            .file_id = 0,
            .line_number = 2,
            .column_start = 12,
            .column_end = 16,
        }, .literal = "int64" },
        .{ .kind = .OpenBrace, .position = .{
            .file_id = 0,
            .line_number = 2,
            .column_start = 18,
            .column_end = 18,
        }, .literal = "" },
        .{ .kind = .Identifier, .position = .{
            .file_id = 0,
            .line_number = 3,
            .column_start = 5,
            .column_end = 10,
        }, .literal = "printf" },
        .{ .kind = .OpenParen, .position = .{
            .file_id = 0,
            .line_number = 3,
            .column_start = 11,
            .column_end = 11,
        }, .literal = "" },
        .{ .kind = .String, .position = .{
            .file_id = 0,
            .line_number = 3,
            .column_start = 12,
            .column_end = 28,
        }, .literal = "Hello, World!\n" },
        .{ .kind = .CloseParen, .position = .{
            .file_id = 0,
            .line_number = 3,
            .column_start = 29,
            .column_end = 29,
        }, .literal = "" },
        .{ .kind = .Semicolon, .position = .{
            .file_id = 0,
            .line_number = 3,
            .column_start = 30,
            .column_end = 30,
        }, .literal = "" },
        .{ .kind = .Return, .position = .{
            .file_id = 0,
            .line_number = 4,
            .column_start = 5,
            .column_end = 10,
        }, .literal = "return" },
        .{ .kind = .Int, .position = .{
            .file_id = 0,
            .line_number = 4,
            .column_start = 12,
            .column_end = 12,
        }, .literal = "0" },
        .{ .kind = .Semicolon, .position = .{
            .file_id = 0,
            .line_number = 4,
            .column_start = 13,
            .column_end = 13,
        }, .literal = "" },
        .{ .kind = .CloseBrace, .position = .{
            .file_id = 0,
            .line_number = 5,
            .column_start = 1,
            .column_end = 1,
        }, .literal = "" },
        .{ .kind = .EndOfFile, .position = .{
            .file_id = 0,
            .line_number = 5,
            .column_start = 1,
            .column_end = 1,
        }, .literal = "" },
    };

    try std.testing.expectEqualDeep(&expected, tokens);
}
