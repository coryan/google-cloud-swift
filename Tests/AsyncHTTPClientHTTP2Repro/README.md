# AsyncHTTPClient HTTP/2 Crash Reproducer

This program reproduces and stress-tests the `HTTP2ClientRequestHandler` crash in [`swift-server/async-http-client`](https://github.com/swift-server/async-http-client) using only `AsyncHTTPClient` and `GoogleCloudAuth`.

## Overview

Under high-concurrency HTTP/2 traffic, `HTTP2ClientRequestHandler` can crash with:
```text
AsyncHTTPClient/HTTP2ClientRequestHandler.swift:249: Fatal error: Unexpectedly found nil while unwrapping an Optional value
```

### Crash Mechanics

1. When performing streaming uploads (`HTTPClientRequest.Body.stream`), `HTTPRequestStateMachine` remains in `.running(.streaming(...), .endReceived)` after receiving the server's response.
2. Upon receiving the response end, `HTTP2ClientRequestHandler.run(.forwardResponseEnd)` forwards the response and sets `self.request = nil`.
3. If the server or an intermediary subsequently issues an HTTP/2 stream reset (`RST_STREAM`), a `GOAWAY` frame, or abruptly drops the connection, the channel pipeline triggers `errorCaught(context:error:)`.
4. `HTTPRequestStateMachine.errorHappened(error)` sees that the state is still `.running` and returns action `.failRequest(error, ...)`.
5. `HTTP2ClientRequestHandler.run(.failRequest)` attempts to invoke `self.request!.fail(error)`, which crashes because `self.request` was already cleared.

## Prerequisites

1. **Google Cloud Storage Bucket**:
   A bucket located in the same region as the client or test machine.

2. **Google Cloud Credentials**:
   Application Default Credentials (ADC) must be available:
   ```bash
   gcloud auth application-default login
   ```
   *Note*: The program calls `Credentials.headers()` **exactly once** at startup before launching tasks to ensure credentials acquisition does not interfere with concurrency or timing.

3. **Open File Descriptor Limit**:
   High-concurrency tests require sufficient open file descriptors:
   ```bash
   ulimit -n 32768
   ```

## Command-Line Options

| Option | Default | Description |
| :--- | :--- | :--- |
| `--bucket-name <str>` | *(required)* | Target GCS bucket name. |
| `--client-count <int>` | `64` | Number of `HTTPClient` instances. |
| `--task-count <int>` | `256` | Number of concurrent worker tasks. |
| `--iterations <int>` | `500` | Operations per worker task. |
| `--object-size <int>` | `32768` | Payload size in bytes (32 KiB). |
| `--read-count <int>` | `3` | Number of read operations per upload. |
| `--rampup-ms <int>` | `500` | Milliseconds of delay between starting each task. |
| `--no-delete` | `false` | Skip object deletion step. |
| `--stream-body` | `true` | Stream the upload body using `HTTPClientRequest.Body.stream`. |

## Building

Build the executable in release mode:

```bash
swift build -c release --product AsyncHTTPClientHTTP2Repro
```

## Running the Repro

### 1. High-Concurrency Stress Run (Full Load)

Run 256 concurrent tasks spread across 64 `HTTPClient` instances:

```bash
.build/release/AsyncHTTPClientHTTP2Repro \
  --bucket-name "${BUCKET_NAME}" \
  --client-count 64 \
  --task-count 256 \
  --iterations 500 \
  --rampup-ms 500 \
  --stream-body
```

### 2. Fast Ramp-up (High Pressure)

To ramp up tasks faster and increase the likelihood of connection churn:

```bash
.build/release/AsyncHTTPClientHTTP2Repro \
  --bucket-name "${BUCKET_NAME}" \
  --client-count 64 \
  --task-count 256 \
  --iterations 1000 \
  --rampup-ms 100 \
  --stream-body
```

### Monitoring Progress

The tool periodically prints status updates to `stderr`:

```text
[Elapsed: 30s] [RssAnon: 97660 kB] [Active: 61] [Writes: 3985] [Reads: 11890] [Deletes: 3937] [Errors: 0] [Rate: 1500.1 ops/s]
```

- `RssAnon`: Current anonymous resident set memory usage from `/proc/self/status`.
- `Active`: Number of active concurrent tasks currently running.
- `Writes / Reads / Deletes`: Cumulative operation counts.
- `Rate`: Throughput in operations per second.

## Local Deterministic Reproducer (Without Google Cloud)

Because GCS normal operation rarely emits premature `RST_STREAM` frames on clean uploads, reproducing the crash against live GCS is probabilistic and depends on transient network/proxy resets.

For a **100% deterministic reproduction in under 100ms** without needing a GCS bucket or cloud credentials, use the companion test target:

```bash
swift run HTTP2ServerCrashRepro
```

This starts a local in-process HTTP/2 server (`127.0.0.1`) that emits a `200 OK` followed immediately by a controlled `RST_STREAM` frame to trigger the fatal error on demand.
