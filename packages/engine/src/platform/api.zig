const model = @import("model");

/// How a backend reports input events back to the platform-agnostic caller.
///
/// The `app` pointer is only valid for the duration of `on_event`. Sinks must
/// copy any slices they want to retain.
pub const Sink = struct {
    context: ?*anyopaque = null,
    on_event: *const fn (
        context: ?*anyopaque,
        event: model.Event,
        app: ?*const model.AppInfo,
    ) void,
};

// Backend contract, satisfied by platform/x11.zig and future backends:
//
//   pub const Backend = struct { ... };
//   pub fn init(allocator: std.mem.Allocator) !Backend;
//   pub fn deinit(self: *Backend) void;
//   pub fn listen(self: *Backend, sink: Sink) !void;
//   pub fn activeApp(self: *Backend) ?model.AppInfo;
//
// `build.zig` selects exactly one backend module at compile time and exposes it
// to main.zig as `backend`. There is no runtime vtable and no type erasure at
// this boundary.
