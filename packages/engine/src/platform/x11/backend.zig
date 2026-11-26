//! Public X11 backend facade.
//!
//! This is the only file in the X11 backend module exposed to `main.zig`. All
//! Xlib interaction lives in the sibling modules.

const std = @import("std");
const model = @import("model");
const api = @import("platform_api");
const connection_mod = @import("connection.zig");
const atoms_mod = @import("atoms.zig");
const active_app = @import("active_app.zig");
const record = @import("record.zig");

pub const Backend = struct {
    connection: connection_mod.Connection,
    atoms: atoms_mod.Atoms,
    apps: active_app.Tracker,

    /// Closes both X11 connections and releases the app-info cache.
    pub fn deinit(self: *Backend) void {
        self.apps.deinit();
        self.connection.deinit();
    }

    /// Configures the XRecord context and blocks while delivering decoded events
    /// to `sink`.
    ///
    /// Configuration uses the control connection; the event stream uses the data
    /// connection. The context is created before it is enabled on `data`.
    pub fn listen(self: *Backend, sink: api.Sink) !void {
        try record.listen(
            self.connection.control,
            self.connection.data,
            self.atoms,
            &self.apps,
            sink,
        );
    }

    /// Returns the active application for the current X11 focus/active-window state.
    ///
    /// Results are cached by X11 window id, including negative lookups.
    pub fn activeApp(self: *Backend) ?model.AppInfo {
        return self.apps.active(self.connection.control, self.atoms);
    }
};

/// Opens the control and data X11 displays and interns the atoms used by the
/// backend.
pub fn init(allocator: std.mem.Allocator) !Backend {
    var connection = try connection_mod.open();
    errdefer connection.deinit();

    const atoms = try atoms_mod.intern(connection.control);

    return .{
        .connection = connection,
        .atoms = atoms,
        .apps = active_app.Tracker.init(allocator),
    };
}
