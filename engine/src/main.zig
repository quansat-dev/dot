const std = @import("std");
const c = @import("c");

const key_press: u8 = @intCast(c.KeyPress);
const key_release: u8 = @intCast(c.KeyRelease);
const button_press: u8 = @intCast(c.ButtonPress);
const button_release: u8 = @intCast(c.ButtonRelease);
const motion_notify: u8 = @intCast(c.MotionNotify);
const record_from_server: c_int = c.XRecordFromServer;

fn onRecord(_: c.XPointer, raw: [*c]c.XRecordInterceptData) callconv(.c) void {
    if (raw == null) return;
    const data: *c.XRecordInterceptData = @ptrCast(&raw[0]);
    defer c.XRecordFreeData(raw);

    if (data.category != record_from_server) return;

	// XRecord reports data_len in units of 4 bytes,
	// core X11 event is 32 bytes
	// => expect 8 units
    const byte_len: usize = @intCast(data.data_len * 4);
    if (byte_len != @sizeOf(c.xEvent)) return;

    const bytes = data.data[0..byte_len];
    const event: *const c.xEvent = @ptrCast(@alignCast(bytes.ptr));

    switch (event.u.u.type) {
        key_press, key_release => std.debug.print(
            "key {s} code={d} state={d} time={d}\n",
            .{
                if (event.u.u.type == key_press) "press" else "release",
                event.u.u.detail,
                event.u.keyButtonPointer.state,
                event.u.keyButtonPointer.time,
            },
        ),
        button_press, button_release => std.debug.print(
            "mouse {s} button={d} x={d} y={d}\n",
            .{
                if (event.u.u.type == button_press) "press" else "release",
                event.u.u.detail,
                event.u.keyButtonPointer.rootX,
                event.u.keyButtonPointer.rootY,
            },
        ),
        motion_notify => std.debug.print(
            "mouse move x={d} y={d}\n",
            .{ event.u.keyButtonPointer.rootX, event.u.keyButtonPointer.rootY },
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

	// ask X server if RECORD extension exists
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

    if (c.XRecordEnableContext(data, ctx, onRecord, null) == 0)
        return error.ContextEnableFailed;
}

pub fn main() void {
    run() catch |err| {
        std.debug.print("dot engine: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
