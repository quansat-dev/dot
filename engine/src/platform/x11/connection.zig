//! X11 display connections owned by the backend.

const x11_c = @import("x11_c");

pub const Connection = struct {
    /// Connection used for configuration and active-app queries.
    control: *x11_c.Display,

    /// Connection used exclusively for the XRecord event stream.
    data: *x11_c.Display,

    /// Closes both X11 connections.
    pub fn deinit(self: *Connection) void {
        _ = x11_c.XCloseDisplay(self.data);
        _ = x11_c.XCloseDisplay(self.control);
    }
};

/// Opens the control and data X11 displays.
pub fn open() !Connection {
    const control = x11_c.XOpenDisplay(null) orelse return error.ControlDisplayOpenFailed;
    errdefer _ = x11_c.XCloseDisplay(control);

    const data = x11_c.XOpenDisplay(null) orelse return error.DataDisplayOpenFailed;
    errdefer _ = x11_c.XCloseDisplay(data);

    return .{ .control = control, .data = data };
}
