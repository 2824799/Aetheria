use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_FILE: AtomicU64 = AtomicU64::new(0);
pub(crate) struct TestWav {
    pub path: PathBuf,
}
impl TestWav {
    pub fn pcm(rate: u32, channels: u16, bits: u16, samples: &[i32]) -> Self {
        let data: Vec<u8> = samples
            .iter()
            .flat_map(|s| s.to_le_bytes()[..bits as usize / 8].to_vec())
            .collect();
        Self::write(rate, channels, bits, 1, data)
    }
    pub fn float(rate: u32, channels: u16, samples: &[f64]) -> Self {
        Self::write(
            rate,
            channels,
            64,
            3,
            samples.iter().flat_map(|s| s.to_le_bytes()).collect(),
        )
    }
    fn write(rate: u32, channels: u16, bits: u16, format: u16, data: Vec<u8>) -> Self {
        let path = std::env::temp_dir().join(format!(
            "aetheria-pcm-{}-{}.wav",
            std::process::id(),
            NEXT_FILE.fetch_add(1, Ordering::Relaxed)
        ));
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"RIFF");
        bytes.extend_from_slice(&(36 + data.len() as u32 + (data.len() as u32 % 2)).to_le_bytes());
        bytes.extend_from_slice(b"WAVEfmt ");
        bytes.extend_from_slice(&16u32.to_le_bytes());
        bytes.extend_from_slice(&format.to_le_bytes());
        bytes.extend_from_slice(&channels.to_le_bytes());
        bytes.extend_from_slice(&rate.to_le_bytes());
        bytes.extend_from_slice(&(rate * channels as u32 * bits as u32 / 8).to_le_bytes());
        bytes.extend_from_slice(&(channels * bits / 8).to_le_bytes());
        bytes.extend_from_slice(&bits.to_le_bytes());
        bytes.extend_from_slice(b"data");
        bytes.extend_from_slice(&(data.len() as u32).to_le_bytes());
        bytes.extend(data);
        if bytes.len() % 2 != 0 {
            bytes.push(0);
        }
        std::fs::write(&path, bytes).unwrap();
        Self { path }
    }
    pub fn path(&self) -> &str {
        self.path.to_str().unwrap()
    }
}
impl Drop for TestWav {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}
