const std = @import("std");
const model = @import("model");
const api = @import("platform_api");
const backend = @import("backend");

const Printer = struct {
    pub fn onEvent(
        _: ?*anyopaque,
        event: model.Event,
        app: ?*const model.AppInfo,
    ) void {
        const app_name = model.displayName(app);
        const app_id = model.displayId(app);

        switch (event) {
            .key => |e| std.debug.print(
                "key {s} code={d} state={d} time={d} app={s} id={s}\n",
                .{
                    if (e.action == .press) "press" else "release",
                    e.code,
                    e.state,
                    e.time,
                    app_name,
                    app_id,
                },
            ),
            .button => |e| std.debug.print(
                "mouse {s} button={d} x={d} y={d} app={s} id={s}\n",
                .{
                    if (e.action == .press) "press" else "release",
                    e.button,
                    e.x,
                    e.y,
                    app_name,
                    app_id,
                },
            ),
            .motion => |e| std.debug.print(
                "mouse move x={d} y={d} app={s} id={s}\n",
                .{ e.x, e.y, app_name, app_id },
            ),
        }
    }
};

fn fatal(err: anyerror) noreturn {
    std.debug.print("dot engine: {s}\n", .{@errorName(err)});
    std.process.exit(1);
}

pub fn main() void {
    var b = backend.init(std.heap.page_allocator) catch |err| fatal(err);
    defer b.deinit();

    const sink: api.Sink = .{ .on_event = Printer.onEvent };
    b.listen(sink) catch |err| fatal(err);
}
