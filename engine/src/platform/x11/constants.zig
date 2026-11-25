//! X11 protocol constants used by the X11 backend.

const x11_c = @import("x11_c");

pub const key_press: u8 = @intCast(x11_c.KeyPress);
pub const key_release: u8 = @intCast(x11_c.KeyRelease);
pub const button_press: u8 = @intCast(x11_c.ButtonPress);
pub const button_release: u8 = @intCast(x11_c.ButtonRelease);
pub const motion_notify: u8 = @intCast(x11_c.MotionNotify);
pub const pointer_root: x11_c.Window = @intCast(x11_c.PointerRoot);
pub const record_from_server: c_int = x11_c.XRecordFromServer;
