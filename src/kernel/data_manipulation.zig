const std = @import("std");
const kernel = @import("kernel.zig");
const page_size = kernel.arch.page_size;
const sector_size = kernel.arch.sector_size;
pub inline fn string_eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub inline fn string_starts_with(str: []const u8, slice: []const u8) bool {
    return std.mem.startsWith(u8, str, slice);
}

pub inline fn string_ends_with(str: []const u8, slice: []const u8) bool {
    return std.mem.endsWith(u8, str, slice);
}

pub inline fn align_forward(n: u64, alignment: u64) u64 {
    const mask: u64 = alignment - 1;
    const result = (n + mask) & ~mask;
    return result;
}

pub inline fn align_backward(n: u64, alignment: u64) u64 {
    return n & ~(alignment - 1);
}

pub inline fn is_aligned(n: u64, alignment: u64) bool {
    return n & (alignment - 1) == 0;
}

pub inline fn read_int_big(comptime T: type, slice: []const u8) T {
    return std.mem.readIntBig(T, slice[0..@sizeOf(T)]);
}

pub const copy = std.mem.copy;

pub inline fn zero(bytes: []u8) void {
    for (bytes) |*byte| byte.* = 0;
}

pub inline fn zeroes(comptime T: type) T {
    var result: T = undefined;
    zero(@ptrCast([*]u8, &result)[0..@sizeOf(T)]);
    return result;
}

pub inline fn zero_a_page(page_address: u64) void {
    kernel.assert(@src(), is_aligned(page_address, kernel.arch.page_size));
    zero(@intToPtr([*]u8, page_address)[0..kernel.arch.page_size]);
}

pub inline fn bytes_to_pages(bytes: u64, comptime must_be_exact: bool) u64 {
    return remainder_division_maybe_exact(bytes, page_size, must_be_exact);
}

pub inline fn bytes_to_sector(bytes: u64, comptime must_be_exact: bool) u64 {
    return remainder_division_maybe_exact(bytes, sector_size, must_be_exact);
}

pub inline fn remainder_division_maybe_exact(dividend: u64, divisor: u64, comptime must_be_exact: bool) u64 {
    if (divisor == 0) unreachable;
    const quotient = dividend / divisor;
    const remainder = dividend % divisor;
    const remainder_not_zero = remainder != 0;
    if (must_be_exact and remainder_not_zero) @panic("remainder not exact when asked to be exact");

    return quotient + @boolToInt(remainder_not_zero);
}

pub const maxInt = std.math.maxInt;

pub const as_bytes = std.mem.asBytes;

pub const spinloop_hint = std.atomic.spinLoopHint;

pub fn cstr_len(cstr: [*:0]const u8) u64 {
    var length: u64 = 0;
    while (cstr[length] != 0) : (length += 1) {}
    return length;
}

pub const enum_values = std.enums.values;

pub fn Bitflag(comptime is_volatile: bool, comptime EnumT: type) type {
    return struct {
        const IntType = std.meta.Int(.unsigned, @bitSizeOf(EnumT));
        const Enum = EnumT;
        const Ptr = if (is_volatile) *volatile @This() else *@This();

        bits: IntType,

        pub inline fn from_flags(flags: anytype) @This() {
            const flags_type = @TypeOf(flags);
            const result = comptime blk: {
                const fields = std.meta.fields(flags_type);
                if (fields.len > @bitSizeOf(EnumT)) @compileError("More flags than bits\n");

                var bits: IntType = 0;

                var field_i: u64 = 0;
                inline while (field_i < fields.len) : (field_i += 1) {
                    const field = fields[field_i];
                    const enum_value: EnumT = field.default_value.?;
                    bits |= 1 << @enumToInt(enum_value);
                }
                break :blk bits;
            };
            return @This(){ .bits = result };
        }

        pub fn from_bits(bits: IntType) @This() {
            return @This(){ .bits = bits };
        }

        pub inline fn from_flag(comptime flag: EnumT) @This() {
            const bits = 1 << @enumToInt(flag);
            return @This(){ .bits = bits };
        }

        pub inline fn empty() @This() {
            return @This(){
                .bits = 0,
            };
        }

        pub inline fn all() @This() {
            var result = comptime blk: {
                var bits: IntType = 0;
                inline for (@typeInfo(EnumT).Enum.fields) |field| {
                    bits |= 1 << field.value;
                }
                break :blk @This(){
                    .bits = bits,
                };
            };
            return result;
        }

        pub inline fn is_empty(self: @This()) bool {
            return self.bits == 0;
        }

        /// This assumes invalid values in the flags can't be set.
        pub inline fn is_all(self: @This()) bool {
            return all().bits == self.bits;
        }

        pub inline fn contains(self: @This(), comptime flag: EnumT) bool {
            return ((self.bits & (1 << @enumToInt(flag))) >> @enumToInt(flag)) != 0;
        }

        // TODO: create a mutable version of this
        pub inline fn or_flag(self: Ptr, comptime flag: EnumT) void {
            self.bits |= 1 << @enumToInt(flag);
        }
    };
}
