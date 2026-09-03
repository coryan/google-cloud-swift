# HTTP2ServerCrashRepro

A self-contained, in-process reproducer for the `HTTP2ClientRequestHandler` crash in [`swift-server/async-http-client`](https://github.com/swift-server/async-http-client). It runs completely locally on `127.0.0.1` with no external dependencies or Google Cloud calls.

## How to Run

```bash
swift run HTTP2ServerCrashRepro
```

By default, the mock server sends `200 OK` followed immediately by an HTTP/2 `RST_STREAM` frame. To test with a `GOAWAY` frame instead:

```bash
swift run HTTP2ServerCrashRepro goaway
```

## How It Crashes

The program crashes deterministically in milliseconds with `SIGILL`:

```text
AsyncHTTPClient/HTTP2ClientRequestHandler.swift:249: Fatal error: Unexpectedly found nil while unwrapping an Optional value
Response received: 200 OK

💣 Program crashed: Signal 4: Backtracing from 0x...
```

### Root Cause

1. The client initiates an HTTP/2 request with a streaming body (`HTTPClientRequest.Body.stream`).
2. The server returns response headers (`200 OK`) and marks the response stream finished (`endStream: true`).
3. `HTTP2ClientRequestHandler.run(.forwardResponseEnd)` delivers the response to the caller and clears its reference:
   ```swift
   self.request = nil
   ```
4. While the client's request body stream is still in-flight or finalizing, the server issues a `RST_STREAM` frame.
5. SwiftNIO forwards the stream reset to `errorCaught`.
6. Because the request state machine was still in `.running(.streaming(...), .endReceived)`, it transitions to `.failed` and returns action `.failRequest(error, ...)`.
7. `HTTP2ClientRequestHandler.run(.failRequest)` unconditionally force-unwraps `self.request!`:
   ```swift
   case .failRequest(let error, let finalAction):
       self.request!.fail(error) // Crashes: self.request is nil
   ```

## Why It Is Relevant for Google Cloud

Google Cloud SDKs (such as `GoogleCloudStorage`) rely on `AsyncHTTPClient` over HTTP/2 for uploads and downloads:

- **Streaming Uploads**: Both simple multipart uploads and resumable uploads stream request bodies via `HTTPClientRequest.Body.stream`.
- **Early Server Responses & Preconditions**: When an upload fails early—such as a `412 Precondition Failed` (e.g., `ifGenerationMatch: 0`), quota limit, or authentication rejection—Google Cloud Storage may close or reset the stream before the client finishes sending all request body bytes.
- **Connection Churn & Resets**: In high-concurrency environments or when connections are reclaimed, server-side resets (`RST_STREAM`) or connection closures cause `AsyncHTTPClient` to trigger this unhandled fatal unwrap rather than throwing a normal, catchable Swift error. This abruptly terminates the entire process instead of allowing the SDK's retry or backoff policies to recover.

## Why HTTPS / Self-Signed TLS Is Used

`AsyncHTTPClient` does not support cleartext HTTP/2 (`h2c` / prior knowledge). For all `http://` schemes, `AsyncHTTPClient` unconditionally defaults to HTTP/1.1 (`HTTPConnectionPool+Factory.swift:256`) and never initializes `HTTP2ClientRequestHandler`. Therefore, negotiating HTTP/2 requires HTTPS with ALPN (`"h2"`), which the reproducer configures using an ephemeral in-process self-signed certificate with `certificateVerification = .none`.
