use std::fs::File;
use std::io::{BufRead, BufReader, Read, Seek, SeekFrom, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicU16, Ordering};
use std::thread;

/// The port the audio server is running on (0 means not started)
static AUDIO_SERVER_PORT: AtomicU16 = AtomicU16::new(0);

/// Get the running audio server port
pub fn get_port() -> u16 {
    AUDIO_SERVER_PORT.load(Ordering::Relaxed)
}

/// Start the local audio streaming HTTP server on a background thread.
/// This server properly handles HTTP Range requests, which is required for
/// Android WebView's native MediaPlayer to stream audio files.
pub fn start() {
    thread::spawn(|| {
        // Try a fixed port first, then fall back to alternatives
        let ports_to_try = [16860u16, 16861, 16862, 16863, 16864, 16865];
        let listener = ports_to_try
            .iter()
            .find_map(|&port| TcpListener::bind(format!("127.0.0.1:{}", port)).ok());

        let listener = match listener {
            Some(l) => l,
            None => {
                // Last resort: let OS assign a port
                match TcpListener::bind("127.0.0.1:0") {
                    Ok(l) => l,
                    Err(e) => {
                        eprintln!("Audio server failed to start: {}", e);
                        return;
                    }
                }
            }
        };

        let port = listener.local_addr().map(|a| a.port()).unwrap_or(0);
        AUDIO_SERVER_PORT.store(port, Ordering::Relaxed);
        println!("Audio streaming server started on 127.0.0.1:{}", port);

        for stream in listener.incoming() {
            match stream {
                Ok(stream) => {
                    thread::spawn(move || {
                        if let Err(e) = handle_connection(stream) {
                            eprintln!("Audio server connection error: {}", e);
                        }
                    });
                }
                Err(e) => eprintln!("Audio server accept error: {}", e),
            }
        }
    });
}

fn handle_connection(mut stream: TcpStream) -> Result<(), Box<dyn std::error::Error>> {
    // Set a read timeout to avoid hanging connections
    stream.set_read_timeout(Some(std::time::Duration::from_secs(10)))?;

    let reader_stream = stream.try_clone()?;
    let mut reader = BufReader::new(reader_stream);

    // Read request line
    let mut request_line = String::new();
    reader.read_line(&mut request_line)?;

    let parts: Vec<&str> = request_line.trim().splitn(3, ' ').collect();
    if parts.len() < 2 {
        return send_error(&mut stream, 400, "Bad Request");
    }

    let method = parts[0];
    let raw_url = parts[1];

    // Read all headers
    let mut range_header: Option<String> = None;
    loop {
        let mut line = String::new();
        reader.read_line(&mut line)?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            break;
        }
        let lower = trimmed.to_lowercase();
        if lower.starts_with("range:") {
            range_header = Some(trimmed.to_string());
        }
    }

    // Handle CORS preflight
    if method == "OPTIONS" {
        let response = "HTTP/1.1 204 No Content\r\n\
            Access-Control-Allow-Origin: *\r\n\
            Access-Control-Allow-Methods: GET, HEAD, OPTIONS\r\n\
            Access-Control-Allow-Headers: Range\r\n\
            Access-Control-Expose-Headers: Content-Range, Content-Length, Accept-Ranges\r\n\
            Connection: close\r\n\
            \r\n";
        stream.write_all(response.as_bytes())?;
        return Ok(());
    }

    if method != "GET" && method != "HEAD" {
        return send_error(&mut stream, 405, "Method Not Allowed");
    }

    // Parse the file path from query parameter: /audio?path=<url-encoded-path>
    let file_path = if raw_url.starts_with("/audio?path=") {
        let encoded = &raw_url["/audio?path=".len()..];
        url_decode(encoded)
    } else {
        // Fallback: use the URL path directly (after decoding)
        url_decode(raw_url)
    };

    // Open the file
    let mut file = match File::open(&file_path) {
        Ok(f) => f,
        Err(_) => {
            return send_error(&mut stream, 404, &format!("File not found: {}", file_path));
        }
    };

    let file_size = file.metadata()?.len();
    let content_type = get_mime_type(&file_path);

    // HEAD request: return headers only
    if method == "HEAD" {
        let headers = format!(
            "HTTP/1.1 200 OK\r\n\
             Content-Type: {}\r\n\
             Content-Length: {}\r\n\
             Accept-Ranges: bytes\r\n\
             Access-Control-Allow-Origin: *\r\n\
             Access-Control-Expose-Headers: Content-Range, Content-Length, Accept-Ranges\r\n\
             Connection: close\r\n\
             \r\n",
            content_type, file_size
        );
        stream.write_all(headers.as_bytes())?;
        return Ok(());
    }

    // GET request with or without Range header
    if let Some(ref range) = range_header {
        // Parse Range header
        if let Some((start, end)) = parse_range(range, file_size) {
            let content_length = end - start + 1;
            let headers = format!(
                "HTTP/1.1 206 Partial Content\r\n\
                 Content-Type: {}\r\n\
                 Content-Length: {}\r\n\
                 Content-Range: bytes {}-{}/{}\r\n\
                 Accept-Ranges: bytes\r\n\
                 Access-Control-Allow-Origin: *\r\n\
                 Access-Control-Expose-Headers: Content-Range, Content-Length, Accept-Ranges\r\n\
                 Connection: close\r\n\
                 \r\n",
                content_type, content_length, start, end, file_size
            );
            stream.write_all(headers.as_bytes())?;

            // Seek to start and send the requested range
            file.seek(SeekFrom::Start(start))?;
            let mut remaining = content_length;
            let mut buffer = [0u8; 65536]; // 64KB chunks
            while remaining > 0 {
                let to_read = (remaining as usize).min(buffer.len());
                match file.read(&mut buffer[..to_read]) {
                    Ok(0) => break,
                    Ok(n) => {
                        if stream.write_all(&buffer[..n]).is_err() {
                            break; // Client disconnected
                        }
                        remaining -= n as u64;
                    }
                    Err(_) => break,
                }
            }
        } else {
            // Invalid range
            let headers = format!(
                "HTTP/1.1 416 Range Not Satisfiable\r\n\
                 Content-Range: bytes */{}\r\n\
                 Content-Length: 0\r\n\
                 Connection: close\r\n\
                 \r\n",
                file_size
            );
            stream.write_all(headers.as_bytes())?;
        }
    } else {
        // No Range header: serve the full file
        let headers = format!(
            "HTTP/1.1 200 OK\r\n\
             Content-Type: {}\r\n\
             Content-Length: {}\r\n\
             Accept-Ranges: bytes\r\n\
             Access-Control-Allow-Origin: *\r\n\
             Access-Control-Expose-Headers: Content-Range, Content-Length, Accept-Ranges\r\n\
             Connection: close\r\n\
             \r\n",
            content_type, file_size
        );
        stream.write_all(headers.as_bytes())?;

        let mut buffer = [0u8; 65536];
        loop {
            match file.read(&mut buffer) {
                Ok(0) => break,
                Ok(n) => {
                    if stream.write_all(&buffer[..n]).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    }

    Ok(())
}

/// Parse HTTP Range header into (start, end) byte positions.
/// Supports formats: "bytes=0-499", "bytes=500-", "bytes=-500"
fn parse_range(header: &str, file_size: u64) -> Option<(u64, u64)> {
    // Header format: "Range: bytes=start-end"
    let bytes_eq = header.find("bytes=")?;
    let range_spec = header[bytes_eq + 6..].trim();

    if range_spec.starts_with('-') {
        // Suffix range: last N bytes
        let suffix: u64 = range_spec[1..].parse().ok()?;
        let start = file_size.saturating_sub(suffix);
        Some((start, file_size - 1))
    } else {
        let dash_pos = range_spec.find('-')?;
        let start: u64 = range_spec[..dash_pos].parse().ok()?;
        let end_str = &range_spec[dash_pos + 1..];
        let end = if end_str.is_empty() {
            // Open-ended: from start to end of file
            file_size - 1
        } else {
            let e: u64 = end_str.parse().ok()?;
            e.min(file_size - 1)
        };
        if start > end || start >= file_size {
            return None;
        }
        Some((start, end))
    }
}

/// URL-decode a percent-encoded string
fn url_decode(s: &str) -> String {
    let mut result = Vec::new();
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(byte) =
                u8::from_str_radix(std::str::from_utf8(&bytes[i + 1..i + 3]).unwrap_or(""), 16)
            {
                result.push(byte);
                i += 3;
                continue;
            }
        } else if bytes[i] == b'+' {
            result.push(b' ');
            i += 1;
            continue;
        }
        result.push(bytes[i]);
        i += 1;
    }
    String::from_utf8(result).unwrap_or_else(|_| s.to_string())
}

/// Determine MIME type from file extension
fn get_mime_type(path: &str) -> &'static str {
    let ext = path.rsplit('.').next().unwrap_or("").to_lowercase();
    match ext.as_str() {
        "mp3" => "audio/mpeg",
        "flac" => "audio/flac",
        "wav" => "audio/wav",
        "m4a" => "audio/mp4",
        "ogg" => "audio/ogg",
        "aac" => "audio/aac",
        "wma" => "audio/x-ms-wma",
        _ => "application/octet-stream",
    }
}

fn send_error(
    stream: &mut TcpStream,
    code: u16,
    message: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let body = format!("{} {}", code, message);
    let response = format!(
        "HTTP/1.1 {} {}\r\n\
         Content-Type: text/plain\r\n\
         Content-Length: {}\r\n\
         Access-Control-Allow-Origin: *\r\n\
         Connection: close\r\n\
         \r\n\
         {}",
        code,
        message,
        body.len(),
        body
    );
    stream.write_all(response.as_bytes())?;
    Ok(())
}
