const std = @import("std");

pub const TokenKind = enum {
    Load,
    Import,

    Var,
    Const,

    Enum,
    Type,
    Struct,
    Fun,
    Operator,
    Return,
    If,
    Else,
    For,
    While,
    Switch,
    Cast,
    Defer,

    Break,
    Continue,

    TypeSize,
    TypeAlign,
    ValueSize,

    True,
    False,
    Null,
    Undefined,

    Varargs,

    Dot,
    DotDot,
    Comma,
    Colon,
    ColonColon,
    Semicolon,
    At,

    Plus,
    Minus,
    Star,
    Slash,
    Percent,

    Or,
    OrOr,
    And,
    AndAnd,
    Xor,

    Not,

    Equal,
    EqualEqual,
    Bang,
    BangEqual,
    Greater,
    GreaterEqual,
    Smaller,
    SmallerEqual,

    RightShift,
    RightShiftEqual,
    LeftShift,
    LeftShiftEqual,

    PlusEqual,
    MinusEqual,
    StarEqual,
    SlashEqual,
    PercentEqual,

    OrEqual,
    AndEqual,
    XorEqual,

    PlusPlus,
    MinusMinus,

    RightArrow,

    OpenParen,
    CloseParen,
    OpenBracket,
    CloseBracket,
    OpenBrace,
    CloseBrace,

    Identifier,
    String,
    Character,

    Int,
    Int1,
    Int8,
    Int16,
    Int32,
    Int64,

    Uint8,
    Uint16,
    Uint32,
    Uint64,

    Float,
    Float32,
    Float64,

    Invalid,
    EndOfFile,
};

pub const TokenSpan = struct {
    file_id: i64,
    line_number: u32,
    column_start: u32,
    column_end: u32,
};

pub const Token = struct {
    kind: TokenKind,
    position: TokenSpan,
    literal: []const u8,
};

const TwoTokensOperator = struct {
    first: TokenKind,
    second: TokenKind,
    both: TokenKind,
};

pub fn tokenKindLiteral(kind: TokenKind) []const u8 {
    return switch (kind) {
        .Load => "load",
        .Import => "import",
        .Var => "var",
        .Const => "const",
        .Enum => "enum",
        .Type => "type",
        .Struct => "struct",
        .Fun => "fun",
        .Operator => "operator",
        .Return => "return",
        .If => "if",
        .Else => "else",
        .For => "for",
        .While => "while",
        .Switch => "switch",
        .Cast => "cast",
        .Defer => "defer",
        .Break => "break",
        .Continue => "continue",
        .TypeSize => "type_size",
        .TypeAlign => "type_align",
        .ValueSize => "value_size",
        .True => "true",
        .False => "false",
        .Null => "null",
        .Undefined => "undefined",
        .Varargs => "varargs",
        .Dot => ".",
        .DotDot => "..",
        .Comma => ",",
        .Colon => ":",
        .ColonColon => "::",
        .Semicolon => ";",
        .At => "@",
        .Plus => "+",
        .Minus => "-",
        .Star => "*",
        .Slash => "/",
        .Percent => "%",
        .Or => "|",
        .OrOr => "||",
        .And => "&",
        .AndAnd => "&&",
        .Xor => "^",
        .Not => "~",
        .Equal => "=",
        .EqualEqual => "==",
        .Bang => "!",
        .BangEqual => "!=",
        .Greater => ">",
        .GreaterEqual => ">=",
        .Smaller => "<",
        .SmallerEqual => "<=",
        .RightShift => ">>",
        .RightShiftEqual => ">>=",
        .LeftShift => "<<",
        .LeftShiftEqual => "<<=",
        .PlusEqual => "+=",
        .MinusEqual => "-=",
        .StarEqual => "*=",
        .SlashEqual => "/=",
        .PercentEqual => "%=",
        .OrEqual => "|=",
        .AndEqual => "&=",
        .XorEqual => "^=",
        .PlusPlus => "++",
        .MinusMinus => "--",
        .RightArrow => "->",
        .OpenParen => "(",
        .CloseParen => ")",
        .OpenBracket => "[",
        .CloseBracket => "]",
        .OpenBrace => "{",
        .CloseBrace => "}",
        .Identifier => "identifier",
        .String => "string",
        .Character => "char",
        .Int => "int",
        .Int1 => "int1",
        .Int8 => "int8",
        .Int16 => "int16",
        .Int32 => "int32",
        .Int64 => "int64",
        .Uint8 => "uint8",
        .Uint16 => "uint16",
        .Uint32 => "uint32",
        .Uint64 => "uint64",
        .Float => "float",
        .Float32 => "float32",
        .Float64 => "float64",
        .Invalid => "Invalid",
        .EndOfFile => "End of the file",
    };
}

pub fn unaryOperators(kind: TokenKind) bool {
    return switch (kind) {
        .Minus, .Bang, .Star, .And, .Not => true,
        else => false,
    };
}

pub fn assignmentOperators(kind: TokenKind) bool {
    return switch (kind) {
        .Equal, .PlusEqual, .MinusEqual, .StarEqual, .SlashEqual, .PercentEqual, .OrEqual, .AndEqual, .XorEqual, .RightShiftEqual, .LeftShiftEqual => true,
        else => false,
    };
}

pub fn assignmentBinaryOperators(kind: TokenKind) !TokenKind {
    return switch (kind) {
        .PlusEqual => .Plus,
        .MinusEqual => .Minus,
        .StarEqual => .Star,
        .SlashEqual => .Slash,
        .PercentEqual => .Percent,
        else => error.NotFound,
    };
}

pub fn assignmentBitwiseOperators(kind: TokenKind) !TokenKind {
    return switch (kind) {
        .OrEqual => .Or,
        .AndEqual => .And,
        .XorEqual => .Xor,
        .RightShiftEqual => .RightShift,
        .LeftShiftEqual => .LeftShift,
        else => error.NotFound,
    };
}

pub fn overloadingOperatorLiteral(kind: TokenKind) ![]const u8 {
    return switch (kind) {
        .Plus => "plus",
        .Minus => "minus",
        .Star => "star",
        .Slash => "slash",
        .Percent => "percent",
        .Bang => "bang",
        .Not => "not",
        .EqualEqual => "eq_eq",
        .BangEqual => "not_eq",
        .Greater => "gt",
        .GreaterEqual => "gt_eq",
        .Smaller => "lt",
        .SmallerEqual => "lt_eq",
        .And => "and",
        .Or => "or",
        .Xor => "xor",
        .AndAnd => "and_and",
        .OrOr => "or_or",
        .RightShift => "rsh",
        .LeftShift => "lsh",
        .PlusPlus => "plus_plus",
        .MinusMinus => "minus_minus",
        else => error.NotFound,
    };
}

pub fn overloadingPrefixOperators(kind: TokenKind) bool {
    return switch (kind) {
        .Not, .Bang, .Minus, .PlusPlus, .MinusMinus => true,
        else => false,
    };
}

pub fn overloadingInfixOperators(kind: TokenKind) bool {
    return switch (kind) {
        .Plus, .Minus, .Star, .Slash, .Percent, .EqualEqual, .BangEqual, .Greater, .GreaterEqual, .Smaller, .SmallerEqual, .And, .Or, .Xor, .AndAnd, .OrOr, .RightShift, .LeftShift => true,
        else => false,
    };
}

pub fn overloadingPostfixOperators(kind: TokenKind) bool {
    return switch (kind) {
        .PlusPlus, .MinusMinus => true,
        else => false,
    };
}

pub fn comparisonsOperators(kind: TokenKind) bool {
    return switch (kind) {
        .Equal, .EqualEqual, .BangEqual, .Greater, .GreaterEqual, .Smaller, .SmallerEqual => true,
        else => false,
    };
}

pub const TwoTokensOperators = [_]TwoTokensOperator{
    TwoTokensOperator{ .first = .Plus, .second = .Plus, .both = .PlusPlus },
    // Shift expression
    TwoTokensOperator{ .first = .Greater, .second = .Greater, .both = .RightShift },
    TwoTokensOperator{ .first = .Smaller, .second = .Smaller, .both = .LeftShift },
    // Comparisons expression
    TwoTokensOperator{ .first = .Equal, .second = .Equal, .both = .EqualEqual },
    TwoTokensOperator{ .first = .Bang, .second = .Equal, .both = .BangEqual },
    TwoTokensOperator{ .first = .Greater, .second = .Equal, .both = .GreaterEqual },
    TwoTokensOperator{ .first = .Smaller, .second = .Equal, .both = .SmallerEqual },
    // Assignment expression
    TwoTokensOperator{ .first = .Plus, .second = .Equal, .both = .PlusEqual },
    TwoTokensOperator{ .first = .Minus, .second = .Equal, .both = .MinusEqual },
    TwoTokensOperator{ .first = .Star, .second = .Equal, .both = .StarEqual },
    TwoTokensOperator{ .first = .Slash, .second = .Equal, .both = .SlashEqual },
    TwoTokensOperator{ .first = .Percent, .second = .Equal, .both = .PercentEqual },
    TwoTokensOperator{ .first = .Or, .second = .Equal, .both = .OrEqual },
    TwoTokensOperator{ .first = .And, .second = .Equal, .both = .AndEqual },
    TwoTokensOperator{ .first = .Xor, .second = .Equal, .both = .XorEqual },
};

pub fn isFloatNumberToken(kind: TokenKind) bool {
    return switch (kind) {
        .Float, .Float32, .Float64 => true,
        else => false,
    };
}

pub const Tokenizer = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    file_id: i64,
    source_length: u32,
    start_position: u32,
    current_position: u32,
    line_number: u32,
    column_start: u32,
    column_current: u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, source: []const u8, file_id: i64) Self {
        return Tokenizer{
            .allocator = allocator,
            .source = source,
            .file_id = file_id,
            .source_length = @intCast(source.len),
            .start_position = 0,
            .current_position = 0,
            .line_number = 1,
            .column_start = 0,
            .column_current = 0,
        };
    }

    pub fn scanAllTokens(self: *Self) ![]Token {
        var tokens = std.ArrayList(Token).init(self.allocator);
        while (self.isSourceAvailable()) {
            const token = try self.scanNextToken();
            _ = try tokens.append(token);
        }
        _ = try tokens.append(self.buildToken(.EndOfFile));
        return tokens.items;
    }

    pub fn scanNextToken(self: *Self) !Token {
        try self.skipWhitespaces();
        self.start_position = self.current_position;
        self.column_start = self.column_current;

        const c = self.advance();

        self.start_position += 1;
        self.current_position = self.start_position;
        self.column_start += 1;
        self.column_current = self.column_start;

        switch (c) {
            '(' => return self.buildToken(.OpenParen),
            ')' => return self.buildToken(.CloseParen),
            '[' => return self.buildToken(.OpenBracket),
            ']' => return self.buildToken(.CloseBracket),
            '{' => return self.buildToken(.OpenBrace),
            '}' => return self.buildToken(.CloseBrace),
            ',' => return self.buildToken(.Comma),
            ';' => return self.buildToken(.Semicolon),
            '~' => return self.buildToken(.Not),
            '@' => return self.buildToken(.At),
            '.' => {
                if (try self.match('.')) {
                    return self.buildToken(.DotDot);
                }
                return self.buildToken(.Dot);
            },
            ':' => {
                if (try self.match(':')) {
                    return self.buildToken(.ColonColon);
                }
                return self.buildToken(.Colon);
            },
            '=' => {
                if (try self.match('=')) {
                    return self.buildToken(.EqualEqual);
                }
                return self.buildToken(.Equal);
            },
            '!' => {
                if (try self.match('=')) {
                    return self.buildToken(.BangEqual);
                }
                return self.buildToken(.Bang);
            },
            '*' => {
                if (try self.match('=')) {
                    return self.buildToken(.StarEqual);
                }
                return self.buildToken(.Star);
            },
            '/' => {
                if (try self.match('=')) {
                    return self.buildToken(.SlashEqual);
                }
                return self.buildToken(.Slash);
            },
            '%' => {
                if (try self.match('=')) {
                    return self.buildToken(.PercentEqual);
                }
                return self.buildToken(.Percent);
            },
            '^' => {
                if (try self.match('=')) {
                    return self.buildToken(.XorEqual);
                }
                return self.buildToken(.Xor);
            },
            '+' => {
                if (try self.match('+')) {
                    return self.buildToken(.PlusPlus);
                }
                if (try self.match('=')) {
                    return self.buildToken(.PlusEqual);
                }
                return self.buildToken(.Plus);
            },
            '-' => {
                if (try self.match('-')) {
                    if (try self.match('-')) {
                        return self.buildToken(.Undefined);
                    }
                    return self.buildToken(.MinusMinus);
                }
                if (try self.match('=')) {
                    return self.buildToken(.MinusEqual);
                }
                if (try self.match('>')) {
                    return self.buildToken(.RightArrow);
                }
                return self.buildToken(.Minus);
            },
            '>' => {
                if (try self.matchTwo('>', '=')) {
                    return self.buildToken(.RightShiftEqual);
                }
                if (try self.match('=')) {
                    return self.buildToken(.GreaterEqual);
                }
                return self.buildToken(.Greater);
            },
            '<' => {
                if (try self.match('<')) {
                    if (try self.match('=')) {
                        return self.buildToken(.LeftShiftEqual);
                    }
                    return self.buildToken(.LeftShift);
                }
                if (try self.match('=')) {
                    return self.buildToken(.SmallerEqual);
                }
                return self.buildToken(.Smaller);
            },
            '|' => {
                if (try self.match('=')) {
                    return self.buildToken(.OrEqual);
                }
                if (try self.match('|')) {
                    return self.buildToken(.OrOr);
                }
                return self.buildToken(.Or);
            },
            '&' => {
                if (try self.match('=')) {
                    return self.buildToken(.AndEqual);
                }
                if (try self.match('&')) {
                    return self.buildToken(.AndAnd);
                }
                return self.buildToken(.And);
            },
            'A'...'Z', 'a'...'z', '_' => return self.consumeSymbol(),
            '"' => return self.consumeString(),
            '\'' => return self.consumeCharacter(),
            '0' => {
                if (try self.match('x')) {
                    return self.consumeHexNumber();
                }
                if (try self.match('b')) {
                    return self.consumeBinaryNumber();
                }
                if (try self.match('o')) {
                    return self.consumeOctalNumber();
                }
                return self.consumeNumber();
            },
            '1'...'9' => return self.consumeNumber(),
            0 => return self.buildToken(.EndOfFile),
            else => return self.buildTokenWithLiteral(.Invalid, "Unexpected character"),
        }
    }

    fn consumeSymbol(self: *Self) !Token {
        while (isAlphaNum(self.peek()) or self.peek() == '_') {
            _ = self.advance();
        }
        const literal = self.source[self.start_position - 1 .. self.current_position];
        const kind = resolveKeywordTokenKind(literal);
        return self.buildTokenWithLiteral(kind, literal);
    }

    fn consumeNumber(self: *Self) !Token {
        var kind: TokenKind = .Int;
        while (isDigit(self.peek()) or isUnderscore(self.peek())) {
            _ = self.advance();
        }

        if (self.peek() == '.' and isDigit(try self.peekNext())) {
            kind = .Float;
            _ = self.advance();
            while (isDigit(self.peek()) or isUnderscore(self.peek())) {
                _ = self.advance();
            }
        }

        const number_end_position = self.current_position;

        // Signed Integers types
        if (try self.match('i')) {
            if (try self.match('1')) {
                kind = if (try self.match('6'))
                    .Int16
                else
                    .Int1;
            } else if (try self.match('8')) {
                kind = .Int8;
            } else if (try self.match('3') and try self.match('2')) {
                kind = .Int32;
            } else if (try self.match('6') and try self.match('4')) {
                kind = .Int64;
            } else {
                return self.buildTokenWithLiteral(.Invalid, "invalid width for singed integer literal, expect 8, 16, 32 or 64");
            }
        }
        // Un Signed Integers types
        if (try self.match('u')) {
            if (try self.match('1') and try self.match('6')) {
                kind = .Uint16;
            } else if (try self.match('8')) {
                kind = .Uint8;
            } else if (try self.match('3') and try self.match('2')) {
                kind = .Uint32;
            } else if (try self.match('6') and try self.match('4')) {
                kind = .Uint64;
            } else {
                return self.buildTokenWithLiteral(.Invalid, "invalid width for unsinged integer literal, expect 8, 16, 32 or 64");
            }
        }
        // Floating Pointers types
        else if (try self.match('f')) {
            if (try self.match('3') and try self.match('2')) {
                kind = .Float32;
            } else if (try self.match('6') and try self.match('4')) {
                kind = .Float64;
            } else {
                return self.buildTokenWithLiteral(.Invalid, "invalid width for floating point literal, expect 32 or 64");
            }
        } else if (isAlpha(self.peek())) {
            return self.buildTokenWithLiteral(.Invalid, "invalid suffix for number literal, expect i, u or f");
        }

        var literal = self.source[self.start_position - 1 .. number_end_position];
        literal = try std.mem.replaceOwned(u8, self.allocator, literal, "_", "");

        return self.buildTokenWithLiteral(kind, literal);
    }

    fn consumeHexNumber(self: *Self) !Token {
        var has_digits = false;
        while (isHexDigit(self.peek()) or isUnderscore(self.peek())) {
            _ = self.advance();
            has_digits = true;
        }

        if (!has_digits) {
            return self.buildTokenWithLiteral(.Invalid, "Missing digits after the integer base prefix");
        }
        var literal = self.source[self.start_position + 1 .. self.current_position];
        literal = try std.mem.replaceOwned(u8, self.allocator, literal, "_", "");
        const decimal_value = try hexToDecimal(literal);

        if (decimal_value == -1) {
            return self.buildTokenWithLiteral(.Invalid, "Hex integer literal is too large");
        }

        return self.buildTokenWithLiteral(.Int, try std.fmt.allocPrint(self.allocator, "{d}", .{decimal_value}));
    }

    fn consumeBinaryNumber(self: *Self) !Token {
        var has_digits = false;
        while (isBinaryDigit(self.peek()) or isUnderscore(self.peek())) {
            _ = self.advance();
            has_digits = true;
        }

        if (!has_digits) {
            return self.buildTokenWithLiteral(.Invalid, "Missing digits after the integer base prefix");
        }

        const literal = self.source[self.start_position + 1 .. self.current_position];
        const decimal_value = try binaryToDecimal(literal);

        if (decimal_value == -1) {
            return self.buildTokenWithLiteral(.Invalid, "Binary integer literal is too large");
        }

        return self.buildTokenWithLiteral(.Int, try std.fmt.allocPrint(self.allocator, "{d}", .{decimal_value}));
    }

    fn consumeOctalNumber(self: *Self) !Token {
        var has_digits = false;
        while (isOctalDigit(self.peek()) or isUnderscore(self.peek())) {
            _ = self.advance();
            has_digits = true;
        }

        if (!has_digits) {
            return self.buildTokenWithLiteral(.Invalid, "Missing digits after the integer base prefix");
        }

        var literal = self.source[self.start_position + 1 .. self.current_position];
        literal = try std.mem.replaceOwned(u8, self.allocator, literal, "_", "");
        const decimal_value = try octalToDecimal(literal);

        if (decimal_value == -1) {
            return self.buildTokenWithLiteral(.Invalid, "Octal integer literal is too large");
        }

        return self.buildTokenWithLiteral(.Int, try std.fmt.allocPrint(self.allocator, "{d}", .{decimal_value}));
    }

    fn consumeString(self: *Self) !Token {
        var stream = std.ArrayList(u8).init(self.allocator);
        while (self.isSourceAvailable() and self.peek() != '"') {
            const c = self.consumeOneCharacter() catch {
                return self.buildTokenWithLiteral(.Invalid, "Invalid character");
            };
            _ = try stream.append(c);
        }

        if (!self.isSourceAvailable()) {
            return self.buildTokenWithLiteral(.Invalid, "Unterminated double quote string");
        }

        _ = self.advance();
        return self.buildTokenWithLiteral(.String, stream.items);
    }

    fn consumeCharacter(self: *Self) !Token {
        const c = self.consumeOneCharacter() catch {
            return self.buildTokenWithLiteral(.Invalid, "Invalid character");
        };

        if (c == '\'') {
            return self.buildTokenWithLiteral(.Invalid, "Empty character literal");
        }

        if (self.peek() != '\'') {
            return self.buildTokenWithLiteral(.Invalid, "Unterminated single quote character");
        }

        _ = self.advance();
        const literal = std.fmt.allocPrint(self.allocator, "{c}", .{c}) catch unreachable;
        return self.buildTokenWithLiteral(
            .Character,
            literal,
        );
    }

    fn consumeOneCharacter(self: *Self) !u8 {
        const c = self.advance();
        if (c == '\\') {
            const escape = self.peek();
            switch (escape) {
                'a' => {
                    _ = self.advance();
                    return 7;
                },
                'b' => {
                    _ = self.advance();
                    return 8;
                },
                'f' => {
                    _ = self.advance();
                    return 12;
                },
                'n' => {
                    _ = self.advance();
                    return '\n';
                },
                'r' => {
                    _ = self.advance();
                    return '\r';
                },
                't' => {
                    _ = self.advance();
                    return '\t';
                },
                'v' => {
                    _ = self.advance();
                    return 11;
                },
                '0' => {
                    _ = self.advance();
                    return 0;
                },
                '\'' => {
                    _ = self.advance();
                    return '\'';
                },
                '\\' => {
                    _ = self.advance();
                    return '\\';
                },
                '"' => {
                    _ = self.advance();
                    return '"';
                },
                'x' => {
                    _ = self.advance();
                    const first_digit = self.advance();
                    const second_digit = self.advance();
                    if (isDigit(first_digit) and isDigit(second_digit)) {
                        return (hexToInt(first_digit) << 4) + hexToInt(second_digit);
                    }
                    return error.InvalidCharacter;
                },
                else => {
                    return error.InvalidCharacter;
                },
            }
        }
        return c;
    }

    fn buildTokenWithLiteral(self: *Self, kind: TokenKind, literal: []const u8) Token {
        return Token{
            .kind = kind,
            .position = self.buildTokenSpan(),
            .literal = literal,
        };
    }

    fn buildToken(self: *Self, kind: TokenKind) Token {
        return self.buildTokenWithLiteral(kind, "");
    }

    fn buildTokenSpan(self: *Self) TokenSpan {
        return TokenSpan{
            .file_id = self.file_id,
            .line_number = self.line_number,
            .column_start = self.column_start,
            .column_end = self.column_current,
        };
    }

    fn skipWhitespaces(self: *Self) !void {
        while (self.isSourceAvailable()) {
            const c = self.peek();
            switch (c) {
                ' ', '\r', '\t' => {
                    _ = self.advance();
                    // break;
                },
                '\n' => {
                    self.line_number += 1;
                    _ = self.advance();
                    self.column_current = 0;
                    // break;
                },
                '/' => {
                    if (try self.peekNext() == '/' or try self.peekNext() == '*') {
                        _ = self.advance();
                    } else {
                        return;
                    }
                    if (try self.match('/')) {
                        try self.skipSingleLineComment();
                    } else if (try self.match('*')) {
                        try self.skipMultiLinesComment();
                    }
                    // break;
                },
                else => return,
            }
        }
    }

    fn skipSingleLineComment(self: *Self) !void {
        while (self.isSourceAvailable() and self.peek() != '\n') {
            _ = self.advance();
        }
    }

    fn skipMultiLinesComment(self: *Self) !void {
        while (self.isSourceAvailable() and (self.peek() != '*' or try self.peekNext() != '/')) {
            _ = self.advance();
            if (self.peek() == '\n') {
                self.line_number += 1;
                self.column_current = 0;
            }
        }
        _ = self.advance();
        _ = self.advance();

        // If multi line comments end with new line update the line number
        if (self.peek() == '\n') {
            self.line_number += 1;
            self.column_current = 0;
        }
    }

    fn match(self: *Self, expected: u8) !bool {
        if (!self.isSourceAvailable() or self.peek() != expected) {
            return false;
        }
        _ = self.advance();
        return true;
    }

    fn matchTwo(self: *Self, first: u8, second: u8) !bool {
        if (!self.isSourceAvailable() or self.peek() != first or try self.peekNext() != second) {
            return false;
        }
        _ = self.advance();
        _ = self.advance();
        return true;
    }

    fn advance(self: *Self) u8 {
        if (!self.isSourceAvailable()) {
            return 0;
        }
        self.current_position += 1;
        self.column_current += 1;
        return self.source[self.current_position - 1];
    }

    fn peek(self: *Self) u8 {
        if (self.current_position >= self.source_length) {
            return 0;
        }
        return self.source[self.current_position];
    }

    fn peekNext(self: *Self) !u8 {
        if (self.current_position + 1 >= self.source_length) {
            return error.OutOfBounds;
        }
        return self.source[self.current_position + 1];
    }

    fn isDigit(c: u8) bool {
        return '9' >= c and c >= '0';
    }

    fn isHexDigit(c: u8) bool {
        return isDigit(c) or ('F' >= c and c >= 'A') or ('f' >= c and c >= 'a');
    }

    fn isBinaryDigit(c: u8) bool {
        return c == '1' or c == '0';
    }

    fn isOctalDigit(c: u8) bool {
        return '7' >= c and c >= '0';
    }

    fn isAlpha(c: u8) bool {
        if ('z' >= c and c >= 'a') {
            return true;
        }
        return 'Z' >= c and c >= 'A';
    }

    fn isAlphaNum(c: u8) bool {
        return isAlpha(c) or isDigit(c);
    }

    fn isUnderscore(c: u8) bool {
        return c == '_';
    }

    fn binaryToDecimal(binary: []const u8) !i64 {
        const integer = try std.fmt.parseInt(i64, binary, 2);
        return integer;
    }

    fn hexToDecimal(hex: []const u8) !i64 {
        const integer = try std.fmt.parseInt(i64, hex, 16);
        return integer;
    }

    fn octalToDecimal(octal: []const u8) !i64 {
        const integer = try std.fmt.parseInt(i64, octal, 8);
        return integer;
    }

    fn hexToInt(c: u8) u8 {
        if (c <= '9') {
            return c - '0';
        } else if (c <= 'F') {
            return c - 'A';
        }
        return c - 'a';
    }

    fn resolveKeywordTokenKind(keyword: []const u8) TokenKind {
        if (std.mem.eql(u8, keyword, "load")) {
            return .Load;
        }
        if (std.mem.eql(u8, keyword, "import")) {
            return .Import;
        }
        if (std.mem.eql(u8, keyword, "var")) {
            return .Var;
        }
        if (std.mem.eql(u8, keyword, "const")) {
            return .Const;
        }
        if (std.mem.eql(u8, keyword, "enum")) {
            return .Enum;
        }
        if (std.mem.eql(u8, keyword, "type")) {
            return .Type;
        }
        if (std.mem.eql(u8, keyword, "struct")) {
            return .Struct;
        }
        if (std.mem.eql(u8, keyword, "fun")) {
            return .Fun;
        }
        if (std.mem.eql(u8, keyword, "operator")) {
            return .Operator;
        }
        if (std.mem.eql(u8, keyword, "return")) {
            return .Return;
        }
        if (std.mem.eql(u8, keyword, "if")) {
            return .If;
        }
        if (std.mem.eql(u8, keyword, "else")) {
            return .Else;
        }
        if (std.mem.eql(u8, keyword, "for")) {
            return .For;
        }
        if (std.mem.eql(u8, keyword, "while")) {
            return .While;
        }
        if (std.mem.eql(u8, keyword, "switch")) {
            return .Switch;
        }
        if (std.mem.eql(u8, keyword, "cast")) {
            return .Cast;
        }
        if (std.mem.eql(u8, keyword, "defer")) {
            return .Defer;
        }
        if (std.mem.eql(u8, keyword, "break")) {
            return .Break;
        }
        if (std.mem.eql(u8, keyword, "continue")) {
            return .Continue;
        }
        if (std.mem.eql(u8, keyword, "type_size")) {
            return .TypeSize;
        }
        if (std.mem.eql(u8, keyword, "type_align")) {
            return .TypeAlign;
        }
        if (std.mem.eql(u8, keyword, "value_size")) {
            return .ValueSize;
        }
        if (std.mem.eql(u8, keyword, "true")) {
            return .True;
        }
        if (std.mem.eql(u8, keyword, "false")) {
            return .False;
        }
        if (std.mem.eql(u8, keyword, "null")) {
            return .Null;
        }
        if (std.mem.eql(u8, keyword, "undefined")) {
            return .Undefined;
        }
        if (std.mem.eql(u8, keyword, "varargs")) {
            return .Varargs;
        }
        return .Identifier;
    }

    fn isSourceAvailable(self: *Self) bool {
        return self.current_position < self.source_length;
    }

    pub fn getSourceFileId(self: *Self) i64 {
        return self.file_id;
    }
};
