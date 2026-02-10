pub mod event;
pub mod platform;
use std::sync::Mutex;
use std::thread;

use log::info;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    let counter = Mutex::new(0);

    // Keep the main thread alive
    info!("Listening for global events... (Ctrl+C to stop)");

    // Start the recording in a separate thread/connection
    // The "data" connection will block while receiving recorded data
    thread::scope(|s| {
        s.spawn(|| {
            platform::linux::x11::record(|event: &event::Event| {
                let ignored_apps = ["i3", "sway"];
                for app in ignored_apps.iter() {
                    if event.app.to_lowercase().contains(app) {
                        return;
                    }
                }

                let mut num = counter.lock().unwrap();
                *num += 1;

                // info!(
                //     "[{}] App: {}, Event: {:?}",
                //     event.timestamp.to_rfc3339(),
                //     event.app,
                //     event.data
                // );
                info!("Event #{}", *num);
            });
        });
    });

    info!("Counted {} events", *counter.lock().unwrap());
    info!("Exiting...");

    Ok(())
}
