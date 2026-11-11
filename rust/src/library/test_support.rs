use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard};
use uuid::Uuid;

/// The library location is process-global, so library tests take turns.
static LIBRARY_LOCK: Mutex<()> = Mutex::new(());

/// A freshly initialized library in a temp directory, removed on drop.
pub(crate) struct TestLibrary {
    root: PathBuf,
    _guard: MutexGuard<'static, ()>,
}

impl TestLibrary {
    pub fn new() -> Self {
        let guard = LIBRARY_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let root = std::env::temp_dir().join(format!("aetheria-library-test-{}", Uuid::new_v4()));
        super::initialize(root.join("library")).unwrap();
        Self {
            root,
            _guard: guard,
        }
    }

    /// A directory outside the library for source and export files.
    pub fn scratch_dir(&self) -> PathBuf {
        let dir = self.root.join("scratch");
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }
}

impl Drop for TestLibrary {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}
