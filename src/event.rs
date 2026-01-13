use chrono::{DateTime, Utc};

#[derive(Debug, Copy, Clone, PartialEq)]
pub enum EventData {
    KeyPress(u32),
    PointerPress(u8),
    PointerMove { x: f64, y: f64 },
    FocusIn,
    FocusOut,
}

pub struct Event {
    /// when the event occurred
    pub timestamp: DateTime<Utc>,
    /// the application generated the event (if known).
    /// This depends on platform capabilities, for example,
    /// in Linux X11 this is the `WM_CLASS` property of the window,
    /// in MacOS this is the bundle identifier, and
    /// in Windows this is the executable name.
    pub app: String,
    /// event-specific data
    pub data: EventData,
}
