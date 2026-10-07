# Audio fidelity fixture

`pcm24-stereo.flac` is synthetic, 48 kHz, two channels, 24-bit integer PCM,
10,000 frames. Interleaved sample `n` (0 ≤ n < 20,000) is:

```
((n * 104729) % 16777216) - 8388608
```

No recorded or third-party audio is included. Generated independently of the
player decoder with FFmpeg; tests compare every decoded sample against the formula.
The file also covers seeking inside a compressed codec packet.

Reproduce from the repository root:

```python
import subprocess
samples = [((n * 104729) % (1 << 24)) - (1 << 23) for n in range(20000)]
raw = b''.join((s & 0xffffff).to_bytes(3, 'little') for s in samples)
subprocess.run([
    'ffmpeg', '-v', 'error', '-f', 's24le', '-ar', '48000', '-ac', '2',
    '-i', 'pipe:0', '-c:a', 'flac', '-flags:a', '+bitexact',
    '-fflags', '+bitexact', '-map_metadata', '-1', '-y',
    'rust/tests/fixtures/pcm24-stereo.flac',
], input=raw, check=True)
```

Byte-for-byte container output can vary with FFmpeg version; decoded PCM must not.
