//! Active application resolution and caching for X11.

const std = @import("std");
const x11_c = @import("x11_c");
const model = @import("model");
const atoms_mod = @import("atoms.zig");
const constants = @import("constants.zig");
const property = @import("property.zig");

pub const Tracker = struct {
    cache: std.AutoHashMap(u64, ?model.AppInfo),

    /// Creates an empty app-info cache.
    pub fn init(allocator: std.mem.Allocator) Tracker {
        return .{ .cache = std.AutoHashMap(u64, ?model.AppInfo).init(allocator) };
    }

    /// Releases the app-info cache.
    pub fn deinit(self: *Tracker) void {
        self.cache.deinit();
    }

    /// Returns the active application for the current X11 focus/active-window state.
    ///
    /// Results are cached by X11 window id, including negative lookups.
    pub fn active(
        self: *Tracker,
        display: *x11_c.Display,
        atoms: atoms_mod.Atoms,
    ) ?model.AppInfo {
        const window = activeAppWindow(display, atoms) orelse return null;
        const id = windowId(window);

        if (self.cache.get(id)) |cached| return cached;

        const info = lookupAppInfo(display, atoms, window);
        self.cache.put(id, info) catch {};
        return info;
    }
};

/// Converts an X11 window id to the opaque cache key used by the backend.
fn windowId(window: x11_c.Window) u64 {
    return @intCast(window);
}

/// Reports whether a window looks like an application window during tree walking.
///
/// `_NET_WM_PID` remains a private heuristic for windows that publish no
/// `WM_CLASS`.
fn hasAppProperties(
    display: *x11_c.Display,
    atoms: atoms_mod.Atoms,
    window: x11_c.Window,
) bool {
    // Keep this private X11 heuristic: some windows publish a PID but no
    // WM_CLASS, and should still be treated as application windows.
    if (property.readPid(display, window, atoms.net_wm_pid) != null) return true;

    if (property.readWmClass(display, window, atoms.wm_class)) |wm|
        return property.preferredAppId(wm).len > 0;

    return false;
}

/// Walks up the X11 window tree until a window with app-like properties is found.
///
/// Stops before WM frames and caps the walk at 64 parent links.
fn resolveAppWindow(
    display: *x11_c.Display,
    atoms: atoms_mod.Atoms,
    root: x11_c.Window,
    start: x11_c.Window,
) ?x11_c.Window {
    var window = start;
    var depth: usize = 0;

    while (depth < 64) : (depth += 1) {
        if (window == 0 or window == root) return null;

        // Stop as soon as a window looks like an application window. Walking
        // all the way to the top would often land on a WM frame instead.
        if (hasAppProperties(display, atoms, window)) return window;

        var root_return: x11_c.Window = 0;
        var parent_return: x11_c.Window = 0;
        var children_return: [*c]x11_c.Window = null;
        var children_count: c_uint = 0;

        const status = x11_c.XQueryTree(
            display,
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
fn windowUnderPointer(
    display: *x11_c.Display,
    atoms: atoms_mod.Atoms,
    root: x11_c.Window,
) ?x11_c.Window {
    var root_return: x11_c.Window = 0;
    var child_return: x11_c.Window = 0;
    var root_x: c_int = 0;
    var root_y: c_int = 0;
    var win_x: c_int = 0;
    var win_y: c_int = 0;
    var mask: c_uint = 0;

    if (x11_c.XQueryPointer(
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
    return resolveAppWindow(display, atoms, root, child_return) orelse child_return;
}

/// Determines the X11 window representing the active application.
///
/// Prefers the EWMH `_NET_ACTIVE_WINDOW` property, then falls back to core X11
/// keyboard focus and the `PointerRoot` case.
fn activeAppWindow(display: *x11_c.Display, atoms: atoms_mod.Atoms) ?x11_c.Window {
    const root = x11_c.XDefaultRootWindow(display);

    // EWMH window managers publish their active window here. This is already
    // the application window, not a WM frame.
    if (property.readWindowAtom(display, root, atoms.net_active_window)) |window| {
        if (window != 0 and window != root)
            return resolveAppWindow(display, atoms, root, window) orelse window;
    }

    // Core X11 fallback: keyboard focus.
    var focus: x11_c.Window = 0;
    var revert_to: c_int = 0;
    if (x11_c.XGetInputFocus(display, &focus, &revert_to) == 0) return null;

    if (focus == 0) return null;
    if (focus == constants.pointer_root) return windowUnderPointer(display, atoms, root);
    if (focus == root) return null;

    return resolveAppWindow(display, atoms, root, focus) orelse focus;
}

/// Builds `AppInfo` from the X11 `WM_CLASS` property of `window`.
///
/// Both `name` and `id` use the preferred WM_CLASS value on X11; they may
/// diverge when other backends or richer name sources are added.
fn lookupAppInfo(
    display: *x11_c.Display,
    atoms: atoms_mod.Atoms,
    window: x11_c.Window,
) model.AppInfo {
    var info = model.AppInfo{};

    if (property.readWmClass(display, window, atoms.wm_class)) |wm| {
        const id = property.preferredAppId(wm);
        info.id = id;
        info.name = id;
    }

    return info;
}
