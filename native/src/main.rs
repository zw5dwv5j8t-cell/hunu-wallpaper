//! Native settings gate and short-lived stdio transport for the QML picker.
use serde_json::Value;
use std::{env, fs, io::{self, Read, Write}, net::Shutdown, os::unix::net::UnixStream,
          path::Path, process, thread, time::{Duration, Instant}};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

fn enabled(app: &Path) -> Result<bool> {
    let folder = if app.file_name().is_some_and(|name| name == "src")
        && app.parent().is_some_and(|parent| parent.join("config").is_dir()) {
        app.parent().unwrap().join("config")
    } else { app.to_path_buf() };
    let content = match fs::read_to_string(folder.join("switcher-settings.json")) {
        Ok(content) => content,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(true),
        Err(error) => return Err(error.into()),
    };
    let value: Value = serde_json::from_str(&content)?;
    let object = value.as_object().ok_or("Switcher settings must be an object.")?;
    for name in ["enabled", "livePreview", "showActionButtons"] {
        if object.get(name).is_some_and(|value| !value.is_boolean()) {
            return Err("Enable, live preview, and show buttons must be true or false.".into());
        }
    }
    if object.get("position").is_some_and(|value| !matches!(value.as_str(), Some("top" | "center" | "bottom"))) {
        return Err("Position must be top, center, or bottom.".into());
    }
    if object.get("delayMs").is_some_and(|value| !value.as_u64().is_some_and(|delay| (100..=1500).contains(&delay))) {
        return Err("Preview delay must be between 100 and 1500 milliseconds.".into());
    }
    Ok(object.get("enabled").and_then(Value::as_bool).unwrap_or(true))
}

fn connect(path: &Path) -> Result<()> {
    let deadline = Instant::now() + Duration::from_secs(2);
    let stream = loop {
        match UnixStream::connect(path) {
            Ok(stream) => break stream,
            Err(error) if matches!(error.kind(), io::ErrorKind::NotFound | io::ErrorKind::ConnectionRefused)
                && Instant::now() < deadline => thread::sleep(Duration::from_millis(10)),
            Err(error) => return Err(error.into()),
        }
    };
    let mut outgoing = stream.try_clone()?;
    // The main thread returns when the controller disconnects. A blocked stdin
    // reader then ends with the process; no detached helper remains resident.
    thread::spawn(move || {
        let mut stdin = io::stdin().lock();
        let mut buffer = [0; 65536];
        while let Ok(count) = stdin.read(&mut buffer) {
            if count == 0 || outgoing.write_all(&buffer[..count]).is_err() { break; }
        }
        let _ = outgoing.shutdown(Shutdown::Write);
    });
    let mut incoming = stream;
    let mut stdout = io::stdout().lock();
    let mut buffer = [0; 65536];
    loop {
        let count = incoming.read(&mut buffer)?;
        if count == 0 { break; }
        stdout.write_all(&buffer[..count])?;
        stdout.flush()?;
    }
    Ok(())
}

fn run() -> Result<()> {
    let arguments: Vec<_> = env::args_os().collect();
    if arguments.len() != 3 {
        return Err("Usage: hunu-switcher-native enabled APP_DIR | connect SOCKET".into());
    }
    match arguments[1].to_str() {
        Some("enabled") => println!("{}", enabled(Path::new(&arguments[2]))?),
        Some("connect") => connect(Path::new(&arguments[2]))?,
        _ => return Err("Unknown native switcher command.".into()),
    }
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("ERROR: {error}");
        process::exit(1);
    }
}
