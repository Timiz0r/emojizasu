use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::io::RawFd;
use std::path::PathBuf;
use std::sync::mpsc::{sync_channel, Receiver, SyncSender};
use std::sync::Mutex;
use std::thread::JoinHandle;

// ── Build variant ─────────────────────────────────────────────────────────────
// Two addons are built from this source, differing only in D-Bus name and
// recent-list path, so the test harness can drive an isolated service without
// touching the production one. Selected by the `test-variant` cargo feature.
#[cfg(not(feature = "test-variant"))]
const DBUS_NAME: &str = "org.emojizasu.InputMethod";
#[cfg(not(feature = "test-variant"))]
const RECENT_SUBDIR: &str = "emojizasu";

#[cfg(feature = "test-variant")]
const DBUS_NAME: &str = "org.emojizasu.InputMethodTest";
#[cfg(feature = "test-variant")]
const RECENT_SUBDIR: &str = "emojizasu-test";

// ── fcitx5 addon entry point ──────────────────────────────────────────────────
extern "C" {
    fn emojizasu_get_factory() -> *mut c_void;
}

#[no_mangle]
pub extern "C" fn fcitx_addon_factory_instance() -> *mut c_void {
    unsafe { emojizasu_get_factory() }
}

// ── C shims declared in cpp/shims.h ──────────────────────────────────────────

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

// ── Message channel ───────────────────────────────────────────────────────────

enum Msg {
    /// Immediate commit (only works if target IC is currently active).
    Commit(String),
    /// Queue text to commit when the locked IC next regains focus.
    QueuedCommit(String),
    Lock,
    Unlock,
}

// ── Addon state ───────────────────────────────────────────────────────────────

struct AddonState {
    instance_ptr: *mut c_void,
    io_event_src: *mut c_void,
    eventfd: RawFd,
    rx: Mutex<Receiver<Msg>>,
    recent_path: PathBuf,
    shutdown_tx: Option<tokio::sync::oneshot::Sender<()>>,
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
            Msg::Lock   => unsafe { shim_lock_ic() },
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

// ── D-Bus service (tokio thread) ─────────────────────────────────────────────

struct ImdService {
    tx: SyncSender<Msg>,
    notify_fd: RawFd,
    recent_path: PathBuf,
}

impl ImdService {
    fn wake(&self) {
        let val: u64 = 1;
        unsafe {
            libc::write(
                self.notify_fd,
                &val as *const u64 as *const c_void,
                std::mem::size_of::<u64>(),
            )
        };
    }
}

#[cfg_attr(not(feature = "test-variant"), zbus::interface(name = "org.emojizasu.InputMethod"))]
#[cfg_attr(feature = "test-variant", zbus::interface(name = "org.emojizasu.InputMethodTest"))]
impl ImdService {
    /// Commit `text` into the locked/tracked target text field.
    async fn commit(&self, text: String) -> zbus::fdo::Result<()> {
        self.tx.try_send(Msg::Commit(text))
            .map_err(|_| zbus::fdo::Error::Failed("channel full".into()))?;
        self.wake();
        Ok(())
    }

    /// Queue text to commit the next time the locked IC regains focus.
    /// Call this then close the picker — the commit fires when the target app
    /// gets focus back after the picker window closes.
    async fn queued_commit(&self, text: String) -> zbus::fdo::Result<()> {
        self.tx.try_send(Msg::QueuedCommit(text))
            .map_err(|_| zbus::fdo::Error::Failed("channel full".into()))?;
        self.wake();
        Ok(())
    }

    /// Call when the picker becomes visible — locks the commit target to
    /// whatever text field had focus before the picker stole it.
    async fn register_self(&self) -> zbus::fdo::Result<()> {
        let _ = self.tx.try_send(Msg::Lock);
        self.wake();
        Ok(())
    }

    /// Call when the picker is hidden — releases the lock.
    async fn unregister_self(&self) -> zbus::fdo::Result<()> {
        let _ = self.tx.try_send(Msg::Unlock);
        self.wake();
        Ok(())
    }

    /// Return the recently-used list as a JSON array string.
    async fn get_recent(&self) -> zbus::fdo::Result<String> {
        Ok(load_recent_json(&self.recent_path))
    }
}

async fn run_dbus(
    tx: SyncSender<Msg>,
    notify_fd: RawFd,
    recent_path: PathBuf,
    shutdown_rx: tokio::sync::oneshot::Receiver<()>,
) {
    let service = ImdService { tx, notify_fd, recent_path };

    let conn = match zbus::connection::Builder::session()
        .unwrap()
        .name(DBUS_NAME)
        .unwrap()
        .serve_at("/imd", service)
        .unwrap()
        .build()
        .await
    {
        Ok(c) => c,
        Err(e) => { eprintln!("emojizasu-imd: D-Bus setup failed: {e}"); return; }
    };

    let _ = shutdown_rx.await;
    drop(conn);
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

fn load_recent_json(path: &PathBuf) -> String {
    serde_json::to_string(&load_recent(path)).unwrap_or_else(|_| "[]".into())
}

fn update_recent(path: &PathBuf, text: &str) -> std::io::Result<()> {
    let mut list = load_recent(path);
    list.retain(|x| x != text);
    list.insert(0, text.to_string());
    list.truncate(MAX_RECENT);
    if let Some(p) = path.parent() { std::fs::create_dir_all(p)?; }
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

    let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();

    let mut state = Box::new(AddonState {
        instance_ptr,
        io_event_src: std::ptr::null_mut(),
        eventfd: efd,
        rx: Mutex::new(rx),
        recent_path: path.clone(),
        shutdown_tx: Some(shutdown_tx),
        thread_handle: None,
    });

    let state_ptr = &*state as *const AddonState as *mut c_void;
    state.io_event_src = unsafe { shim_add_io_event(instance_ptr, efd, on_io_event, state_ptr) };

    let skip = CString::new("qs").unwrap();
    unsafe { shim_setup_ic_tracking(instance_ptr, skip.as_ptr()) };

    let handle = std::thread::Builder::new()
        .name("emojizasu-dbus".into())
        .spawn(move || {
            tokio::runtime::Runtime::new().unwrap()
                .block_on(run_dbus(tx, efd, path, shutdown_rx));
        })
        .expect("failed to spawn dbus thread");

    state.thread_handle = Some(handle);

    Box::into_raw(state) as *mut c_void
}

#[no_mangle]
pub extern "C" fn rust_addon_destroy(state_ptr: *mut c_void) {
    if state_ptr.is_null() { return; }
    let mut state = unsafe { Box::from_raw(state_ptr as *mut AddonState) };
    if let Some(tx) = state.shutdown_tx.take() { let _ = tx.send(()); }
    if let Some(h) = state.thread_handle.take() { let _ = h.join(); }
}
