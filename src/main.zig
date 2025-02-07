pub fn main() void {}

const ClassFile = struct {
    constants: []const Constant,
    fields: []const Field,
    attributes: []const Attribute,
};

const Constant = union(enum(u8)) {
    class: Class = 7,
    field_ref: FieldRef = 9,
    method_ref: MethodRef = 10,
    interface_method_ref: InterfaceMethodRef = 11,
    string: String = 8,
    integer: i32 = 3,
    float: f32 = 4,
    long: i64 = 5,
    double: f64 = 6,
    name_and_type: NameAndType = 12,
    utf8: []const u8 = 1,
    method_handle: MethodHandle = 15,
    method_type: MethodType = 16,
    invoke_dynamic: InvokeDynamic = 18,

    const Class = struct {
        name: Index(.utf8),
    };

    const FieldRef = struct {
        class: Index(.class),
        name_and_type: Index(.name_and_type),
    };

    const MethodRef = struct {
        class: Index(.class),
        name_and_type: Index(.name_and_type),
    };

    const InterfaceMethodRef = struct {
        class: Index(.class),
        name_and_type: Index(.name_and_type),
    };

    const String = struct {
        utf8: Index(.utf8),
    };

    const NameAndType = struct {
        name: Index(.utf8),
        descriptor: Index(.utf8),
    };

    const MethodHandle = struct {
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

    const MethodType = struct {
        descriptor: Index(.utf8),
    };

    const InvokeDynamic = struct {
        bootstrap_method_attr: BootstrapMethodIndex,
        name_and_type: Index(.name_and_type),
    };
};

const Field = struct {
    access: Access,
    name: Index(.utf8),
    descriptor: Index(.utf8),
    attributes: []const Attribute,

    const Access = struct {
        public: bool,
        private: bool,
        protected: bool,
        static: bool,
        final: bool,
        @"volatile": bool,
        transient: bool,
        synthetic: bool,
        @"enum": bool,
    };
};

const Method = struct {
    access: Access,
    name: Index(.utf8),
    descriptor: Index(.utf8),
    attributes: []const Attribute,

    const Access = struct {
        public: bool,
        private: bool,
        protected: bool,
        static: bool,
        final: bool,
        synchronized: bool,
        bridge: bool,
        varargs: bool,
        native: bool,
        abstract: bool,
        strict: bool,
        synthetic: bool,
    };
};

const Attribute = struct {
    name: Index(.utf8),
    info: []const u8,
};

fn Index(kind: @typeInfo(Constant).@"enum".tag_type) type {
    return enum(u16) {
        comptime {
            _ = kind;
        }
        _,
    };
}

const UntypedConstantIndex = enum(u16) { _ };

const BootstrapMethodIndex = enum(u16) { _ };
