//! Key forwarding (addon → picker).
//!
//! While the picker is up it connects to the key socket; the C++ key watcher
//! then calls [`rust_key_handler`] for every key. We forward keys to the
//! connected picker over the socket and report them consumed, so the underlying
//! app never sees them. With no picker connected, keys pass straight through.

use std::future::Future;
use std::os::raw::c_char;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixListener;
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender};

extern "C" {
    fn shim_install_key_watcher(inst: *mut std::os::raw::c_void);
}

#[cfg(not(feature = "test-variant"))]
const KEY_SOCKET_NAME: &str = "emojizasu-imd.sock";
#[cfg(feature = "test-variant")]
const KEY_SOCKET_NAME: &str = "emojizasu-imd-test.sock";

static KEY_TX: OnceLock<UnboundedSender<String>> = OnceLock::new();
static READER_CONNECTED: AtomicBool = AtomicBool::new(false);

/// (dev, ino) of the socket this process currently has bound, so teardown can
/// tell our own socket file apart from one a successor bound at the same path.
static BOUND_SOCKET_ID: Mutex<Option<(u64, u64)>> = Mutex::new(None);

fn socket_id(path: &Path) -> Option<(u64, u64)> {
    std::fs::metadata(path).ok().map(|m| (m.dev(), m.ino()))
}

/// Unlink the socket file only if it is still the one we bound. `fcitx5 -r`
/// starts the replacement instance before the outgoing one tears its addons
/// down; without this check the dying instance deletes the successor's freshly
/// bound socket, leaving a listener no picker can ever reach.
fn unlink_own_socket(path: &Path) {
    let mut bound = match BOUND_SOCKET_ID.lock() {
        Ok(g) => g,
        Err(e) => e.into_inner(),
    };
    if bound.is_some() && *bound == socket_id(path) {
        let _ = std::fs::remove_file(path);
    }
    *bound = None;
}

/// Owns the key-forwarding socket path and the channel receiver used to
/// shuttle keys from the C++ watcher to the connected picker.
pub(crate) struct KeysChannel {
    socket_path: PathBuf,
    rx: Option<UnboundedReceiver<String>>,
}

impl Drop for KeysChannel {
    fn drop(&mut self) {
        unlink_own_socket(&self.socket_path);
    }
}

/// Install the C++ key watcher, resolve the socket path, and create the
/// forwarding channel.
pub(crate) fn new(instance_ptr: *mut std::os::raw::c_void) -> KeysChannel {
    let (tx, rx) = unbounded_channel::<String>();
    let _ = KEY_TX.set(tx);
    unsafe { shim_install_key_watcher(instance_ptr) };
    KeysChannel { socket_path: socket_path(), rx: Some(rx) }
}

impl KeysChannel {
    /// Return a `'static` future that serves the key socket until cancelled.
    /// Moves the receiver out so `self` can be placed in [`crate::AddonState`]
    /// immediately after this call.
    pub(crate) fn run(&mut self) -> impl Future<Output = std::convert::Infallible> + Send + 'static {
        let path = self.socket_path.clone();
        let rx = self.rx.take().expect("run called twice");
        async move { run_socket(path, rx).await }
    }
}

fn socket_path() -> PathBuf {
    if let Ok(p) = std::env::var("EMOJIZASU_KEY_SOCKET") {
        return PathBuf::from(p);
    }
    let base = std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    base.join(KEY_SOCKET_NAME)
}

#[no_mangle]
pub extern "C" fn rust_key_handler(sym: u32, states: u32, text: *const c_char, text_len: usize, is_release: bool) -> bool {
    let connected = READER_CONNECTED.load(Ordering::Acquire);
    if !connected {
        return false;
    }
    if is_release {
        return true;
    }
    let utf8 = if text.is_null() || text_len == 0 {
        ""
    } else {
        unsafe { std::str::from_utf8(std::slice::from_raw_parts(text as *const u8, text_len)) }
            .unwrap_or("")
    };
    let safe: String = utf8.chars().filter(|c| !c.is_control()).collect();
    if let Some(tx) = KEY_TX.get() {
        let _ = tx.send(format!("{sym} {states} {safe}"));
    }
    true
}

async fn run_socket(path: PathBuf, mut rx: UnboundedReceiver<String>) -> ! {
    let mut backoff = crate::RETRY_INIT;
    loop {
        let _ = std::fs::remove_file(&path);
        match UnixListener::bind(&path) {
            Ok(listener) => {
                if let Ok(mut bound) = BOUND_SOCKET_ID.lock() {
                    *bound = socket_id(&path);
                }
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
