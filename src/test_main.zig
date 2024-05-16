const std = @import("std");

test "sanity_test" {
    try std.testing.expect(42 == 42);
}

test {
    _ = @import("test_tokenizer.zig");
    _ = @import("test_parser.zig");
    _ = @import("test_typechecker.zig");
}
