use log::{error, info, warn};

use x11rb::connection::Connection;
use x11rb::connection::RequestConnection;
use x11rb::errors::ConnectionError;
use x11rb::properties::WmClass;
use x11rb::protocol::record::{self, ConnectionExt as _};
use x11rb::protocol::xproto::{self, AtomEnum, ConnectionExt as _};
use x11rb::x11_utils::TryParse;

use crate::event;

x11rb::atom_manager! {
    Atoms:
    AtomsCookie {
        _NET_ACTIVE_WINDOW,
        _NET_WM_NAME,
        UTF8_STRING,
    }
}

pub fn record<C>(callback: C)
where
    C: Fn(&event::Event) + Send + Sync + 'static,
{
    // From https://www.x.org/releases/X11R7.6/doc/recordproto/record.html
    // "The typical communication model for a recording client is to open two
    // connections to the server and use one for RC control and the other for
    // reading protocol data."
    let (data_conn, _) = x11rb::connect(None).unwrap();
    let (ctrl_conn, _) = x11rb::connect(None).unwrap();

    // Check if the record extension is supported.
    if ctrl_conn
        .extension_information(record::X11_EXTENSION_NAME)
        .unwrap()
        .is_none()
    {
        error!("The X11 server does not support the RECORD extension");
        // exit early
        return;
    }

    // Set up a recording range for events of interest
    let mut range = record::Range::default();
    range.delivered_events.first = record::ElementHeader::from(xproto::KEY_PRESS_EVENT);
    range.delivered_events.last = record::ElementHeader::from(xproto::FOCUS_OUT_EVENT);

    // Set up a recording context
    let rc = ctrl_conn.generate_id().unwrap();
    ctrl_conn
        .record_create_context(rc, 0, &[record::CS::ALL_CLIENTS.into()], &[range])
        .unwrap()
        .check()
        .unwrap();

    // Apply a timeout if we are requested to do so.
    // match std::env::var("X11RB_TIMEOUT")
    //     .ok()
    //     .and_then(|str| str.parse().ok())
    // {
    //     None => {}
    //     Some(timeout) => {
    //         std::thread::spawn(move || {
    //             std::thread::sleep(std::time::Duration::from_secs(timeout));
    //             ctrl_conn.record_disable_context(rc).unwrap();
    //             ctrl_conn.sync().unwrap();
    //         });
    //     }
    // }

    // We now switch to using "the other" connection.
    const START_OF_DATA: u8 = 4;
    const RECORD_FROM_SERVER: u8 = 0;
    for reply in data_conn.record_enable_context(rc).unwrap() {
        let reply = reply.unwrap();
        if reply.client_swapped {
            error!("Byte swapped clients are unsupported");
        } else if reply.category == RECORD_FROM_SERVER {
            let mut stream = &reply.data[..];
            while !stream.is_empty() {
                let data = &reply.data;
                match data[0] {
                    0 => {
                        // This is a reply, we compute its length as follows
                        let (length, _) = u32::try_parse(&data[4..]).unwrap();
                        let length = usize::try_from(length).unwrap() * 4 + 32;
                        warn!("unparsed reply: {:?}", &data[..length]);
                        stream = &data[length..];
                    }
                    xproto::KEY_PRESS_EVENT => {
                        // parse the event
                        let (event, remaining) = xproto::KeyPressEvent::try_parse(data).unwrap();

                        // if the window reports with WM_CLASS, report the event
                        if let Some(class) = get_window_class(&ctrl_conn, event.event).unwrap() {
                            let event = event::Event {
                                timestamp: chrono::Utc::now(),
                                app: class,
                                data: event::EventData::KeyPress(event.detail.into()),
                            };
                            callback(&event);
                        }

                        // continue the stream
                        stream = remaining;
                    }
                    xproto::BUTTON_PRESS_EVENT => {
                        // parse the event
                        let (event, remaining) = xproto::ButtonPressEvent::try_parse(data).unwrap();

                        // if the window reports with WM_CLASS, report the event
                        if let Some(class) = get_window_class(&ctrl_conn, event.event).unwrap() {
                            let event = event::Event {
                                timestamp: chrono::Utc::now(),
                                app: class,
                                data: event::EventData::PointerPress(event.detail.into()),
                            };
                            callback(&event);
                        }

                        // continue the stream
                        stream = remaining;
                    }
                    xproto::MOTION_NOTIFY_EVENT => {
                        // parse the event
                        let (event, remaining) =
                            xproto::MotionNotifyEvent::try_parse(data).unwrap();

                        // get the __active__ window, because this event will be reported to root,
                        // not any specific window
                        let active_win = get_active_window(&ctrl_conn, event.root).unwrap();

                        // if the window reports with WM_CLASS, report the event
                        if let Some(class) = get_window_class(&ctrl_conn, active_win).unwrap() {
                            let event = event::Event {
                                timestamp: chrono::Utc::now(),
                                app: class,
                                data: event::EventData::PointerMove {
                                    x: event.root_x as f64,
                                    y: event.root_y as f64,
                                },
                            };
                            callback(&event);
                        }

                        stream = remaining;
                    }
                    xproto::FOCUS_IN_EVENT => {
                        // parse the event
                        let (event, remaining) = xproto::FocusInEvent::try_parse(data).unwrap();

                        // if the window reports with WM_CLASS, report the event
                        if let Some(class) = get_window_class(&ctrl_conn, event.event).unwrap() {
                            let event = event::Event {
                                timestamp: chrono::Utc::now(),
                                app: class,
                                data: event::EventData::FocusIn,
                            };
                            callback(&event);
                        }

                        stream = remaining;
                    }
                    xproto::FOCUS_OUT_EVENT => {
                        // parse the event
                        let (event, remaining) = xproto::FocusOutEvent::try_parse(data).unwrap();

                        // if the window reports with WM_CLASS, report the event
                        if let Some(class) = get_window_class(&ctrl_conn, event.event).unwrap() {
                            let event = event::Event {
                                timestamp: chrono::Utc::now(),
                                app: class,
                                data: event::EventData::FocusOut,
                            };
                            callback(&event);
                        }

                        stream = remaining;
                    }
                    _ => {
                        // Error or event, they always have length 32
                        stream = &data[32..];
                    }
                }
            }
        } else if reply.category == START_OF_DATA {
            info!("Start of data stream...")
        } else {
            warn!("Got a reply with an unsupported category: {reply:?}");
        }
    }
}

fn get_window_class(
    conn: &impl Connection,
    window: xproto::Window,
) -> Result<Option<String>, ConnectionError> {
    let wm_class = match WmClass::get(conn, window)?.reply_unchecked()? {
        Some(wm_class) => wm_class,
        None => return Ok(None),
    };
    // Note that the WM_CLASS property is not actually encoded in utf8.
    // ASCII values are most common and for these from_utf8() should be fine.
    let class = std::str::from_utf8(wm_class.class());
    match class {
        Ok(class) => Ok(Some(class.to_string())),
        Err(_) => Ok(None),
    }
}

// fn get_window_name(
//     conn: &impl Connection,
//     window: xproto::Window,
// ) -> Result<Option<String>, ConnectionError> {
//     let atoms = Atoms::new(conn).unwrap().reply().unwrap();
//     let name_prop = conn
//         .get_property(
//             false,
//             window,
//             atoms._NET_WM_NAME,
//             atoms.UTF8_STRING,
//             0,
//             0x1000,
//         )
//         .unwrap()
//         .reply()
//         .unwrap();
//
//     if name_prop.value_len == 0 {
//         return Ok(None);
//     }
//
//     let name = String::from_utf8(name_prop.value).ok();
//     Ok(name)
// }

fn get_active_window(
    conn: &impl Connection,
    root: xproto::Window,
) -> Result<xproto::Window, ConnectionError> {
    let atoms = Atoms::new(conn).unwrap().reply().unwrap();
    let cookie = conn
        .get_property(
            false,
            root,
            atoms._NET_ACTIVE_WINDOW,
            AtomEnum::WINDOW,
            0,
            1,
        )
        .unwrap();
    let reply = cookie.reply().unwrap();
    let win = reply
        .value32()
        .ok_or("_NET_ACTIVE_WINDOW has incorrect format")
        .unwrap()
        .next()
        .ok_or("_NET_ACTIVE_WINDOW is empty")
        .unwrap();
    Ok(win)
}
