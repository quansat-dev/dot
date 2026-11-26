pub const Name = struct {
    pub const capacity = 128;

    bytes: [capacity]u8 = undefined,
    len: usize = 0,

    pub fn set(self: *Name, value: []const u8) void {
        const n = @min(value.len, self.bytes.len);
        @memcpy(self.bytes[0..n], value[0..n]);
        self.len = n;
    }

    pub fn slice(self: *const Name) []const u8 {
        return self.bytes[0..self.len];
    }
};

pub const Action = enum { press, release };

pub const Event = union(enum) {
    key: struct {
        action: Action,
        code: u32,
        state: u32,
        time: u32,
    },
    button: struct {
        action: Action,
        button: u32,
        x: i32,
        y: i32,
    },
    motion: struct {
        x: i32,
        y: i32,
    },
};

pub const AppInfo = struct {
    /// Human-readable label for logging/UI.
    /// Empty means unknown.
    name: Name = .{},

    /// Stable application identifier supplied by the platform/app.
    ///
    /// X11: WM_CLASS class (fallback: instance)
    /// Wayland: xdg_toplevel app_id
    /// macOS: CFBundleIdentifier
    /// Windows: AppUserModelID / package family name / executable fallback
    ///
    /// Empty means unknown. Best-effort, not guaranteed globally unique.
    id: Name = .{},
};

pub fn displayName(app: ?*const AppInfo) []const u8 {
    if (app) |a| {
        if (a.name.len > 0) return a.name.slice();
    }
    return "<unknown>";
}

pub fn displayId(app: ?*const AppInfo) []const u8 {
    if (app) |a| {
        if (a.id.len > 0) return a.id.slice();
    }
    return "<unknown>";
}
