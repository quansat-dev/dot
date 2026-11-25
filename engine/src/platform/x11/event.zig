//! Translation from raw X11 events to the platform-neutral event model.

const x11_c = @import("x11_c");
const model = @import("model");
const constants = @import("constants.zig");

/// Converts a raw X11 event delivered by XRecord into a platform-neutral event.
///
/// Returns `null` for event types the engine does not report.
pub fn translate(raw: *const x11_c.xEvent) ?model.Event {
    return switch (raw.u.u.type) {
        constants.key_press, constants.key_release => model.Event{ .key = .{
            .action = if (raw.u.u.type == constants.key_press) .press else .release,
            .code = @intCast(raw.u.u.detail),
            .state = @intCast(raw.u.keyButtonPointer.state),
            .time = @truncate(raw.u.keyButtonPointer.time),
        } },
        constants.button_press, constants.button_release => model.Event{ .button = .{
            .action = if (raw.u.u.type == constants.button_press) .press else .release,
            .button = @intCast(raw.u.u.detail),
            .x = @intCast(raw.u.keyButtonPointer.rootX),
            .y = @intCast(raw.u.keyButtonPointer.rootY),
        } },
        constants.motion_notify => model.Event{ .motion = .{
            .x = @intCast(raw.u.keyButtonPointer.rootX),
            .y = @intCast(raw.u.keyButtonPointer.rootY),
        } },
        else => null,
    };
}
