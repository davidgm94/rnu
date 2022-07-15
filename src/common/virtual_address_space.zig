const VirtualAddressSpace = @This();

const root = @import("root");
const common = @import("../common.zig");
const context = @import("context");
const Allocator = common.Allocator;
const TODO = common.TODO;
const log = common.log.scoped(.VirtualAddressSpace);

const arch = common.arch;
const VirtualAddress = common.VirtualAddress;
const VirtualMemoryRegion = common.VirtualMemoryRegion;
const PhysicalMemoryRegion = common.PhysicalMemoryRegion;
const PhysicalAddress = common.PhysicalAddress;
const PhysicalAddressSpace = common.PhysicalAddressSpace;
const Heap = common.Heap;
const Spinlock = common.arch.Spinlock;

arch: arch.VirtualAddressSpace,
privilege_level: common.PrivilegeLevel,
heap: Heap,
lock: Spinlock,
initialized: bool,

/// This is going to return an identitty-mapped virtual address pointer and it is only intended to use for the
/// kernel address space
pub fn initialize_kernel_address_space(virtual_address_space: *VirtualAddressSpace, physical_address_space: *PhysicalAddressSpace) ?void {
    // TODO: defer memory free when this produces an error
    const arch_virtual_space = arch.VirtualAddressSpace.new(physical_address_space) orelse return null;
    // TODO: Maybe consume just the necessary space? We are doing this to avoid branches in the kernel heap allocator
    virtual_address_space.* = VirtualAddressSpace{
        .arch = arch_virtual_space,
        .privilege_level = .kernel,
        .heap = Heap.new(virtual_address_space),
        .lock = Spinlock.new(),
        .initialized = false,
    };
}

pub fn bootstrapping() VirtualAddressSpace {
    const bootstrap_arch_specific_vas = arch.VirtualAddressSpace.bootstrapping();
    return VirtualAddressSpace{
        .arch = bootstrap_arch_specific_vas,
        .privilege_level = .kernel,
        .heap = undefined,
        .lock = Spinlock.new(),
        .initialized = false,
    };
}

pub fn initialize_user_address_space(virtual_address_space: *VirtualAddressSpace, physical_address_space: *PhysicalAddressSpace, kernel_address_space: *VirtualAddressSpace) ?void {
    // TODO: defer memory free when this produces an error
    const arch_virtual_space = arch.VirtualAddressSpace.new(physical_address_space) orelse return null;
    // TODO: Maybe consume just the necessary space? We are doing this to avoid branches in the kernel heap allocator
    virtual_address_space.* = VirtualAddressSpace{
        .arch = arch_virtual_space,
        .privilege_level = .user,
        .heap = Heap.new(virtual_address_space),
        .lock = Spinlock.new(),
        .initialized = false,
    };

    virtual_address_space.arch.map_kernel_address_space_higher_half(kernel_address_space);
}

pub fn copy(old: *VirtualAddressSpace, new: *VirtualAddressSpace) void {
    new.* = old.*;
    new.heap.allocator.ptr = new;
}

pub fn allocate(virtual_address_space: *VirtualAddressSpace, byte_count: u64, maybe_specific_address: ?VirtualAddress, flags: Flags) !VirtualAddress {
    virtual_address_space.lock.acquire();
    defer virtual_address_space.lock.release();
    const page_count = common.bytes_to_pages(byte_count, context.page_size, .must_be_exact);
    const physical_address = root.physical_address_space.allocate(page_count) orelse return Allocator.Error.OutOfMemory;

    const virtual_address = blk: {
        if (maybe_specific_address) |specific_address| {
            common.runtime_assert(@src(), !flags.user == specific_address.is_higher_half());
            break :blk specific_address;
        } else {
            if (flags.user) {
                break :blk VirtualAddress.new(physical_address.value);
            } else {
                break :blk physical_address.to_higher_half_virtual_address();
            }
        }
    };

    if (flags.user) common.runtime_assert(@src(), virtual_address_space.translate_address(virtual_address) == null);

    const physical_region = PhysicalMemoryRegion.new(physical_address, page_count * context.page_size);
    virtual_address_space.map_physical_region(physical_region, virtual_address, flags);
    return virtual_address;
}

pub fn map(virtual_address_space: *VirtualAddressSpace, physical_address: PhysicalAddress, virtual_address: VirtualAddress, flags: Flags) void {
    virtual_address_space.arch.map(physical_address, virtual_address, flags.to_arch_specific());
    const new_physical_address = virtual_address_space.translate_address(virtual_address) orelse @panic("address not present");
    common.runtime_assert(@src(), new_physical_address.is_valid());
    common.runtime_assert(@src(), new_physical_address.is_equal(physical_address));
}

pub fn translate_address(virtual_address_space: *VirtualAddressSpace, virtual_address: VirtualAddress) ?PhysicalAddress {
    return virtual_address_space.arch.translate_address(virtual_address);
}

pub fn make_current(virtual_address_space: *VirtualAddressSpace) void {
    virtual_address_space.arch.make_current();
}

// TODO: make this efficient
pub fn map_virtual_region(virtual_address_space: *VirtualAddressSpace, virtual_region: VirtualMemoryRegion, base_physical_address: PhysicalAddress, flags: Flags) void {
    var physical_address = base_physical_address;
    var virtual_address = virtual_region.address;
    const page_size = context.page_size;
    common.runtime_assert(@src(), common.is_aligned(physical_address.value, page_size));
    common.runtime_assert(@src(), common.is_aligned(virtual_address.value, page_size));
    common.runtime_assert(@src(), common.is_aligned(virtual_region.size, page_size));

    var size: u64 = 0;

    while (size < virtual_region.size) : (size += page_size) {
        virtual_address_space.map(physical_address, virtual_address, flags);
        physical_address.value += page_size;
        virtual_address.value += page_size;
    }
}

pub fn map_physical_region(virtual_address_space: *VirtualAddressSpace, physical_region: PhysicalMemoryRegion, base_virtual_address: VirtualAddress, flags: Flags) void {
    var physical_address = physical_region.address;
    var virtual_address = base_virtual_address;
    const page_size = context.page_size;
    common.runtime_assert(@src(), common.is_aligned(physical_address.value, page_size));
    common.runtime_assert(@src(), common.is_aligned(virtual_address.value, page_size));
    common.runtime_assert(@src(), common.is_aligned(physical_region.size, page_size));

    var size: u64 = 0;
    log.debug("Init mapping", .{});

    while (size < physical_region.size) : (size += page_size) {
        virtual_address_space.map(physical_address, virtual_address, flags);
        physical_address.value += page_size;
        virtual_address.value += page_size;
    }
    log.debug("End mapping", .{});
}

pub const Flags = packed struct {
    write: bool = false,
    cache_disable: bool = false,
    accessed: bool = false,
    global: bool = false,
    execute: bool = false,
    user: bool = false,

    pub inline fn empty() Flags {
        return common.zeroes(Flags);
    }

    pub inline fn to_arch_specific(flags: Flags) arch.VirtualAddressSpace.Flags {
        return arch.VirtualAddressSpace.new_flags(flags);
    }
};
