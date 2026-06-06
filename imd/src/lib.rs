use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::io::RawFd;
use std::path::PathBuf;
use std::sync::mpsc::{sync_channel, Receiver};
use std::sync::Mutex;
use std::thread::JoinHandle;

mod dbus;
mod keys;

#[cfg(not(feature = "test-variant"))]
const RECENT_SUBDIR: &str = "emojizasu";
#[cfg(feature = "test-variant")]
const RECENT_SUBDIR: &str = "emojizasu-test";

extern "C" {
    fn emojizasu_get_factory() -> *mut c_void;
}

#[no_mangle]
pub extern "C" fn fcitx_addon_factory_instance() -> *mut c_void {
    unsafe { emojizasu_get_factory() }
}

extern "C" {
    fn shim_get_instance(mgr: *mut c_void) -> *mut c_void;
    fn shim_setup_ic_tracking(inst: *mut c_void, skip_program: *const c_char);
    fn shim_lock_ic();
    fn shim_unlock_ic();
    fn shim_queue_commit(text: *const c_char, len: usize);
    fn shim_commit_to_target(inst: *mut c_void, text: *const c_char, len: usize);
    fn shim_add_io_event(
        inst: *mut c_void,
        fd: c_int,
        cb: extern "C" fn(*mut c_void),
        userdata: *mut c_void,
    ) -> *mut c_void;
    fn shim_free_io_event(src: *mut c_void);
}

pub(crate) enum Msg {
    /// Immediate commit (only works if target IC is currently active).
    Commit(String),
    /// Queue text to commit when the locked IC next regains focus.
    QueuedCommit(String),
    Lock,
    Unlock,
}

/// First delay between restart attempts of a background service.
pub(crate) const RETRY_INIT: std::time::Duration = std::time::Duration::from_millis(250);
/// Cap on the (exponential) restart delay, so a permanently-failing service
/// retries at a steady slow rate instead of spinning.
pub(crate) const RETRY_MAX: std::time::Duration = std::time::Duration::from_secs(5);

/// Next backoff: double, clamped to [`RETRY_MAX`].
pub(crate) fn next_backoff(d: std::time::Duration) -> std::time::Duration {
    std::cmp::min(d.saturating_mul(2), RETRY_MAX)
}

/// Resolve once shutdown has been requested (value set to `true`) or the sender
/// is dropped. Used by background services to break out of their retry loops.
pub(crate) async fn shutdown_requested(rx: &mut tokio::sync::watch::Receiver<bool>) {
    let _ = rx.wait_for(|&done| done).await;
}

struct AddonState {
    instance_ptr: *mut c_void,
    io_event_src: *mut c_void,
    eventfd: RawFd,
    rx: Mutex<Receiver<Msg>>,
    recent_path: PathBuf,
    key_socket_path: PathBuf,
    shutdown_tx: Option<tokio::sync::watch::Sender<bool>>,
    thread_handle: Option<JoinHandle<()>>,
}

unsafe impl Send for AddonState {}
unsafe impl Sync for AddonState {}

impl Drop for AddonState {
    fn drop(&mut self) {
        unsafe {
            shim_free_io_event(self.io_event_src);
            libc::close(self.eventfd);
        }
        let _ = std::fs::remove_file(&self.key_socket_path);
    }
}

// ── IO-event callback (fcitx5 main thread) ───────────────────────────────────

extern "C" fn on_io_event(userdata: *mut c_void) {
    let state = unsafe { &*(userdata as *const AddonState) };

    let mut buf = [0u8; 8];
    unsafe { libc::read(state.eventfd, buf.as_mut_ptr() as *mut c_void, 8) };

    let rx = state.rx.lock().unwrap();
    while let Ok(msg) = rx.try_recv() {
        match msg {
            Msg::Lock => unsafe { shim_lock_ic() },
            Msg::Unlock => unsafe { shim_unlock_ic() },
            Msg::Commit(text) => {
                let _ = update_recent(&state.recent_path, &text);
                if let Ok(c) = CString::new(text.as_bytes()) {
                    unsafe { shim_commit_to_target(state.instance_ptr, c.as_ptr(), text.len()) };
                }
            }
            Msg::QueuedCommit(text) => {
                let _ = update_recent(&state.recent_path, &text);
                if let Ok(c) = CString::new(text.as_bytes()) {
                    unsafe { shim_queue_commit(c.as_ptr(), text.len()) };
                }
            }
        }
    }
}

// ── Recent-list helpers ───────────────────────────────────────────────────────

const MAX_RECENT: usize = 40;

fn recent_path() -> PathBuf {
    if let Ok(path) = std::env::var("EMOJIZASU_RECENT_FILE") {
        return PathBuf::from(path);
    }

    let base = std::env::var("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into()))
                .join(".local/state")
        });
    base.join(RECENT_SUBDIR).join("recent.json")
}

fn load_recent(path: &PathBuf) -> Vec<String> {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

pub(crate) fn load_recent_json(path: &PathBuf) -> String {
    serde_json::to_string(&load_recent(path)).unwrap_or_else(|_| "[]".into())
}

fn update_recent(path: &PathBuf, text: &str) -> std::io::Result<()> {
    let mut list = load_recent(path);
    list.retain(|x| x != text);
    list.insert(0, text.to_string());
    list.truncate(MAX_RECENT);
    if let Some(p) = path.parent() {
        std::fs::create_dir_all(p)?;
    }
    std::fs::write(path, serde_json::to_string(&list).unwrap())?;
    Ok(())
}

// ── Addon entry points ────────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn rust_addon_init(mgr: *mut c_void) -> *mut c_void {
    let instance_ptr = unsafe { shim_get_instance(mgr) };

    let efd = unsafe { libc::eventfd(0, libc::EFD_CLOEXEC | libc::EFD_NONBLOCK) };
    if efd < 0 {
        eprintln!("emojizasu-imd: eventfd() failed");
        return std::ptr::null_mut();
    }

    let (tx, rx) = sync_channel::<Msg>(64);
    let path = recent_path();
    let sock_path = keys::socket_path();

    let (shutdown_tx, shutdown_rx) = tokio::sync::watch::channel(false);

    let mut state = Box::new(AddonState {
        instance_ptr,
        io_event_src: std::ptr::null_mut(),
        eventfd: efd,
        rx: Mutex::new(rx),
        recent_path: path.clone(),
        key_socket_path: sock_path.clone(),
        shutdown_tx: Some(shutdown_tx),
        thread_handle: None,
    });

    let state_ptr = &*state as *const AddonState as *mut c_void;
    state.io_event_src = unsafe { shim_add_io_event(instance_ptr, efd, on_io_event, state_ptr) };

    let skip = CString::new("qs").unwrap();
    unsafe { shim_setup_ic_tracking(instance_ptr, skip.as_ptr()) };
    let key_rx = keys::install_handler();

    let handle = std::thread::Builder::new()
        .name("emojizasu".into())
        .spawn(move || {
            tokio::runtime::Runtime::new()
                .unwrap()
                .block_on(async move {
                    let mut shutdown_rx = shutdown_rx;
                    tokio::select! {
                        _ = keys::run_socket(sock_path, key_rx) => {}
                        _ = dbus::run(tx, efd, path) => {}
                        _ = shutdown_requested(&mut shutdown_rx) => {}
                    }
                });
        })
        .expect("failed to spawn emojizasu thread");

    state.thread_handle = Some(handle);

    Box::into_raw(state) as *mut c_void
}

#[no_mangle]
pub extern "C" fn rust_addon_destroy(state_ptr: *mut c_void) {
    if state_ptr.is_null() {
        return;
    }
    let mut state = unsafe { Box::from_raw(state_ptr as *mut AddonState) };
    if let Some(tx) = state.shutdown_tx.take() {
        let _ = tx.send(true);
    }
    if let Some(h) = state.thread_handle.take() {
        let _ = h.join();
    }
}
