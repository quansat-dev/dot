pub mod event;
pub mod platform;

use log::info;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    let callback: Box<dyn Fn(&event::Event) + Send + Sync> = Box::new(|event: &event::Event| {
        info!(
            "[{}] App: {}, Event: {:?}",
            event.timestamp.to_rfc3339(),
            event.app,
            event.data
        );
    });

    // Start the recording in a separate thread/connection
    // The "data" connection will block while receiving recorded data
    std::thread::spawn(move || platform::linux::x11::record(callback));

    // Keep the main thread alive
    info!("Listening for global events... (Ctrl+C to stop)");
    loop {
        std::thread::park();
    }
}
