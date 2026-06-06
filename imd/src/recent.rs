use std::path::PathBuf;

#[cfg(not(feature = "test-variant"))]
const SUBDIR: &str = "emojizasu";
#[cfg(feature = "test-variant")]
const SUBDIR: &str = "emojizasu-test";

const MAX: usize = 40;

pub(crate) fn path() -> PathBuf {
    if let Ok(p) = std::env::var("EMOJIZASU_RECENT_FILE") {
        return PathBuf::from(p);
    }
    let base = std::env::var("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into()))
                .join(".local/state")
        });
    base.join(SUBDIR).join("recent.json")
}

pub(crate) fn load_json(path: &PathBuf) -> String {
    serde_json::to_string(&load(path)).unwrap_or_else(|_| "[]".into())
}

pub(crate) fn update(path: &PathBuf, text: &str) -> std::io::Result<()> {
    let mut list = load(path);
    list.retain(|x| x != text);
    list.insert(0, text.to_string());
    list.truncate(MAX);
    if let Some(p) = path.parent() {
        std::fs::create_dir_all(p)?;
    }
    std::fs::write(path, serde_json::to_string_pretty(&list).unwrap())?;
    Ok(())
}

fn load(path: &PathBuf) -> Vec<String> {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}
