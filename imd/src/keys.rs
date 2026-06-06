//! Key forwarding (addon → picker).
//!
//! While the picker is up it connects to the key socket; the C++ key watcher
//! then calls [`on_key`] for every key on the locked IC. We forward keys to the
//! connected picker over the socket and report them consumed, so the underlying
//! app never sees them. With no picker connected, keys pass straight through.

use std::ffi::CStr;
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixListener;
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender};

extern "C" {
    fn shim_set_key_handler(cb: extern "C" fn(u32, u32, *const c_char, bool) -> bool);
}

// Key-forwarding socket filename (under $XDG_RUNTIME_DIR), per variant so the
// test addon and production addon never share one.
#[cfg(not(feature = "test-variant"))]
const KEY_SOCKET_NAME: &str = "emojizasu-imd.sock";
#[cfg(feature = "test-variant")]
const KEY_SOCKET_NAME: &str = "emojizasu-imd-test.sock";

static KEY_TX: OnceLock<UnboundedSender<String>> = OnceLock::new();
static READER_CONNECTED: AtomicBool = AtomicBool::new(false);

extern "C" fn on_key(sym: u32, states: u32, text: *const c_char, is_release: bool) -> bool {
    let connected = READER_CONNECTED.load(Ordering::Acquire);
    eprintln!("emojizasu-imd: on_key sym={sym:x} release={is_release} reader_connected={connected}");
    // No picker listening — let the key reach the focused app untouched.
    if !connected {
        return false;
    }
    // Picker owns input: swallow releases (we only forward presses) but still
    // report them consumed so stray releases don't leak to the app.
    if is_release {
        return true;
    }
    let utf8 = if text.is_null() {
        ""
    } else {
        unsafe { CStr::from_ptr(text) }.to_str().unwrap_or("")
    };
    // Strip control chars so nothing can break the newline-framed wire format.
    let safe: String = utf8.chars().filter(|c| !c.is_control()).collect();
    if let Some(tx) = KEY_TX.get() {
        let _ = tx.send(format!("{sym} {states} {safe}"));
    }
    true
}

pub fn socket_path() -> PathBuf {
    if let Ok(p) = std::env::var("EMOJIZASU_KEY_SOCKET") {
        return PathBuf::from(p);
    }
    let base = std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    base.join(KEY_SOCKET_NAME)
}

/// Create the key-forwarding channel and install the C++ key handler. Returns
/// the receiver to be drained by [`run_socket`].
pub fn install_handler() -> UnboundedReceiver<String> {
    let (tx, rx) = unbounded_channel::<String>();
    let _ = KEY_TX.set(tx);
    unsafe { shim_set_key_handler(on_key) };
    rx
}

/// Serve the key socket: bind (retrying on failure with capped backoff), then
/// accept pickers forever. Runs until the task is cancelled at shutdown.
pub async fn run_socket(path: PathBuf, mut rx: UnboundedReceiver<String>) -> ! {
    let mut backoff = crate::RETRY_INIT;
    loop {
        let _ = std::fs::remove_file(&path);
        match UnixListener::bind(&path) {
            Ok(listener) => {
                eprintln!("emojizasu-imd: key socket listening at {}", path.display());
                accept_loop(&listener, &mut rx).await;
            }
            Err(e) => {
                eprintln!("emojizasu-imd: key socket bind failed: {e}; retrying in {backoff:?}");
                tokio::time::sleep(backoff).await;
                backoff = crate::next_backoff(backoff);
            }
        }
    }
}

async fn accept_loop(listener: &UnixListener, rx: &mut UnboundedReceiver<String>) -> ! {
    loop {
        let stream = match listener.accept().await {
            Ok((s, _)) => s,
            Err(_) => continue,
        };
        eprintln!("emojizasu-imd: picker connected to key socket");
        while rx.try_recv().is_ok() {}
        READER_CONNECTED.store(true, Ordering::Release);
        serve_client(stream, rx).await;
        READER_CONNECTED.store(false, Ordering::Release);
    }
}

async fn serve_client(stream: tokio::net::UnixStream, rx: &mut UnboundedReceiver<String>) {
    let (mut rd, mut wr) = stream.into_split();
    loop {
        tokio::select! {
            line = rx.recv() => {
                let Some(line) = line else { return; };
                let mut buf = line.into_bytes();
                buf.push(b'\n');
                if wr.write_all(&buf).await.is_err() { return; }
            }
            r = rd.read_u8() => {
                if r.is_err() { return; }
            }
        }
    }
}
