//! Low-level X11 window-property reads.

const std = @import("std");
const x11_c = @import("x11_c");
const model = @import("model");

pub const Property = struct {
    format: c_int,
    items: c_ulong,
    data: [*c]u8,
};

pub const WmClass = struct {
    instance: model.Name,
    class: model.Name,
};

/// Reads an X11 window property with `XGetWindowProperty`.
///
/// The caller owns `Property.data` and must release it with `XFree`.
pub fn getProperty(
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
pub fn readWindowAtom(
    display: *x11_c.Display,
    window: x11_c.Window,
    atom: x11_c.Atom,
) ?x11_c.Window {
    const property = getProperty(display, window, atom, x11_c.XA_WINDOW, 1) orelse return null;
    defer _ = x11_c.XFree(@ptrCast(property.data));

    if (property.format != 32 or property.items < 1) return null;

    const value_ptr: *const c_ulong = @ptrCast(@alignCast(property.data));
    return @intCast(value_ptr.*);
}

/// Reads a single `XA_CARDINAL` property value, used for `_NET_WM_PID`.
///
/// This is private X11 metadata only; PID is not part of the common app model.
pub fn readPid(display: *x11_c.Display, window: x11_c.Window, atom: x11_c.Atom) ?u32 {
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
pub fn readWmClass(display: *x11_c.Display, window: x11_c.Window, atom: x11_c.Atom) ?WmClass {
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
pub fn preferredAppId(wm: WmClass) model.Name {
    return if (wm.class.len > 0) wm.class else wm.instance;
}
