use std::os::raw::c_void;
use std::sync::Mutex;
use std::thread::JoinHandle;

mod commit_channel;
mod keys_channel;
mod recent;

use commit_channel::CommitChannel;
use keys_channel::KeysChannel;

extern "C" {
    fn emojizasu_get_factory() -> *mut c_void;
}

#[no_mangle]
pub extern "C" fn fcitx_addon_factory_instance() -> *mut c_void {
    unsafe { emojizasu_get_factory() }
}

extern "C" {
    fn shim_get_instance(mgr: *mut c_void) -> *mut c_void;
}

pub(crate) static ADDON_STATE: Mutex<Option<AddonState>> = Mutex::new(None);

/// First delay between restart attempts of a background service.
pub(crate) const RETRY_INIT: std::time::Duration = std::time::Duration::from_millis(250);
/// Cap on the (exponential) restart delay, so a permanently-failing service
/// retries at a steady slow rate instead of spinning.
pub(crate) const RETRY_MAX: std::time::Duration = std::time::Duration::from_secs(5);

/// Next backoff: double, clamped to [`RETRY_MAX`].
pub(crate) fn next_backoff(d: std::time::Duration) -> std::time::Duration {
    std::cmp::min(d.saturating_mul(2), RETRY_MAX)
}

/// Owned state for the lifetime of the addon (init → destroy).
pub(crate) struct AddonState {
    /// fcitx5 `Instance*` — passed to shims that need to call back into fcitx5.
    instance_ptr: *mut c_void,
    /// Delivers picker commits from the async D-Bus service to the fcitx5 main thread.
    commit_channel: CommitChannel,
    /// Forwards keystrokes from the fcitx5 key watcher to the connected picker.
    _keys_channel: KeysChannel,
    /// Signals the async worker thread to shut down.
    shutdown_tx: Option<tokio::sync::watch::Sender<bool>>,
    /// Async worker thread handle; joined on [`Drop`].
    thread_handle: Option<JoinHandle<()>>,
}

unsafe impl Send for AddonState {}

impl Drop for AddonState {
    fn drop(&mut self) {
        if let Some(tx) = self.shutdown_tx.take() {
            let _ = tx.send(true);
        }
        if let Some(h) = self.thread_handle.take() {
            let _ = h.join();
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_addon_init(mgr: *mut c_void) {
    let instance_ptr = unsafe { shim_get_instance(mgr) };

    let Some(commit_channel) = commit_channel::new(instance_ptr) else {
        eprintln!("emojizasu-imd: eventfd() failed");
        return;
    };
    let mut keys_channel = keys_channel::new(instance_ptr);

    let (shutdown_tx, shutdown_rx) = tokio::sync::watch::channel(false);
    let dbus_run = commit_channel.run();
    let keys_run = keys_channel.run();

    let handle = std::thread::Builder::new()
        .name("emojizasu".into())
        .spawn(move || {
            tokio::runtime::Runtime::new()
                .unwrap()
                .block_on(async move {
                    let mut shutdown_rx = shutdown_rx;
                    tokio::select! {
                        _ = keys_run => {}
                        _ = dbus_run => {}
                        _ = shutdown_rx.wait_for(|&done| done) => {}
                    }
                });
        })
        .expect("failed to spawn emojizasu thread");

    *ADDON_STATE.lock().unwrap() = Some(AddonState {
        instance_ptr,
        commit_channel,
        _keys_channel: keys_channel,
        shutdown_tx: Some(shutdown_tx),
        thread_handle: Some(handle),
    });
}

#[no_mangle]
pub extern "C" fn rust_addon_destroy() {
    let _ = ADDON_STATE.lock().unwrap().take();
}
