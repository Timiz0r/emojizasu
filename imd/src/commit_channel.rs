//! D-Bus control service (picker → addon).
//!
//! Owns the session-bus name and the `/imd` object. Each method sends a commit
//! string onto the channel drained on the fcitx5 main thread and wakes it via the
//! eventfd, so all fcitx5 interaction stays on that thread.

use std::ffi::CString;
use std::future::Future;
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::io::RawFd;
use std::path::PathBuf;
use std::sync::mpsc::{sync_channel, Receiver, SyncSender};
use std::sync::Mutex;

use crate::recent;

#[cfg(not(feature = "test-variant"))]
const DBUS_NAME: &str = "org.emojizasu.InputMethod";
#[cfg(feature = "test-variant")]
const DBUS_NAME: &str = "org.emojizasu.InputMethodTest";

extern "C" {
    fn shim_commit_to_target(inst: *mut c_void, text: *const c_char, len: usize);
    fn shim_install_io_event(inst: *mut c_void, fd: c_int) -> *mut c_void;
    fn shim_free_io_event(src: *mut c_void);
}

/// Owns the eventfd, IO event source, commit channel, and recent-emoji path used
/// to deliver picker commits from the async D-Bus service to the fcitx5 main thread.
pub(crate) struct CommitChannel {
    /// eventfd written by the D-Bus service to wake the fcitx5 main thread.
    notify_fd: RawFd,
    /// Commit strings queued by the D-Bus service, drained on the fcitx5 main thread.
    rx: Mutex<Receiver<String>>,
    /// Sender half — cloned into each [`ImdService`] spawned by [`CommitChannel::run`].
    tx: SyncSender<String>,
    /// Handle returned by [`shim_install_io_event`]; freed in [`Drop`].
    io_event_src: *mut c_void,
    /// Path to `recent.json`; updated on commit, read for [`ImdService::get_recent`].
    recent_path: PathBuf,
}

unsafe impl Send for CommitChannel {}

/// Create the eventfd, channel, fcitx5 IO event watcher, and resolve the
/// recent-emoji path. Returns `None` if `eventfd` fails.
pub(crate) fn new(instance_ptr: *mut c_void) -> Option<CommitChannel> {
    let notify_fd = unsafe { libc::eventfd(0, libc::EFD_CLOEXEC | libc::EFD_NONBLOCK) };
    if notify_fd < 0 {
        return None;
    }
    let (tx, rx) = sync_channel(64);
    let io_event_src = unsafe { shim_install_io_event(instance_ptr, notify_fd) };
    Some(CommitChannel {
        notify_fd,
        rx: Mutex::new(rx),
        tx,
        io_event_src,
        recent_path: recent::path(),
    })
}

impl CommitChannel {
    /// Return a `'static` future that serves the D-Bus interface until cancelled.
    /// Clones the sender and copies the fd so `self` can be moved into [`AddonState`]
    /// immediately after this call.
    pub(crate) fn run(&self) -> impl Future<Output = std::convert::Infallible> + Send + 'static {
        let tx = self.tx.clone();
        let notify_fd = self.notify_fd;
        let recent_path = self.recent_path.clone();
        async move { run_loop(tx, notify_fd, recent_path).await }
    }
}

impl Drop for CommitChannel {
    fn drop(&mut self) {
        unsafe {
            shim_free_io_event(self.io_event_src);
            libc::close(self.notify_fd);
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_io_event_handler(_src: *mut c_void, fd: c_int, _flags: u32) -> bool {
    let guard = crate::ADDON_STATE.lock().unwrap();
    let Some(state) = guard.as_ref() else {
        return true;
    };

    let mut buf = [0u8; 8];
    unsafe { libc::read(fd, buf.as_mut_ptr() as *mut c_void, 8) };

    let rx = state.commit_channel.rx.lock().unwrap();
    while let Ok(text) = rx.try_recv() {
        let _ = recent::update(&state.commit_channel.recent_path, &text);
        if let Ok(c) = CString::new(text.as_bytes()) {
            unsafe { shim_commit_to_target(state.instance_ptr, c.as_ptr(), text.len()) };
        }
    }
    true
}

struct ImdService {
    tx: SyncSender<String>,
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

#[zbus::interface(name = "org.emojizasu.InputMethod")]
impl ImdService {
    /// Commit `text` into the currently active text field.
    async fn queued_commit(&self, text: String) -> zbus::fdo::Result<()> {
        self.tx
            .try_send(text)
            .map_err(|_| zbus::fdo::Error::Failed("channel full".into()))?;
        self.wake();
        Ok(())
    }

    /// Return the recently-used list as a JSON array string.
    async fn get_recent(&self) -> zbus::fdo::Result<String> {
        Ok(recent::load_json(&self.recent_path))
    }
}

async fn connect(service: ImdService) -> zbus::Result<zbus::Connection> {
    zbus::connection::Builder::session()?
        .name(DBUS_NAME)?
        .serve_at("/imd", service)?
        .build()
        .await
}

async fn run_loop(tx: SyncSender<String>, notify_fd: RawFd, recent_path: PathBuf) -> ! {
    let mut backoff = crate::RETRY_INIT;
    loop {
        let service = ImdService {
            tx: tx.clone(),
            notify_fd,
            recent_path: recent_path.clone(),
        };
        match connect(service).await {
            Ok(_conn) => {
                eprintln!("emojizasu-imd: D-Bus serving as {DBUS_NAME}");
                std::future::pending::<()>().await;
            }
            Err(e) => {
                eprintln!("emojizasu-imd: D-Bus setup failed: {e}; retrying in {backoff:?}");
                tokio::time::sleep(backoff).await;
                backoff = crate::next_backoff(backoff);
            }
        }
    }
}
