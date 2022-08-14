const std = @import("../../common/std.zig");
const entry_point = switch (std.cpu.arch) {
    .x86_64 => @import("x86_64/entry_point.zig"),
    else => unreachable,
};

pub const function = entry_point.function;
