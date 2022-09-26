const RNUFS = @This();

const common = @import("common");
const Allocator = common.CustomAllocator;
const assert = common.assert;
const cstr_len = common.cstr_len;
const div_ceil = common.div_ceil;
const log = common.log.scoped(.RNUFS);
const string_eq = common.string_eq;

const default_signature = common.RNUFS.default_signature;
const Node = common.RNUFS.Node;
const Superblock = common.RNUFS.Superblock;

const RNU = @import("RNU");
const DeviceManager = RNU.DeviceManager;
const Disk = RNU.Disk;
const Filesystem = RNU.Filesystem;
const panic = RNU.panic;
const VirtualAddressSpace = RNU.VirtualAddressSpace;

fs: Filesystem,

const InitError = error{
    not_found,
};

// TODO: free
pub fn init(device_manager: *DeviceManager, virtual_address_space: *VirtualAddressSpace, disk: *Disk) !void {
    var dma_buffer = try disk.get_dma_buffer(virtual_address_space.heap.allocator, 1);
    const result = disk.access(&dma_buffer, .{
        .sector_offset = 0,
        .sector_count = 1,
        .operation = .read,
    }, virtual_address_space);
    assert(result == 1);
    assert(dma_buffer.completed_size == disk.sector_size);

    const possible_signature = @intToPtr([*]const u8, dma_buffer.virtual_address)[0..default_signature.len];
    if (!string_eq(possible_signature, &default_signature)) {
        return InitError.not_found;
    }

    const rnufs = try virtual_address_space.heap.allocator.create(RNUFS);
    rnufs.fs = .{
        .type = .RNU,
        .disk = disk,
        .callback_read_file = read_file,
        .callback_write_file = unreachable,
    };

    try Filesystem.init(device_manager, virtual_address_space, &rnufs.fs);
}

pub fn seek_file(fs_driver: *Filesystem, allocator: Allocator, name: []const u8, extra_context: ?*anyopaque) ?SeekResult {
    const virtual_address_space = @ptrCast(*VirtualAddressSpace, @alignCast(@alignOf(VirtualAddressSpace), extra_context));
    log.debug("Seeking file {s}", .{name});
    const sectors_to_read_at_time = 1;
    const sector_size = fs_driver.disk.sector_size;
    var sector: u64 = @divExact(@sizeOf(Superblock), sector_size);
    var search_buffer = fs_driver.disk.get_dma_buffer(allocator, sectors_to_read_at_time) catch {
        log.err("Unable to allocate search buffer", .{});
        return null;
    };

    while (true) {
        defer search_buffer.completed_size = 0;

        log.debug("FS driver asking read", .{});
        const sectors_read = fs_driver.disk.access(&search_buffer, Disk.Work{
            .sector_offset = sector,
            .sector_count = sectors_to_read_at_time,
            .operation = .read,
        }, virtual_address_space);
        log.debug("FS driver ending read", .{});
        if (sectors_read != sectors_to_read_at_time) panic("Driver internal error: cannot seek file", .{});
        //for (search_buffer.address.access([*]const u8)[0..sector_size]) |byte, i| {
        //if (byte != 0) log.debug("[{}] 0x{x}", .{ i, byte });
        //}
        var node = @intToPtr(*Node, search_buffer.virtual_address);
        if (node.type == .empty) break;
        const node_name_cstr = @ptrCast([*:0]const u8, &node.name);
        const node_name = node_name_cstr[0..cstr_len(node_name_cstr)];
        if (node_name.len == 0) break;

        if (name[0] == 0x00) @panic("Wtf");

        log.debug("Wanted node name: (\"{s}\", {}) (First byte = 0x{x}). This node name: (\"{s}\", {})", .{ name, name.len, name[0], node_name, node_name.len });

        if (string_eq(node_name, name)) {
            return SeekResult{
                .sector = sector,
                .node = node.*,
            };
        }

        log.debug("Names don't match", .{});

        const sectors_to_add = 1 + (div_ceil(u64, node.size, sector_size) catch unreachable);
        log.debug("Sectors to add: {}", .{sectors_to_add});
        sector += sectors_to_add;
    }

    @panic("not found");
}

pub fn read_file(fs_driver: *Filesystem, allocator: Allocator, name: []const u8, extra_context: ?*anyopaque) Filesystem.ReadError![]const u8 {
    const virtual_address_space = @ptrCast(*VirtualAddressSpace, @alignCast(@alignOf(VirtualAddressSpace), extra_context));
    log.debug("About to read file {s}...", .{name});
    if (seek_file(fs_driver, allocator, name, extra_context)) |seek_result| {
        const sector_size = fs_driver.disk.sector_size;
        const node_size = seek_result.node.size;
        log.debug("File size: {}", .{node_size});
        const sector_count = div_ceil(u64, node_size, sector_size) catch unreachable;
        var buffer = fs_driver.disk.get_dma_buffer(allocator, sector_count) catch {
            @panic("Unable to allocate read buffer");
        };
        const sector_offset = seek_result.sector + 1;
        log.debug("Sector offset: {}. Sector count: {}", .{ sector_offset, sector_count });
        // Add one to skip the metadata
        const sectors_read = fs_driver.disk.access(&buffer, Disk.Work{
            .sector_offset = sector_offset,
            .sector_count = sector_count,
            .operation = .read,
        }, virtual_address_space);

        if (sectors_read != sector_count) panic("Driver internal error: cannot read file", .{});

        return @intToPtr([*]const u8, buffer.virtual_address)[0..node_size];
    } else {
        @panic("unable to find file");
    }
}

pub const SeekResult = struct {
    sector: u64,
    node: Node,
};
