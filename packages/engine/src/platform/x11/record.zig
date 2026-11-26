//! XRecord setup and C callback adapter.

const std = @import("std");
const x11_c = @import("x11_c");
const api = @import("platform_api");
const atoms_mod = @import("atoms.zig");
const active_app = @import("active_app.zig");
const constants = @import("constants.zig");
const event = @import("event.zig");

const Closure = struct {
    /// Control connection, used for app queries while `data` is blocked.
    control: *x11_c.Display,
    atoms: atoms_mod.Atoms,
    apps: *active_app.Tracker,
    sink: api.Sink,
};

/// Configures the XRecord context and blocks while delivering decoded events
/// to `sink`.
///
/// Configuration uses the control connection; the event stream uses the data
/// connection. The context is created before it is enabled on `data`.
pub fn listen(
    control: *x11_c.Display,
    data: *x11_c.Display,
    atoms: atoms_mod.Atoms,
    apps: *active_app.Tracker,
    sink: api.Sink,
) !void {
    var major: c_int = 0;
    var minor: c_int = 0;
    if (x11_c.XRecordQueryVersion(control, &major, &minor) == 0)
        return error.RecordExtensionUnavailable;

    const range_ptr = x11_c.XRecordAllocRange();
    if (range_ptr == null) return error.OutOfMemory;
    defer x11_c.free(@ptrCast(range_ptr));

    const range: *x11_c.XRecordRange = @ptrCast(&range_ptr[0]);
    range.* = std.mem.zeroes(x11_c.XRecordRange);
    range.device_events.first = constants.key_press;
    range.device_events.last = constants.motion_notify;
    var ranges = [_][*c]x11_c.XRecordRange{range_ptr};

    var clients = [_]x11_c.XRecordClientSpec{@intCast(x11_c.XRecordAllClients)};

    const ctx = x11_c.XRecordCreateContext(control, 0, &clients, 1, &ranges, 1);
    if (ctx == 0) return error.ContextCreationFailed;
    defer _ = x11_c.XRecordFreeContext(control, ctx);

    // The context is created on the control connection but enabled on the data
    // connection. Flush first so the server knows the context before the data
    // connection references it.
    _ = x11_c.XSync(control, 0);

    std.debug.print("dot engine: listening on X11 RECORD (keyboard + mouse)\n", .{});

    var closure = Closure{
        .control = control,
        .atoms = atoms,
        .apps = apps,
        .sink = sink,
    };
    if (x11_c.XRecordEnableContext(data, ctx, onRecord, @ptrCast(&closure)) == 0)
        return error.ContextEnableFailed;
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

    if (data.category != constants.record_from_server) return;

    const byte_len: usize = @intCast(data.data_len * 4);
    if (byte_len != @sizeOf(x11_c.xEvent)) return;

    const bytes = data.data[0..byte_len];
    const raw_event: *const x11_c.xEvent = @ptrCast(@alignCast(bytes.ptr));

    const translated = event.translate(raw_event) orelse return;

    const ctx: *Closure = @ptrCast(@alignCast(closure));
    var app = ctx.apps.active(ctx.control, ctx.atoms);

    ctx.sink.on_event(
        ctx.sink.context,
        translated,
        if (app) |*a| a else null,
    );
}
