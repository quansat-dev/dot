const std = @import("std");
const x11_c = @import("x11_c");
const model = @import("model");
const api = @import("platform_api");

const Name = model.Name;

const key_press: u8 = @intCast(x11_c.KeyPress);
const key_release: u8 = @intCast(x11_c.KeyRelease);
const button_press: u8 = @intCast(x11_c.ButtonPress);
const button_release: u8 = @intCast(x11_c.ButtonRelease);
const motion_notify: u8 = @intCast(x11_c.MotionNotify);
const pointer_root: x11_c.Window = @intCast(x11_c.PointerRoot);
const record_from_server: c_int = x11_c.XRecordFromServer;

pub const Backend = struct {
    control: *x11_c.Display,
    data: *x11_c.Display,
    atoms: Atoms,
    cache: std.AutoHashMap(u64, ?model.AppInfo),
    allocator: std.mem.Allocator,

    /// Closes both X11 connections and releases the app-info cache.
    pub fn deinit(self: *Backend) void {
        self.cache.deinit();
        _ = x11_c.XCloseDisplay(self.data);
        _ = x11_c.XCloseDisplay(self.control);
    }

    /// Configures the XRecord context and blocks while delivering decoded events
    /// to `sink`.
    ///
    /// Configuration uses the control connection; the event stream uses the data
    /// connection. The context is created before it is enabled on `data`.
    pub fn listen(self: *Backend, sink: api.Sink) !void {
        var major: c_int = 0;
        var minor: c_int = 0;
        if (x11_c.XRecordQueryVersion(self.control, &major, &minor) == 0)
            return error.RecordExtensionUnavailable;

        const range_ptr = x11_c.XRecordAllocRange();
        if (range_ptr == null) return error.OutOfMemory;
        defer x11_c.free(@ptrCast(range_ptr));

        const range: *x11_c.XRecordRange = @ptrCast(&range_ptr[0]);
        range.* = std.mem.zeroes(x11_c.XRecordRange);
        range.device_events.first = key_press;
        range.device_events.last = motion_notify;
        var ranges = [_][*c]x11_c.XRecordRange{range_ptr};

        var clients = [_]x11_c.XRecordClientSpec{@intCast(x11_c.XRecordAllClients)};

        const ctx = x11_c.XRecordCreateContext(self.control, 0, &clients, 1, &ranges, 1);
        if (ctx == 0) return error.ContextCreationFailed;
        defer _ = x11_c.XRecordFreeContext(self.control, ctx);

        // The context is created on the control connection but enabled on the data
        // connection. Flush first so the server knows the context before the data
        // connection references it.
        _ = x11_c.XSync(self.control, 0);

        std.debug.print("dot engine: listening on X11 RECORD (keyboard + mouse)\n", .{});

        var closure = Closure{ .backend = self, .sink = sink };
        if (x11_c.XRecordEnableContext(self.data, ctx, onRecord, @ptrCast(&closure)) == 0)
            return error.ContextEnableFailed;
    }

    /// Returns the active application for the current X11 focus/active-window state.
    ///
    /// Results are cached by X11 window id, including negative lookups.
    pub fn activeApp(self: *Backend) ?model.AppInfo {
        const window = activeAppWindow(self) orelse return null;
        const id = windowId(window);

        if (self.cache.get(id)) |cached| return cached;

        const info = lookupAppInfo(self, window);
        self.cache.put(id, info) catch {};
        return info;
    }
};

const Atoms = struct {
    net_active_window: x11_c.Atom,
    net_wm_pid: x11_c.Atom,
    wm_class: x11_c.Atom,
};

const Property = struct {
    format: c_int,
    items: c_ulong,
    data: [*c]u8,
};

const WmClass = struct {
    instance: Name,
    class: Name,
};

const Closure = struct {
    backend: *Backend,
    sink: api.Sink,
};

/// Opens the control and data X11 displays and interns the atoms used by the
/// backend.
pub fn init(allocator: std.mem.Allocator) !Backend {
    const control = x11_c.XOpenDisplay(null) orelse return error.ControlDisplayOpenFailed;
    errdefer _ = x11_c.XCloseDisplay(control);

    const data = x11_c.XOpenDisplay(null) orelse return error.DataDisplayOpenFailed;
    errdefer _ = x11_c.XCloseDisplay(data);

    const atoms = try internAtoms(control);

    return .{
        .control = control,
        .data = data,
        .atoms = atoms,
        .cache = std.AutoHashMap(u64, ?model.AppInfo).init(allocator),
        .allocator = allocator,
    };
}

/// Interns the EWMH and X11 property atoms used for active-app lookup.
///
/// Returns `error.AtomInternFailed` if any atom id is zero.
fn internAtoms(display: *x11_c.Display) !Atoms {
    const net_active_window = x11_c.XInternAtom(display, "_NET_ACTIVE_WINDOW", 0);
    const net_wm_pid = x11_c.XInternAtom(display, "_NET_WM_PID", 0);
    const wm_class = x11_c.XInternAtom(display, "WM_CLASS", 0);

    if (net_active_window == 0 or net_wm_pid == 0 or wm_class == 0)
        return error.AtomInternFailed;

    return .{
        .net_active_window = net_active_window,
        .net_wm_pid = net_wm_pid,
        .wm_class = wm_class,
    };
}

/// Converts an X11 window id to the opaque cache key used by the backend.
fn windowId(window: x11_c.Window) u64 {
    return @intCast(window);
}

/// Converts a raw X11 event delivered by XRecord into a platform-neutral event.
///
/// Returns `null` for event types the engine does not report.
fn translateEvent(raw: *const x11_c.xEvent) ?model.Event {
    return switch (raw.u.u.type) {
        key_press, key_release => model.Event{ .key = .{
            .action = if (raw.u.u.type == key_press) .press else .release,
            .code = @intCast(raw.u.u.detail),
            .state = @intCast(raw.u.keyButtonPointer.state),
            .time = @truncate(raw.u.keyButtonPointer.time),
        } },
        button_press, button_release => model.Event{ .button = .{
            .action = if (raw.u.u.type == button_press) .press else .release,
            .button = @intCast(raw.u.u.detail),
            .x = @intCast(raw.u.keyButtonPointer.rootX),
            .y = @intCast(raw.u.keyButtonPointer.rootY),
        } },
        motion_notify => model.Event{ .motion = .{
            .x = @intCast(raw.u.keyButtonPointer.rootX),
            .y = @intCast(raw.u.keyButtonPointer.rootY),
        } },
        else => null,
    };
}

/// C ABI callback invoked by XRecord with intercepted X11 data.
///
/// Filters bookkeeping records, decodes one X11 event, resolves the active app,
/// and forwards both to the sink. `closure` points to the `Closure` stack value
/// owned by `listen`.
fn onRecord(closure: x11_c.XPointer, raw: [*c]x11_c.XRecordInterceptData) callconv(.c) void {
    if (raw == null) return;
    const data: *x11_c.XRecordInterceptData = @ptrCast(&raw[0]);
    defer x11_c.XRecordFreeData(raw);

    if (data.category != record_from_server) return;

    const byte_len: usize = @intCast(data.data_len * 4);
    if (byte_len != @sizeOf(x11_c.xEvent)) return;

    const bytes = data.data[0..byte_len];
    const raw_event: *const x11_c.xEvent = @ptrCast(@alignCast(bytes.ptr));

    const event = translateEvent(raw_event) orelse return;

    const ctx: *Closure = @ptrCast(@alignCast(closure));
    var app = ctx.backend.activeApp();

    ctx.sink.on_event(
        ctx.sink.context,
        event,
        if (app) |*a| a else null,
    );
}

/// Reads an X11 window property with `XGetWindowProperty`.
///
/// The caller owns `Property.data` and must release it with `XFree`.
fn getProperty(
    display: *x11_c.Display,
    window: x11_c.Window,
    atom: x11_c.Atom,
    expected_type: x11_c.Atom,
    long_length: c_long,
) ?Property {
    var actual_type: x11_c.Atom = 0;
    var actual_format: c_int = 0;
    var items: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var data: [*c]u8 = null;

    const status = x11_c.XGetWindowProperty(
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

    if (status != x11_c.Success or actual_type != expected_type or data == null) {
        if (data != null) _ = x11_c.XFree(@ptrCast(data));
        return null;
    }

    return .{
        .format = actual_format,
        .items = items,
        .data = data,
    };
}

/// Reads a single `XA_WINDOW` property value, used for `_NET_ACTIVE_WINDOW`.
fn readWindowAtom(display: *x11_c.Display, window: x11_c.Window, atom: x11_c.Atom) ?x11_c.Window {
    const property = getProperty(display, window, atom, x11_c.XA_WINDOW, 1) orelse return null;
    defer _ = x11_c.XFree(@ptrCast(property.data));

    if (property.format != 32 or property.items < 1) return null;

    const value_ptr: *const c_ulong = @ptrCast(@alignCast(property.data));
    return @intCast(value_ptr.*);
}

/// Reads a single `XA_CARDINAL` property value, used for `_NET_WM_PID`.
///
/// This is private X11 metadata only; PID is not part of the common app model.
fn readPid(display: *x11_c.Display, window: x11_c.Window, atom: x11_c.Atom) ?u32 {
    const property = getProperty(display, window, atom, x11_c.XA_CARDINAL, 1) orelse return null;
    defer _ = x11_c.XFree(@ptrCast(property.data));

    if (property.format != 32 or property.items < 1) return null;

    const value_ptr: *const c_ulong = @ptrCast(@alignCast(property.data));
    return @truncate(value_ptr.*);
}

/// Reads and splits the two NUL-terminated strings in the `WM_CLASS` property.
///
/// X11 stores `instance\0class\0`; the class is generally the more stable
/// application identifier.
fn readWmClass(display: *x11_c.Display, window: x11_c.Window, atom: x11_c.Atom) ?WmClass {
    const property = getProperty(display, window, atom, x11_c.XA_STRING, 64) orelse return null;
    defer _ = x11_c.XFree(@ptrCast(property.data));

    if (property.format != 8 or property.items < 1) return null;

    const bytes = property.data[0..@intCast(property.items)];
    const first_zero = std.mem.indexOfScalar(u8, bytes, 0) orelse return null;
    const instance = bytes[0..first_zero];

    const rest = bytes[first_zero + 1 ..];
    const class_len = std.mem.indexOfScalar(u8, rest, 0) orelse rest.len;
    const class = rest[0..class_len];

    var result = WmClass{ .instance = .{}, .class = .{} };
    result.instance.set(instance);
    result.class.set(class);
    return result;
}

/// Chooses the WM_CLASS class value, falling back to the instance value.
fn preferredAppId(wm: WmClass) Name {
    return if (wm.class.len > 0) wm.class else wm.instance;
}

/// Reports whether a window looks like an application window during tree walking.
///
/// `_NET_WM_PID` remains a private heuristic for windows that publish no
/// `WM_CLASS`.
fn hasAppProperties(self: *Backend, window: x11_c.Window) bool {
    // Keep this private X11 heuristic: some windows publish a PID but no
    // WM_CLASS, and should still be treated as application windows.
    if (readPid(self.control, window, self.atoms.net_wm_pid) != null) return true;

    if (readWmClass(self.control, window, self.atoms.wm_class)) |wm|
        return preferredAppId(wm).len > 0;

    return false;
}

/// Walks up the X11 window tree until a window with app-like properties is found.
///
/// Stops before WM frames and caps the walk at 64 parent links.
fn resolveAppWindow(self: *Backend, root: x11_c.Window, start: x11_c.Window) ?x11_c.Window {
    var window = start;
    var depth: usize = 0;

    while (depth < 64) : (depth += 1) {
        if (window == 0 or window == root) return null;

        // Stop as soon as a window looks like an application window. Walking
        // all the way to the top would often land on a WM frame instead.
        if (hasAppProperties(self, window)) return window;

        var root_return: x11_c.Window = 0;
        var parent_return: x11_c.Window = 0;
        var children_return: [*c]x11_c.Window = null;
        var children_count: c_uint = 0;

        const status = x11_c.XQueryTree(
            self.control,
            window,
            &root_return,
            &parent_return,
            &children_return,
            &children_count,
        );

        if (children_return != null) _ = x11_c.XFree(@ptrCast(children_return));
        if (status == 0) return null;

        if (parent_return == 0 or parent_return == root or parent_return == window)
            return window;

        window = parent_return;
    }

    return window;
}

/// Finds the app window under the pointer when X11 focus is `PointerRoot`.
fn windowUnderPointer(self: *Backend, root: x11_c.Window) ?x11_c.Window {
    var root_return: x11_c.Window = 0;
    var child_return: x11_c.Window = 0;
    var root_x: c_int = 0;
    var root_y: c_int = 0;
    var win_x: c_int = 0;
    var win_y: c_int = 0;
    var mask: c_uint = 0;

    if (x11_c.XQueryPointer(
        self.control,
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
    return resolveAppWindow(self, root, child_return) orelse child_return;
}

/// Determines the X11 window representing the active application.
///
/// Prefers the EWMH `_NET_ACTIVE_WINDOW` property, then falls back to core X11
/// keyboard focus and the `PointerRoot` case.
fn activeAppWindow(self: *Backend) ?x11_c.Window {
    const root = x11_c.XDefaultRootWindow(self.control);

    // EWMH window managers publish their active window here. This is already
    // the application window, not a WM frame.
    if (readWindowAtom(self.control, root, self.atoms.net_active_window)) |window| {
        if (window != 0 and window != root)
            return resolveAppWindow(self, root, window) orelse window;
    }

    // Core X11 fallback: keyboard focus.
    var focus: x11_c.Window = 0;
    var revert_to: c_int = 0;
    if (x11_c.XGetInputFocus(self.control, &focus, &revert_to) == 0) return null;

    if (focus == 0) return null;
    if (focus == pointer_root) return windowUnderPointer(self, root);
    if (focus == root) return null;

    return resolveAppWindow(self, root, focus) orelse focus;
}

/// Builds `AppInfo` from the X11 `WM_CLASS` property of `window`.
///
/// Both `name` and `id` use the preferred WM_CLASS value on X11; they may
/// diverge when other backends or richer name sources are added.
fn lookupAppInfo(self: *Backend, window: x11_c.Window) model.AppInfo {
    var info = model.AppInfo{};

    if (readWmClass(self.control, window, self.atoms.wm_class)) |wm| {
        const id = preferredAppId(wm);
        info.id = id;
        info.name = id;
    }

    return info;
}
