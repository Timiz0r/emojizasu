//! D-Bus control service (picker → addon).
//!
//! Owns the session-bus name and the `/imd` object. Each method drops a [`Msg`]
//! onto the channel drained on the fcitx5 main thread and wakes it via the
//! eventfd, so all fcitx5 interaction stays on that thread.

use std::os::raw::c_void;
use std::os::unix::io::RawFd;
use std::path::PathBuf;
use std::sync::mpsc::SyncSender;

use crate::{load_recent_json, Msg};

#[cfg(not(feature = "test-variant"))]
const DBUS_NAME: &str = "org.emojizasu.InputMethod";
#[cfg(feature = "test-variant")]
const DBUS_NAME: &str = "org.emojizasu.InputMethodTest";

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

#[cfg_attr(
    not(feature = "test-variant"),
    zbus::interface(name = "org.emojizasu.InputMethod")
)]
#[cfg_attr(
    feature = "test-variant",
    zbus::interface(name = "org.emojizasu.InputMethodTest")
)]
impl ImdService {
    /// Commit `text` into the locked/tracked target text field.
    async fn commit(&self, text: String) -> zbus::fdo::Result<()> {
        self.tx
            .try_send(Msg::Commit(text))
            .map_err(|_| zbus::fdo::Error::Failed("channel full".into()))?;
        self.wake();
        Ok(())
    }

    /// Queue text to commit the next time the locked IC regains focus.
    /// Call this then close the picker — the commit fires when the target app
    /// gets focus back after the picker window closes.
    async fn queued_commit(&self, text: String) -> zbus::fdo::Result<()> {
        self.tx
            .try_send(Msg::QueuedCommit(text))
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

async fn connect(service: ImdService) -> zbus::Result<zbus::Connection> {
    zbus::connection::Builder::session()?
        .name(DBUS_NAME)?
        .serve_at("/imd", service)?
        .build()
        .await
}

/// Serve the D-Bus interface, restarting on setup failure with capped backoff.
/// Never returns — the connection is held until the task is cancelled at
/// shutdown, which drops it and releases the name.
pub(crate) async fn run(tx: SyncSender<Msg>, notify_fd: RawFd, recent_path: PathBuf) -> ! {
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
