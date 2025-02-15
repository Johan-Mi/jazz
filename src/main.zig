const std = @import("std");

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const buffer = try std.io.getStdIn().readToEndAlloc(allocator, std.math.maxInt(usize));
    const class_file: ClassFile = try .init(buffer, allocator);
    std.log.debug("{}", .{class_file});
}

const ClassFile = struct {
    constants: []const Constant,
    fields: []const Field,
    attributes: []const Attribute,

    fn init(buffer: []const u8, arena: std.mem.Allocator) !@This() {
        var stream = std.io.fixedBufferStream(buffer);
        const reader = stream.reader();
        const magic = try reader.readInt(u32, .big);
        if (magic != 0xcafebabe) return error.InvalidMagic;
        const minor_version = try reader.readInt(u16, .big);
        const major_version = try reader.readInt(u16, .big);
        _ = .{ minor_version, major_version };
        const constants = try arena.alloc(
            Constant,
            std.math.sub(u16, try reader.readInt(u16, .big), 1) catch
                return error.InvalidConstantPoolSize,
        );
        {
            var pending_large = false;
            for (constants) |*it| {
                it.* = if (pending_large) .invalid else try .read(&stream);
                pending_large = Constant.Kind.isLarge(it.*);
            }
        }
        try reader.skipBytes(2 + 2 + 2, .{}); // access_flags, this_class, super_class
        try reader.skipBytes(try reader.readInt(u16, .big) * 2, .{}); // interfaces
        const fields = try arena.alloc(Field, try reader.readInt(u16, .big));
        for (fields) |*it| it.* = try .read(&stream, arena);
        const methods = try arena.alloc(Method, try reader.readInt(u16, .big));
        for (methods) |*it| it.* = try .read(&stream, arena);
        const attributes = try arena.alloc(Attribute, try reader.readInt(u16, .big));
        for (attributes) |*it| it.* = try .read(&stream);
        return .{ .constants = constants, .fields = fields, .attributes = attributes };
    }
};

const Constant = union(Constant.Kind) {
    const Kind = enum(u8) {
        class = 7,
        field_ref = 9,
        method_ref = 10,
        interface_method_ref = 11,
        string = 8,
        integer = 3,
        float = 4,
        long = 5,
        double = 6,
        name_and_type = 12,
        utf8 = 1,
        method_handle = 15,
        method_type = 16,
        invoke_dynamic = 18,
        invalid = 0,

        fn isLarge(self: @This()) bool {
            return switch (self) {
                .long, .double => true,
                else => false,
            };
        }
    };

    class: Class,
    field_ref: FieldRef,
    method_ref: MethodRef,
    interface_method_ref: InterfaceMethodRef,
    string: String,
    integer: i32,
    float: f32,
    long: i64,
    double: f64,
    name_and_type: NameAndType,
    utf8: []const u8,
    method_handle: MethodHandle,
    method_type: MethodType,
    invoke_dynamic: InvokeDynamic,
    invalid,

    const Class = extern struct {
        name: Index(.utf8),
    };

    const FieldRef = extern struct {
        class: Index(.class),
        name_and_type: Index(.name_and_type),
    };

    const MethodRef = extern struct {
        class: Index(.class),
        name_and_type: Index(.name_and_type),
    };

    const InterfaceMethodRef = extern struct {
        class: Index(.class),
        name_and_type: Index(.name_and_type),
    };

    const String = extern struct {
        utf8: Index(.utf8),
    };

    const NameAndType = extern struct {
        name: Index(.utf8),
        descriptor: Index(.utf8),
    };

    const MethodHandle = extern struct {
        reference_kind: enum(u8) {
            get_field = 1,
            get_static = 2,
            put_field = 3,
            put_static = 4,
            invoke_virtual = 5,
            invoke_static = 6,
            invoke_special = 7,
            new_invoke_special = 8,
            invoke_interface = 9,
        },
        reference_index: UntypedConstantIndex,
    };

    const MethodType = extern struct {
        descriptor: Index(.utf8),
    };

    const InvokeDynamic = extern struct {
        bootstrap_method_attr: BootstrapMethodIndex,
        name_and_type: Index(.name_and_type),
    };

    fn read(stream: *std.io.FixedBufferStream([]const u8)) !@This() {
        const reader = stream.reader();
        return switch (try reader.readEnum(Kind, .big)) {
            .integer => .{ .integer = try reader.readInt(i32, .big) },
            .float => .{ .float = @bitCast(try reader.readInt(u32, .big)) },
            .long => .{ .long = try reader.readInt(i64, .big) },
            .double => .{ .double = @bitCast(try reader.readInt(u64, .big)) },
            .utf8 => blk: {
                const len = try reader.readInt(u16, .big);
                if (stream.buffer.len - stream.pos < len) return error.EndOfStream;
                defer stream.pos += len;
                break :blk .{ .utf8 = stream.buffer[stream.buffer.len..][0..len] };
            },
            .invalid => return error.InvalidValue,
            inline else => |tag| @unionInit(
                @This(),
                @tagName(tag),
                try reader.readStructEndian(@TypeOf( // We have `@FieldType` at home
                    @field(@unionInit(@This(), @tagName(tag), undefined), @tagName(tag)),
                ), .big),
            ),
        };
    }
};

const Field = struct {
    access: Access,
    name: Index(.utf8),
    descriptor: Index(.utf8),
    attributes: []const Attribute,

    const Access = packed struct {
        public: bool,
        private: bool,
        protected: bool,
        static: bool,
        final: bool,
        _: bool,
        @"volatile": bool,
        transient: bool,
        synthetic: bool,
        @"enum": bool,
    };

    fn read(stream: *std.io.FixedBufferStream([]const u8), arena: std.mem.Allocator) !@This() {
        const reader = stream.reader();
        const raw_access = try reader.readInt(u16, .big);
        const name = try reader.readEnum(Index(.utf8), .big);
        const descriptor = try reader.readEnum(Index(.utf8), .big);
        const attributes = try arena.alloc(Attribute, try reader.readInt(u16, .big));
        for (attributes) |*it| it.* = try .read(stream);
        return .{
            .access = @bitCast(@as(u10, @truncate(raw_access))),
            .name = name,
            .descriptor = descriptor,
            .attributes = attributes,
        };
    }
};

const Method = struct {
    access: Access,
    name: Index(.utf8),
    descriptor: Index(.utf8),
    attributes: []const Attribute,

    const Access = packed struct {
        public: bool,
        private: bool,
        protected: bool,
        static: bool,
        final: bool,
        synchronized: bool,
        bridge: bool,
        varargs: bool,
        native: bool,
        _: bool,
        abstract: bool,
        strict: bool,
        synthetic: bool,
    };

    fn read(stream: *std.io.FixedBufferStream([]const u8), arena: std.mem.Allocator) !@This() {
        const reader = stream.reader();
        const raw_access = try reader.readInt(u16, .big);
        const name = try reader.readEnum(Index(.utf8), .big);
        const descriptor = try reader.readEnum(Index(.utf8), .big);
        const attributes = try arena.alloc(Attribute, try reader.readInt(u16, .big));
        for (attributes) |*it| it.* = try .read(stream);
        return .{
            .access = @bitCast(@as(u13, @truncate(raw_access))),
            .name = name,
            .descriptor = descriptor,
            .attributes = attributes,
        };
    }
};

const Attribute = struct {
    name: Index(.utf8),
    info: []const u8,

    fn read(stream: *std.io.FixedBufferStream([]const u8)) !@This() {
        const reader = stream.reader();
        const name = try reader.readEnum(Index(.utf8), .big);
        const len = try reader.readInt(u32, .big);
        if (stream.buffer.len - stream.pos < len) return error.EndOfStream;
        defer stream.pos += len;
        return .{ .name = name, .info = stream.buffer[stream.buffer.len..][0..len] };
    }
};

fn Index(kind: Constant.Kind) type {
    return enum(u16) {
        comptime {
            _ = kind;
        }
        _,
    };
}

const UntypedConstantIndex = enum(u16) { _ };

const BootstrapMethodIndex = enum(u16) { _ };
