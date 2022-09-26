const std = @import("../common.zig");
const zig_std = @import("std");

comptime {
    if (os == .freestanding) @compileError("This is only meant to be imported in build.zig");
}

pub const Builder = zig_std.build.Builder;
pub const FileSource = zig_std.build.FileSource;
pub const LibExeObjStep = zig_std.build.LibExeObjStep;
pub const OptionsStep = zig_std.build.OptionsStep;
pub const Package = zig_std.build.Pkg;
pub const RunStep = zig_std.build.RunStep;
pub const Step = zig_std.build.Step;
pub const WriteFileStep = zig_std.build.WriteFileStep;

pub const Target = zig_std.Target;
pub const Arch = Target.Cpu.Arch;
pub const CrossTarget = zig_std.zig.CrossTarget;

pub const os = @import("builtin").target.os.tag;
pub const arch = @import("builtin").target.cpu.arch;

pub const print = zig_std.debug.print;
pub const log = std.log;

pub const fork = zig_std.os.fork;
pub const ChildProcess = zig_std.ChildProcess;
pub const waitpid = zig_std.os.waitpid;

const CustomAllocator = std.CustomAllocator;

pub fn allocate_zero_memory(bytes: u64) ![]align(0x1000) u8 {
    switch (os) {
        .windows => {
            const windows = zig_std.os.windows;
            return @ptrCast([*]align(0x1000) u8, try windows.VirtualAlloc(null, bytes, windows.MEM_RESERVE | windows.MEM_COMMIT, windows.PAGE_READWRITE))[0..bytes];
        },
        else => {
            const mmap = zig_std.os.mmap;
            const PROT = zig_std.os.PROT;
            const MAP = zig_std.os.MAP;
            return try mmap(null, bytes, PROT.READ | PROT.WRITE, MAP.PRIVATE | MAP.ANONYMOUS, -1, 0);
        },
    }
}

pub fn get_allocator(builder: *Builder) CustomAllocator {
    return CustomAllocator{
        .callback_allocate = allocate,
        .context = builder,
    };
}
pub const zero_allocator = CustomAllocator{ .allocate = zero_allocate, .context = null };

fn allocate(allocator: CustomAllocator, size: u64, alignment: u64) CustomAllocator.Error!CustomAllocator.Result {
    const builder = @ptrCast(*Builder, @alignCast(@alignOf(Builder), allocator.context));
    const result = builder.allocator.allocBytes(@intCast(u29, alignment), size, 0, 0) catch unreachable;
    return CustomAllocator.Result{
        .address = @ptrToInt(result.ptr),
        .size = result.len,
    };
}

fn zero_allocate(allocator: CustomAllocator, size: u64, alignment: u64) CustomAllocator.Result {
    _ = allocator;
    std.assert(alignment <= 0x1000);
    const result = allocate_zero_memory(size) catch unreachable;
    return CustomAllocator.Result{
        .address = @ptrToInt(result.ptr),
        .size = result.size,
    };
}

pub const cwd = zig_std.fs.cwd;
pub const Dir = zig_std.fs.Dir;
pub const path = zig_std.fs.path;
pub const basename = zig_std.fs.path.basename;
pub const dirname = zig_std.fs.path.dirname;

pub const QEMU = @import("../common/qemu/common.zig");

pub fn add_qemu_debug_isa_exit(builder: *Builder, list: *std.ArrayListManaged([]const u8), qemu_debug_isa_exit: QEMU.ISADebugExit) !void {
    try list.append("-device");
    try list.append(builder.fmt("isa-debug-exit,iobase=0x{x},iosize=0x{x}", .{ qemu_debug_isa_exit.port, qemu_debug_isa_exit.size }));
}

pub const Disk = struct {
    const BufferType = std.ArrayListAligned(u8, 0x1000);
    //disk: DiskInterface,
    buffer: BufferType,

    fn access(disk: *Disk, extra_context: ?*anyopaque) u64 {
        _ = disk;
        _ = extra_context;
        @panic("todo disk access");
        //const build_disk = @fieldParentPtr(Disk, "disk", disk);
        //_ = extra_context;
        //const sector_size = disk.sector_size;
        ////log.debug("Disk work: {}", .{disk_work});
        //switch (disk_work.operation) {
        //.write => {
        //const work_byte_size = disk_work.sector_count * sector_size;
        //const byte_count = work_byte_size;
        //const write_source_buffer = @intToPtr([*]const u8, buffer.virtual_address)[0..byte_count];
        //const disk_slice_start = disk_work.sector_offset * sector_size;
        //log.debug("Disk slice start: {}. Disk len: {}", .{ disk_slice_start, build_disk.buffer.items.len });
        //std.assert(disk_slice_start == build_disk.buffer.items.len);
        //build_disk.buffer.appendSliceAssumeCapacity(write_source_buffer);

        //return byte_count;
        //},
        //.read => {
        //const offset = disk_work.sector_offset * sector_size;
        //const bytes = disk_work.sector_count * sector_size;
        //const previous_len = build_disk.buffer.items.len;

        //if (offset >= previous_len or offset + bytes > previous_len) build_disk.buffer.items.len = build_disk.buffer.capacity;
        //std.copy(u8, @intToPtr([*]u8, buffer.virtual_address)[0..bytes], build_disk.buffer.items[offset .. offset + bytes]);
        //if (offset >= previous_len or offset + bytes > previous_len) build_disk.buffer.items.len = previous_len;

        //return disk_work.sector_count;
        //},
        //}
    }

    //fn get_dma_buffer(disk: *Disk, allocator: CustomAllocator, sector_count: u64) CustomAllocator.Error!DMA.Buffer {
    //const allocation_size = disk.sector_size * sector_count;
    //const alignment = 0x1000;
    //log.debug("DMA buffer allocation size: {}, alignment: {}", .{ allocation_size, alignment });
    //return DMA.Buffer.new(allocator, allocation_size, alignment);
    //}

    pub fn new(buffer: BufferType) Disk {
        _ = buffer;
        @panic("todo disk dma buffer");
        //return Disk{
        //.disk = DiskInterface{
        //.sector_size = 0x200,
        //.access = access,
        //.get_dma_buffer = get_dma_buffer,
        //.type = .memory,
        //},
        //.buffer = buffer,
        //};
    }
};

pub const Dependency = struct {
    type: Type,
    path: []const u8,
    dependencies: []const *const Dependency,

    pub fn from_source_file(source_file: anytype) *const Dependency {
        return &source_file.dependency.dependency;
    }

    pub fn get_path_to_file(dependency: Dependency, allocator: std.Allocator, file: []const u8) []const u8 {
        const directory_length = std.last_index_of(u8, dependency.path, "dependency.zig") orelse unreachable;
        const directory_path = dependency.path[0..directory_length];
        const path_to_file = std.concatenate(allocator, u8, &.{ directory_path, file }) catch unreachable;
        return path_to_file;
    }

    fn get_program_name(dependency: Dependency) []const u8 {
        const directory_length = std.last_index_of(u8, dependency.path, "/dependency.zig") orelse unreachable;
        const directory_path = dependency.path[0..directory_length];
        const directory_name = basename(directory_path);
        return directory_name;
    }

    pub const Type = enum(u32) {
        zig_exe = 0,
        zig_static_lib = 1,
        zig_dynamic_lib = 2,
        c_objects = 3,
    };
};

pub const CObject = struct {
    dependency: Dependency,
    objects: []const []const u8,
};

pub const UserProgram = struct {
    dependency: Dependency,
    path: []const u8 = undefined,
    name: []const u8 = undefined,

    pub fn make(allocator: std.Allocator, dependencies_file: anytype) UserProgram {
        var zig_exe = dependencies_file.dependency;
        std.assert(zig_exe.dependency.type == .zig_exe);
        zig_exe.path = zig_exe.dependency.get_path_to_file(allocator, "main.zig");
        zig_exe.name = zig_exe.dependency.get_program_name();

        return zig_exe;
    }
};

pub const Filesystem = struct {
    pub fn new(disk: *Disk) Filesystem {
        _ = disk;
        @panic("todo filesystem new");
        // TODO: copy signature
        //const rnufs_signature = Build.Filesystem.get_signature();
        //build_disk.buffer.items.len = Build.Filesystem.get_superblock_size();

        //for (rnufs_signature) |signature_byte, byte_i| {
        //const dst_byte = &build_disk.buffer.items[byte_i];
        //dst_byte.* = signature_byte;
        //}
    }

    pub fn get_signature() []const u8 {
        @panic("todo get signature");
    }

    pub fn write_file(filesystem: *Filesystem, file_content: []const u8) void {
        _ = filesystem;
        _ = file_content;
        @panic("todo write_file");
    }
};
