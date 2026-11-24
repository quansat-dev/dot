const std = @import("std");
const c = @import("c");

const key_press: u8 = @intCast(c.KeyPress);
const key_release: u8 = @intCast(c.KeyRelease);
const button_press: u8 = @intCast(c.ButtonPress);
const button_release: u8 = @intCast(c.ButtonRelease);
const motion_notify: u8 = @intCast(c.MotionNotify);
const pointer_root: c.Window = @intCast(c.PointerRoot);
const record_from_server: c_int = c.XRecordFromServer;

const Name = struct {
    pub const capacity = 128;

    bytes: [capacity]u8 = undefined,
    len: usize = 0,

    fn set(self: *Name, value: []const u8) void {
        const n = @min(value.len, self.bytes.len);
        @memcpy(self.bytes[0..n], value[0..n]);
        self.len = n;
    }

    fn slice(self: *const Name) []const u8 {
        return self.bytes[0..self.len];
    }
};

const AppInfo = struct {
    window: c.Window,
    pid: ?u32 = null,
    process_name: Name = .{},
    wm_class: Name = .{},
};

const Atoms = struct {
    net_active_window: c.Atom,
    net_wm_pid: c.Atom,
    wm_class: c.Atom,
};

const Property = struct {
    format: c_int,
    items: c_ulong,
    data: [*c]u8,
};

const Listener = struct {
    display: *c.Display,
    atoms: Atoms,
    cache: std.AutoHashMap(c.Window, ?AppInfo),

    fn init(display: *c.Display) !Listener {
        const net_active_window = c.XInternAtom(display, "_NET_ACTIVE_WINDOW", 0);
        const net_wm_pid = c.XInternAtom(display, "_NET_WM_PID", 0);
        const wm_class = c.XInternAtom(display, "WM_CLASS", 0);

        if (net_active_window == 0 or net_wm_pid == 0 or wm_class == 0)
            return error.AtomInternFailed;

        return .{
            .display = display,
            .atoms = .{
                .net_active_window = net_active_window,
                .net_wm_pid = net_wm_pid,
                .wm_class = wm_class,
            },
            .cache = std.AutoHashMap(c.Window, ?AppInfo).init(std.heap.page_allocator),
        };
    }

    fn deinit(self: *Listener) void {
        self.cache.deinit();
    }

    fn activeApp(self: *Listener) ?AppInfo {
        const window = activeAppWindow(self) orelse return null;

        if (self.cache.get(window)) |cached| return cached;

        const info = lookupAppInfo(self.display, self.atoms, window);
        self.cache.put(window, info) catch {};
        return info;
    }
};

fn getProperty(
    display: *c.Display,
    window: c.Window,
    atom: c.Atom,
    expected_type: c.Atom,
    long_length: c_long,
) ?Property {
    var actual_type: c.Atom = 0;
    var actual_format: c_int = 0;
    var items: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var data: [*c]u8 = null;

    const status = c.XGetWindowProperty(
        display,
        window,
        atom,
        0,
        long_length,
        0,
        expected_type,
        &actual_type,
        &actual_format,
        &items,
        &bytes_after,
        &data,
    );

    if (status != c.Success or actual_type != expected_type or data == null) {
        if (data != null) _ = c.XFree(@ptrCast(data));
        return null;
    }

    return .{
        .format = actual_format,
        .items = items,
        .data = data,
    };
}

fn readWindowAtom(display: *c.Display, window: c.Window, atom: c.Atom) ?c.Window {
    const property = getProperty(display, window, atom, c.XA_WINDOW, 1) orelse return null;
    defer _ = c.XFree(@ptrCast(property.data));

    if (property.format != 32 or property.items < 1) return null;

    const value_ptr: *const c_ulong = @ptrCast(@alignCast(property.data));
    return @intCast(value_ptr.*);
}

fn readPid(display: *c.Display, window: c.Window, atom: c.Atom) ?u32 {
    const property = getProperty(display, window, atom, c.XA_CARDINAL, 1) orelse return null;
    defer _ = c.XFree(@ptrCast(property.data));

    if (property.format != 32 or property.items < 1) return null;

    const value_ptr: *const c_ulong = @ptrCast(@alignCast(property.data));
    return @truncate(value_ptr.*);
}

fn readWmClass(display: *c.Display, window: c.Window, atom: c.Atom, out: *Name) void {
    const property = getProperty(display, window, atom, c.XA_STRING, 64) orelse return;
    defer _ = c.XFree(@ptrCast(property.data));

    if (property.format != 8 or property.items < 1) return;

    const bytes = property.data[0..@intCast(property.items)];
    const first_zero = std.mem.indexOfScalar(u8, bytes, 0) orelse return;
    const instance = bytes[0..first_zero];

    const rest = bytes[first_zero + 1 ..];
    const class_len = std.mem.indexOfScalar(u8, rest, 0) orelse rest.len;
    const class = rest[0..class_len];

    out.set(if (class.len > 0) class else instance);
}

fn readProcessName(pid: u32, out: *Name) void {
    var path_buffer: [64]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buffer, "/proc/{d}/comm", .{pid}) catch return;

    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch return;
    defer _ = std.os.linux.close(fd);

    var raw: [Name.capacity]u8 = undefined;
    const n = std.posix.read(fd, &raw) catch return;

    var name: []const u8 = raw[0..n];
    if (std.mem.indexOfScalar(u8, name, 0)) |zero| name = name[0..zero];
    name = std.mem.trimEnd(u8, name, "\r\n");

    out.set(name);
}

fn hasAppProperties(display: *c.Display, atoms: Atoms, window: c.Window) bool {
    if (readPid(display, window, atoms.net_wm_pid) != null) return true;

    var class = Name{};
    readWmClass(display, window, atoms.wm_class, &class);
    return class.len > 0;
}

fn resolveAppWindow(display: *c.Display, root: c.Window, atoms: Atoms, start: c.Window) ?c.Window {
    var window = start;
    var depth: usize = 0;

    while (depth < 64) : (depth += 1) {
        if (window == 0 or window == root) return null;

        // Stop as soon as a window looks like an application window. Walking
        // all the way to the top would often land on a WM frame instead.
        if (hasAppProperties(display, atoms, window)) return window;

        var root_return: c.Window = 0;
        var parent_return: c.Window = 0;
        var children_return: [*c]c.Window = null;
        var children_count: c_uint = 0;

        const status = c.XQueryTree(
            display,
            window,
            &root_return,
            &parent_return,
            &children_return,
            &children_count,
        );

        if (children_return != null) _ = c.XFree(@ptrCast(children_return));
        if (status == 0) return null;

        if (parent_return == 0 or parent_return == root or parent_return == window)
            return window;

        window = parent_return;
    }

    return window;
}

fn windowUnderPointer(display: *c.Display, root: c.Window, atoms: Atoms) ?c.Window {
    var root_return: c.Window = 0;
    var child_return: c.Window = 0;
    var root_x: c_int = 0;
    var root_y: c_int = 0;
    var win_x: c_int = 0;
    var win_y: c_int = 0;
    var mask: c_uint = 0;

    if (c.XQueryPointer(
        display,
        root,
        &root_return,
        &child_return,
        &root_x,
        &root_y,
        &win_x,
        &win_y,
        &mask,
    ) == 0) return null;

    if (child_return == 0 or child_return == root) return null;
    return resolveAppWindow(display, root, atoms, child_return) orelse child_return;
}

fn activeAppWindow(listener: *Listener) ?c.Window {
    const display = listener.display;
    const root = c.XDefaultRootWindow(display);

    // EWMH window managers publish their active window here. This is already
    // the application window, not a WM frame.
    if (readWindowAtom(display, root, listener.atoms.net_active_window)) |window| {
        if (window != 0 and window != root)
            return resolveAppWindow(display, root, listener.atoms, window) orelse window;
    }

    // Core X11 fallback: keyboard focus.
    var focus: c.Window = 0;
    var revert_to: c_int = 0;
    if (c.XGetInputFocus(display, &focus, &revert_to) == 0) return null;

    if (focus == 0) return null;
    if (focus == pointer_root) return windowUnderPointer(display, root, listener.atoms);
    if (focus == root) return null;

    return resolveAppWindow(display, root, listener.atoms, focus) orelse focus;
}

fn lookupAppInfo(display: *c.Display, atoms: Atoms, window: c.Window) AppInfo {
    var info = AppInfo{ .window = window };

    if (readPid(display, window, atoms.net_wm_pid)) |pid| {
        info.pid = pid;
        readProcessName(pid, &info.process_name);
    }

    readWmClass(display, window, atoms.wm_class, &info.wm_class);
    return info;
}

fn appName(info: ?*const AppInfo) []const u8 {
    if (info) |app| {
        if (app.wm_class.len > 0) return app.wm_class.slice();
        if (app.process_name.len > 0) return app.process_name.slice();
    }
    return "<unknown>";
}

fn appPid(info: ?*const AppInfo) u32 {
    if (info) |app| return app.pid orelse 0;
    return 0;
}

fn appWindow(info: ?*const AppInfo) c.Window {
    if (info) |app| return app.window;
    return 0;
}

fn onRecord(closure: c.XPointer, raw: [*c]c.XRecordInterceptData) callconv(.c) void {
    if (raw == null) return;
    const data: *c.XRecordInterceptData = @ptrCast(&raw[0]);
    defer c.XRecordFreeData(raw);

    if (data.category != record_from_server) return;

    const byte_len: usize = @intCast(data.data_len * 4);
    if (byte_len != @sizeOf(c.xEvent)) return;

    const bytes = data.data[0..byte_len];
    const event: *const c.xEvent = @ptrCast(@alignCast(bytes.ptr));

    const listener: *Listener = @ptrCast(@alignCast(closure));
    const app: ?*const AppInfo = if (listener.activeApp()) |*app| app else null;

    switch (event.u.u.type) {
        key_press, key_release => std.debug.print(
            "key {s} code={d} state={d} time={d} app={s} pid={d} window=0x{x}\n",
            .{
                if (event.u.u.type == key_press) "press" else "release",
                event.u.u.detail,
                event.u.keyButtonPointer.state,
                event.u.keyButtonPointer.time,
                appName(app),
                appPid(app),
                appWindow(app),
            },
        ),
        button_press, button_release => std.debug.print(
            "mouse {s} button={d} x={d} y={d} app={s} pid={d} window=0x{x}\n",
            .{
                if (event.u.u.type == button_press) "press" else "release",
                event.u.u.detail,
                event.u.keyButtonPointer.rootX,
                event.u.keyButtonPointer.rootY,
                appName(app),
                appPid(app),
                appWindow(app),
            },
        ),
        motion_notify => std.debug.print(
            "mouse move x={d} y={d} app={s} pid={d} window=0x{x}\n",
            .{
                event.u.keyButtonPointer.rootX,
                event.u.keyButtonPointer.rootY,
                appName(app),
                appPid(app),
                appWindow(app),
            },
        ),
        else => {},
    }
}

fn run() !void {
	// connection to give instructions
    const control = c.XOpenDisplay(null) orelse return error.ControlDisplayOpenFailed;
    defer _ = c.XCloseDisplay(control);

	// connection to receive stream of events
    const data = c.XOpenDisplay(null) orelse return error.DataDisplayOpenFailed;
    defer _ = c.XCloseDisplay(data);

    var listener = try Listener.init(control);
    defer {
        listener.deinit();
    }

    var major: c_int = 0;
    var minor: c_int = 0;
    if (c.XRecordQueryVersion(control, &major, &minor) == 0)
        return error.RecordExtensionUnavailable;

	// ask libXtst to allocate for XRecordRange
    const range_ptr = c.XRecordAllocRange();
    if (range_ptr == null) return error.OutOfMemory;
    defer c.free(@ptrCast(range_ptr));

	// set to record only events of interest
    const range: *c.XRecordRange = @ptrCast(&range_ptr[0]);
    range.* = std.mem.zeroes(c.XRecordRange);
    range.device_events.first = key_press;
    range.device_events.last = motion_notify;
	var ranges = [_][*c]c.XRecordRange{range_ptr};

	// set to record all clients
    var clients = [_]c.XRecordClientSpec{@intCast(c.XRecordAllClients)};

    const ctx = c.XRecordCreateContext(control, 0, &clients, 1, &ranges, 1);
    if (ctx == 0) return error.ContextCreationFailed;
    defer _ = c.XRecordFreeContext(control, ctx);

    // The context is created on the control connection but enabled on the data
    // connection. Flush first so the server knows the context before the data
    // connection references it.
    _ = c.XSync(control, 0);

    std.debug.print("dot engine: listening on X11 RECORD (keyboard + mouse)\n", .{});

    if (c.XRecordEnableContext(data, ctx, onRecord, @ptrCast(&listener)) == 0)
        return error.ContextEnableFailed;
}

pub fn main() void {
    run() catch |err| {
        std.debug.print("dot engine: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
