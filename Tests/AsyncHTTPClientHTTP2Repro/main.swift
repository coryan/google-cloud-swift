// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ArgumentParser
import AsyncHTTPClient
import Foundation
import GoogleCloudAuth
import NIOCore

actor ReproCounters {
  private(set) var writes: UInt64 = 0
  private(set) var reads: UInt64 = 0
  private(set) var deletes: UInt64 = 0
  private(set) var errors: UInt64 = 0
  private(set) var activeTasks: UInt64 = 0

  func taskStarted() {
    activeTasks &+= 1
  }

  func taskFinished() {
    activeTasks &-= 1
  }

  func recordWrite() {
    writes &+= 1
  }

  func recordRead() {
    reads &+= 1
  }

  func recordDelete() {
    deletes &+= 1
  }

  func recordError() {
    errors &+= 1
  }

  func snapshot() -> (
    writes: UInt64, reads: UInt64, deletes: UInt64, errors: UInt64, activeTasks: UInt64
  ) {
    (writes, reads, deletes, errors, activeTasks)
  }
}

struct ChunkSequence: AsyncSequence, Sendable {
  typealias Element = NIOCore.ByteBuffer

  let buffer: NIOCore.ByteBuffer
  let chunkSize: Int

  struct AsyncIterator: AsyncIteratorProtocol {
    var buffer: NIOCore.ByteBuffer
    let chunkSize: Int

    mutating func next() async throws -> NIOCore.ByteBuffer? {
      if buffer.readableBytes == 0 { return nil }
      let count = Swift.min(chunkSize, buffer.readableBytes)
      return buffer.readSlice(length: count)
    }
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(buffer: buffer, chunkSize: chunkSize)
  }
}

@main
struct AsyncHTTPClientHTTP2Repro: AsyncParsableCommand, Sendable {
  @Option(name: .customLong("bucket-name"), help: "Target GCS bucket name.")
  var bucketName: String

  @Option(name: .customLong("client-count"), help: "Number of AsyncHTTPClient instances.")
  var clientCount: Int = 64

  @Option(name: .customLong("task-count"), help: "Number of concurrent worker tasks.")
  var taskCount: Int = 256

  @Option(name: .customLong("iterations"), help: "Iterations per worker task.")
  var iterations: Int = 500

  @Option(name: .customLong("object-size"), help: "Upload payload size in bytes.")
  var objectSize: Int = 32 * 1024

  @Option(name: .customLong("read-count"), help: "Number of reads per uploaded object.")
  var readCount: Int = 3

  @Option(name: .customLong("rampup-ms"), help: "Rampup delay in milliseconds between tasks.")
  var rampupMs: Int = 500

  @Flag(name: .customLong("no-delete"), help: "Skip deleting objects.")
  var noDelete: Bool = false

  @Flag(name: .customLong("stream-body"), help: "Stream body via HTTPClientRequest.Body.stream.")
  var streamBody: Bool = true

  func run() async throws {
    logToStderr("# Starting AsyncHTTPClientHTTP2Repro")
    logToStderr(
      "# Bucket: \(bucketName), Clients: \(clientCount), Tasks: \(taskCount), Iterations: \(iterations), ReadCount: \(readCount), RampupMs: \(rampupMs)ms"
    )

    // Fetch credentials headers exactly once as requested.
    logToStderr("Fetching credentials headers once...")
    let credentials = try Credentials()
    let authHeaders = try await credentials.headers()
    logToStderr("Credentials headers acquired (\(authHeaders.count) header(s)).")

    let clients: [HTTPClient] = (0..<clientCount).map { _ in
      HTTPClient(eventLoopGroupProvider: .singleton)
    }

    var tempBuffer = ByteBufferAllocator().buffer(capacity: objectSize)
    tempBuffer.writeRepeatingByte(0x5a, count: objectSize)
    let buffer = tempBuffer

    let counters = ReproCounters()
    let startTime = ContinuousClock.now

    let monitorTask = Task {
      var lastTotalOps: UInt64 = 0
      var lastTime = ContinuousClock.now
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        if Task.isCancelled { break }
        let now = ContinuousClock.now
        let (writes, reads, deletes, errors, activeTasks) = await counters.snapshot()
        let totalOps = writes + reads + deletes
        let elapsedTotal = startTime.duration(to: now)
        let elapsedInterval = lastTime.duration(to: now)
        let deltaOps = totalOps - lastTotalOps
        let intervalSeconds =
          Double(elapsedInterval.components.seconds) + Double(
            elapsedInterval.components.attoseconds) / 1e18
        let rate = intervalSeconds > 0 ? Double(deltaOps) / intervalSeconds : 0.0
        let rss = Self.readRssAnon()

        logToStderr(
          "[Elapsed: \(Int(elapsedTotal.components.seconds))s] [\(rss)] [Active: \(activeTasks)] [Writes: \(writes)] [Reads: \(reads)] [Deletes: \(deletes)] [Errors: \(errors)] [Rate: \(String(format: "%.1f", rate)) ops/s]"
        )

        lastTotalOps = totalOps
        lastTime = now
      }
    }
    defer {
      monitorTask.cancel()
    }

    logToStderr("Launching \(taskCount) concurrent tasks...")
    try await withThrowingTaskGroup(of: Void.self) { group in
      for taskIndex in 0..<taskCount {
        let client = clients[taskIndex % clients.count]
        group.addTask {
          if self.rampupMs > 0 && taskIndex > 0 {
            try await Task.sleep(for: .milliseconds(taskIndex * self.rampupMs))
          }
          await self.runWorker(
            taskIndex: taskIndex,
            client: client,
            authHeaders: authHeaders,
            buffer: buffer,
            streamBody: self.streamBody,
            counters: counters
          )
        }
      }
      try await group.waitForAll()
    }

    for client in clients {
      try? await client.shutdown()
    }

    let (finalWrites, finalReads, finalDeletes, finalErrors, _) = await counters.snapshot()
    let totalElapsed = startTime.duration(to: ContinuousClock.now)
    logToStderr(
      "DONE in \(Int(totalElapsed.components.seconds))s. Writes: \(finalWrites), Reads: \(finalReads), Deletes: \(finalDeletes), Errors: \(finalErrors)"
    )
  }

  private func runWorker(
    taskIndex: Int,
    client: HTTPClient,
    authHeaders: [(String, String)],
    buffer: NIOCore.ByteBuffer,
    streamBody: Bool,
    counters: ReproCounters
  ) async {
    await counters.taskStarted()
    defer {
      Task { await counters.taskFinished() }
    }

    let uploadBaseURL = "https://storage.googleapis.com/upload/storage/v1/b/\(bucketName)/o"
    let mediaBaseURL = "https://storage.googleapis.com/storage/v1/b/\(bucketName)/o"

    for _ in 0..<iterations {
      let objectName = Self.randomObjectName()

      // 1. Upload Object
      guard let uploadURL = URL(string: "\(uploadBaseURL)?uploadType=media&name=\(objectName)")
      else {
        await counters.recordError()
        continue
      }

      do {
        var uploadReq = HTTPClientRequest(url: uploadURL.absoluteString)
        uploadReq.method = .POST
        for (name, value) in authHeaders {
          uploadReq.headers.add(name: name, value: value)
        }
        uploadReq.headers.add(name: "Content-Type", value: "application/octet-stream")
        if streamBody {
          let stream = ChunkSequence(buffer: buffer, chunkSize: 16 * 1024)
          uploadReq.body = .stream(stream, length: .known(Int64(buffer.readableBytes)))
        } else {
          uploadReq.body = .bytes(buffer)
        }

        let uploadResp = try await client.execute(uploadReq, timeout: .seconds(30))
        for try await _ in uploadResp.body {}

        if (200..<300).contains(uploadResp.status.code) {
          await counters.recordWrite()
        } else {
          await counters.recordError()
        }
      } catch {
        await counters.recordError()
      }

      // 2. Read Object readCount times
      if readCount > 0 {
        guard let readURL = URL(string: "\(mediaBaseURL)/\(objectName)?alt=media") else {
          await counters.recordError()
          continue
        }

        for _ in 0..<readCount {
          do {
            var readReq = HTTPClientRequest(url: readURL.absoluteString)
            readReq.method = .GET
            for (name, value) in authHeaders {
              readReq.headers.add(name: name, value: value)
            }
            let readResp = try await client.execute(readReq, timeout: .seconds(30))
            for try await _ in readResp.body {}

            if (200..<300).contains(readResp.status.code) {
              await counters.recordRead()
            } else {
              await counters.recordError()
            }
          } catch {
            await counters.recordError()
          }
        }
      }

      // 3. Delete Object (unless disabled)
      if !noDelete {
        guard let deleteURL = URL(string: "\(mediaBaseURL)/\(objectName)") else {
          await counters.recordError()
          continue
        }

        do {
          var deleteReq = HTTPClientRequest(url: deleteURL.absoluteString)
          deleteReq.method = .DELETE
          for (name, value) in authHeaders {
            deleteReq.headers.add(name: name, value: value)
          }
          let deleteResp = try await client.execute(deleteReq, timeout: .seconds(30))
          for try await _ in deleteResp.body {}

          if (200..<300).contains(deleteResp.status.code) || deleteResp.status.code == 404 {
            await counters.recordDelete()
          } else {
            await counters.recordError()
          }
        } catch {
          await counters.recordError()
        }
      }
    }
  }

  private static func randomObjectName() -> String {
    let charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return "http2-repro-" + String((0..<32).map { _ in charset.randomElement()! })
  }

  private static func readRssAnon() -> String {
    guard let content = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) else {
      return "RssAnon: unknown"
    }
    for line in content.split(separator: "\n") {
      if line.hasPrefix("RssAnon:") {
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    return "RssAnon: unknown"
  }
}

private func logToStderr(_ message: String) {
  let line = message.hasSuffix("\n") ? message : message + "\n"
  if let data = line.data(using: .utf8) {
    FileHandle.standardError.write(data)
  }
}
