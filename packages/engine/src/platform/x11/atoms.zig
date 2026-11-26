//! Interning of the X11 atoms used for active-app lookup.

const x11_c = @import("x11_c");

pub const Atoms = struct {
    net_active_window: x11_c.Atom,
    net_wm_pid: x11_c.Atom,
    wm_class: x11_c.Atom,
};

/// Interns the EWMH and X11 property atoms used for active-app lookup.
///
/// Returns `error.AtomInternFailed` if any atom id is zero.
pub fn intern(display: *x11_c.Display) !Atoms {
    const net_active_window = x11_c.XInternAtom(display, "_NET_ACTIVE_WINDOW", 0);
    const net_wm_pid = x11_c.XInternAtom(display, "_NET_WM_PID", 0);
    const wm_class = x11_c.XInternAtom(display, "WM_CLASS", 0);

    if (net_active_window == 0 or net_wm_pid == 0 or wm_class == 0)
        return error.AtomInternFailed;

    return .{
        .net_active_window = net_active_window,
        .net_wm_pid = net_wm_pid,
        .wm_class = wm_class,
    };
}
